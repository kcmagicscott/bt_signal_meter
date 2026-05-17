import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/direction_fix.dart';
import '../scanner_state.dart';
import 'device_memory.dart';

/// Drives the live "point at the device" experience. Once started, the
/// service keeps collecting (heading, RSSI) pairs indefinitely and exposes
/// a [currentEstimate] computed from whatever data exists right now — no
/// "minimum rotation" gate. The user finalizes with [finalize] when they
/// believe they've found the device, or clears and tries again with
/// [resetSamples].
///
/// Accuracy techniques layered in:
///   - 16 buckets × 22.5° (matched to BLE 1–5 Hz scan rate so each
///     bucket gets enough samples to be meaningful)
///   - per-bucket median RSSI (robust to multipath spikes)
///   - circular Gaussian smoothing across neighbours
///   - parabolic peak interpolation for sub-bucket bearing precision
///   - velocity gating (skip samples while rotating too fast for the
///     compass to keep up)
///   - lost-signal rejection (drop RSSI >= 0 or < -100 dBm)
class DirectionFinder extends ChangeNotifier {
  DirectionFinder._();
  static final DirectionFinder instance = DirectionFinder._();

  static const int _bucketCount = 16;
  static const double _bucketDeg = 360.0 / _bucketCount;
  // Safety cap — even if the user forgets to dismiss the sheet, we don't
  // want a streaming sensor subscription running forever.
  static const Duration _maxDuration = Duration(minutes: 5);
  static const List<double> _smoothingKernel = [0.10, 0.25, 0.30, 0.25, 0.10];
  static const double _maxAngularVelocityDegPerSec = 120;

  DeviceIdentifier? _target;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  DateTime? _startedAt;

  double? _currentHeading;
  double? _lastHeading;
  double _totalRotationDeg = 0;
  int? _currentRssi;
  int _lastSampleIdx = 0;

  final List<List<int>> _samples =
      List.generate(_bucketCount, (_) => <int>[]);

  DateTime? _prevHeadingTime;
  double _smoothedVelocityDegPerSec = 0;

  DirectionFix? lastFix;
  bool sensorUnavailable = false;

  DeviceIdentifier? get target => _target;
  bool get isSweeping => _target != null;
  double? get currentHeading => _currentHeading;
  int? get currentRssi => _currentRssi;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  int get bucketsCovered => _samples.where((b) => b.isNotEmpty).length;
  double get coverage => bucketsCovered / _bucketCount;

  double get totalRotationDeg => _totalRotationDeg;

  Set<int> get coveredBuckets {
    final s = <int>{};
    for (var i = 0; i < _bucketCount; i++) {
      if (_samples[i].isNotEmpty) s.add(i);
    }
    return s;
  }

  int get bucketCount => _bucketCount;
  double get bucketSizeDeg => _bucketDeg;

  int get totalSamples {
    var t = 0;
    for (final b in _samples) {
      t += b.length;
    }
    return t;
  }

  /// Live estimate from whatever data exists right now. Returns null when
  /// there isn't enough information to make a meaningful call.
  DirectionFix? get currentEstimate => _computeFix();

  Future<void> start(DeviceIdentifier id) async {
    if (isSweeping) await cancel();
    _target = id;
    _startedAt = DateTime.now();
    sensorUnavailable = false;
    lastFix = null;
    for (var i = 0; i < _bucketCount; i++) {
      _samples[i].clear();
    }
    _currentHeading = null;
    _lastHeading = null;
    _totalRotationDeg = 0;
    _currentRssi = null;
    _prevHeadingTime = null;
    _smoothedVelocityDegPerSec = 0;
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
      final normalized = h < 0 ? h + 360 : h;
      _updateRotationAndVelocity(normalized);
      _currentHeading = normalized;
      _ingestNewSamples();
      notifyListeners();
    });

    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _ingestNewSamples();
      notifyListeners();
    });

    _timeoutTimer = Timer(_maxDuration, () => cancel());
    notifyListeners();
  }

  /// Clear collected samples but keep the streams running. Useful when the
  /// user has been rotating in a noisy spot and wants to start fresh
  /// without dismissing and re-opening the sheet.
  void resetSamples() {
    for (var i = 0; i < _bucketCount; i++) {
      _samples[i].clear();
    }
    _totalRotationDeg = 0;
    _lastHeading = null;
    _prevHeadingTime = null;
    _smoothedVelocityDegPerSec = 0;
    final rec = _target == null
        ? null
        : ScannerState.instance.deviceFor(_target!);
    _lastSampleIdx = rec?.samples.length ?? 0;
    notifyListeners();
  }

  /// User tapped "Found it!". Saves the current best estimate (if any) and
  /// stops the streams.
  Future<DirectionFix?> finalize() async {
    final id = _target;
    if (id == null) return null;
    final fix = _computeFix();
    _stopStreams();
    if (fix != null) {
      lastFix = fix;
      await DeviceMemory.instance.setDirection(id.str, fix);
    }
    _target = null;
    _startedAt = null;
    notifyListeners();
    return fix;
  }

  Future<void> cancel() async {
    _stopStreams();
    _target = null;
    _startedAt = null;
    notifyListeners();
  }

  void _updateRotationAndVelocity(double h) {
    final now = DateTime.now();
    final prev = _lastHeading;
    final prevT = _prevHeadingTime;
    if (prev != null) {
      var delta = h - prev;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      _totalRotationDeg += delta.abs();
      if (prevT != null) {
        final dt = now.difference(prevT).inMicroseconds / 1e6;
        if (dt > 0.001) {
          final inst = delta.abs() / dt;
          _smoothedVelocityDegPerSec =
              inst * 0.4 + _smoothedVelocityDegPerSec * 0.6;
        }
      }
    }
    _lastHeading = h;
    _prevHeadingTime = now;
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
  }

  void _addSample(double headingDeg, int rssi) {
    if (rssi >= 0 || rssi < -100) return;
    if (_smoothedVelocityDegPerSec > _maxAngularVelocityDegPerSec) return;
    var b = (headingDeg / _bucketDeg).floor();
    if (b < 0) b = 0;
    if (b >= _bucketCount) b = _bucketCount - 1;
    _samples[b].add(rssi);
  }

  static double _median(List<int> values) {
    final sorted = List<int>.from(values)..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2].toDouble();
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  List<double?> _smoothedMedians() {
    final raw = List<double?>.filled(_bucketCount, null);
    for (var i = 0; i < _bucketCount; i++) {
      if (_samples[i].isNotEmpty) raw[i] = _median(_samples[i]);
    }
    final smoothed = List<double?>.filled(_bucketCount, null);
    for (var i = 0; i < _bucketCount; i++) {
      var sum = 0.0;
      var w = 0.0;
      for (var k = 0; k < _smoothingKernel.length; k++) {
        final j = (i + k - 2 + _bucketCount) % _bucketCount;
        final v = raw[j];
        if (v != null) {
          sum += v * _smoothingKernel[k];
          w += _smoothingKernel[k];
        }
      }
      if (w > 0) smoothed[i] = sum / w;
    }
    return smoothed;
  }

  int? _peakBucket(List<double?> smoothed) {
    var best = -1;
    var bestVal = -1e9;
    for (var i = 0; i < _bucketCount; i++) {
      final v = smoothed[i];
      if (v == null) continue;
      if (v > bestVal) {
        bestVal = v;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  double _interpolatedBearing(int peakB, List<double?> smoothed) {
    final left = smoothed[(peakB - 1 + _bucketCount) % _bucketCount];
    final center = smoothed[peakB];
    final right = smoothed[(peakB + 1) % _bucketCount];
    if (left == null || center == null || right == null) {
      return (peakB + 0.5) * _bucketDeg;
    }
    final denom = left - 2 * center + right;
    if (denom.abs() < 1e-6) return (peakB + 0.5) * _bucketDeg;
    var offset = 0.5 * (left - right) / denom;
    offset = offset.clamp(-0.5, 0.5);
    return ((peakB + 0.5 + offset) * _bucketDeg + 360) % 360;
  }

  DirectionFix? _computeFix() {
    final samples = totalSamples;
    if (samples < 6) return null;

    final smoothed = _smoothedMedians();
    final peak = _peakBucket(smoothed);
    if (peak == null) return null;

    final bestMean = smoothed[peak]!;
    var worstMean = bestMean;
    var covered = 0;
    for (final v in smoothed) {
      if (v == null) continue;
      covered++;
      if (v < worstMean) worstMean = v;
    }
    if (covered < 3) return null;

    final bearing = _interpolatedBearing(peak, smoothed);
    final range = (bestMean - worstMean).round();

    // Confidence blend:
    //   - swing (45%): peak-to-trough range in dB
    //   - cluster (25%): adjacent buckets staying near the peak
    //   - samples (30%): how much data backs the peak bucket
    final rangeC = (range / 18.0).clamp(0.0, 1.0);

    final threshold = bestMean - (bestMean - worstMean) * 0.25;
    var clusterSize = 0;
    for (var k = 1; k <= 2; k++) {
      final v1 = smoothed[(peak + k) % _bucketCount];
      final v2 = smoothed[(peak - k + _bucketCount) % _bucketCount];
      if (v1 != null && v1 >= threshold) clusterSize++;
      if (v2 != null && v2 >= threshold) clusterSize++;
    }
    final clusterC = (clusterSize / 4.0).clamp(0.0, 1.0);

    final peakSamples = _samples[peak].length;
    final samplesC = (peakSamples / 12.0).clamp(0.0, 1.0);

    final confidence =
        (rangeC * 0.45 + clusterC * 0.25 + samplesC * 0.30).clamp(0.0, 1.0);

    return DirectionFix(
      time: DateTime.now(),
      bearingDeg: bearing,
      confidence: confidence,
      peakRssi: bestMean.round(),
      rangeDb: range,
      sampleCount: samples,
    );
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
