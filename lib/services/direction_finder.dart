import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/direction_fix.dart';
import '../scanner_state.dart';
import 'device_memory.dart';

/// Drives the "rotate to find" sweep. The user holds the phone flat and
/// turns through ~360°; we tag each RSSI sample with the current compass
/// heading. Their body shadows the radio enough that the heading where the
/// signal peaks correlates with the device's bearing — not as precise as
/// Apple's UWB arrow, but useful for narrowing direction.
class DirectionFinder extends ChangeNotifier {
  DirectionFinder._();
  static final DirectionFinder instance = DirectionFinder._();

  static const int _bucketCount = 24;
  static const double _bucketDeg = 360.0 / _bucketCount;
  static const int _minBucketsCovered = 20;
  static const Duration _maxDuration = Duration(seconds: 15);

  DeviceIdentifier? _target;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  DateTime? _startedAt;

  double? _currentHeading;
  int? _currentRssi;
  int _lastSampleIdx = 0;

  final List<double> _sum = List.filled(_bucketCount, 0);
  final List<int> _count = List.filled(_bucketCount, 0);

  /// Set when the most recent sweep produced a result; consumers should
  /// check [DeviceMemory.directionFor] for the persisted version.
  DirectionFix? lastFix;

  /// True if the underlying compass stream is null (no magnetometer on
  /// this device). Set after [start] is attempted.
  bool sensorUnavailable = false;

  DeviceIdentifier? get target => _target;
  bool get isSweeping => _target != null;
  double? get currentHeading => _currentHeading;
  int? get currentRssi => _currentRssi;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  int get bucketsCovered => _count.where((c) => c > 0).length;
  double get coverage => bucketsCovered / _bucketCount;

  /// Returns the set of bucket indices that have at least one sample.
  /// Useful for rendering a coverage arc.
  Set<int> get coveredBuckets {
    final s = <int>{};
    for (var i = 0; i < _bucketCount; i++) {
      if (_count[i] > 0) s.add(i);
    }
    return s;
  }

  int get bucketCount => _bucketCount;
  double get bucketSizeDeg => _bucketDeg;

  Future<void> start(DeviceIdentifier id) async {
    if (isSweeping) await cancel();
    _target = id;
    _startedAt = DateTime.now();
    sensorUnavailable = false;
    lastFix = null;
    for (var i = 0; i < _bucketCount; i++) {
      _sum[i] = 0;
      _count[i] = 0;
    }
    _currentHeading = null;
    _currentRssi = null;
    final rec = ScannerState.instance.deviceFor(id);
    _lastSampleIdx = rec?.samples.length ?? 0;

    final stream = FlutterCompass.events;
    if (stream == null) {
      sensorUnavailable = true;
      _target = null;
      _startedAt = null;
      notifyListeners();
      return;
    }
    _compassSub = stream.listen((e) {
      final h = e.heading;
      if (h == null) return;
      _currentHeading = h < 0 ? h + 360 : h;
      _ingestNewSamples();
      notifyListeners();
    });

    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _ingestNewSamples();
      notifyListeners();
    });

    _timeoutTimer = Timer(_maxDuration, () => _finish());
    notifyListeners();
  }

  void _ingestNewSamples() {
    final id = _target;
    if (id == null) return;
    final rec = ScannerState.instance.deviceFor(id);
    if (rec == null) return;
    final h = _currentHeading;
    if (h == null) return;
    for (var i = _lastSampleIdx; i < rec.samples.length; i++) {
      final s = rec.samples[i];
      _addSample(h, s.rssi);
      _currentRssi = s.rssi;
    }
    _lastSampleIdx = rec.samples.length;
    if (bucketsCovered >= _minBucketsCovered) {
      _finish();
    }
  }

  void _addSample(double headingDeg, int rssi) {
    var b = (headingDeg / _bucketDeg).floor();
    if (b < 0) b = 0;
    if (b >= _bucketCount) b = _bucketCount - 1;
    _sum[b] += rssi;
    _count[b] += 1;
  }

  Future<void> _finish() async {
    final id = _target;
    if (id == null) return;
    _stopStreams();

    final fix = _computeFix();
    if (fix != null) {
      lastFix = fix;
      await DeviceMemory.instance.setDirection(id.str, fix);
    }
    _target = null;
    _startedAt = null;
    notifyListeners();
  }

  DirectionFix? _computeFix() {
    var bestBucket = -1;
    var bestMean = -200.0;
    var worstMean = 1.0;
    var totalSamples = 0;
    for (var i = 0; i < _bucketCount; i++) {
      if (_count[i] == 0) continue;
      final m = _sum[i] / _count[i];
      totalSamples += _count[i];
      if (m > bestMean) {
        bestMean = m;
        bestBucket = i;
      }
      if (m < worstMean) worstMean = m;
    }
    if (bestBucket < 0 || totalSamples < 6) return null;
    final bearing = (bestBucket + 0.5) * _bucketDeg;
    final range = (bestMean - worstMean).round();
    // A 20 dB swing across rotation is unambiguous; 2 dB is noise.
    final confidence = (range / 20.0).clamp(0.0, 1.0);
    return DirectionFix(
      time: DateTime.now(),
      bearingDeg: bearing,
      confidence: confidence,
      peakRssi: bestMean.round(),
      rangeDb: range,
      sampleCount: totalSamples,
    );
  }

  Future<void> cancel() async {
    _stopStreams();
    _target = null;
    _startedAt = null;
    notifyListeners();
  }

  void _stopStreams() {
    _compassSub?.cancel();
    _compassSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}
