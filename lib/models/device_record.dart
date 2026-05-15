import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/beacon_parsers.dart';

class RssiSample {
  final DateTime time;
  final int rssi;
  const RssiSample(this.time, this.rssi);
}

/// One Bluetooth device's accumulated state across the current scan session.
class DeviceRecord {
  DeviceRecord({
    required this.id,
    required this.name,
    required this.firstSeen,
  })  : lastSeen = firstSeen,
        currentRssi = 0,
        samples = <RssiSample>[];

  static const int maxSamples = 5000; // ~80 min at 1 Hz, ~8 min at 10 Hz

  final DeviceIdentifier id;
  String name;
  String? localName;
  int currentRssi;
  int? txPower;
  int? manufacturerId;
  List<Guid> serviceUuids = const [];
  List<int> rawManufacturerBytes = const [];
  Map<String, List<int>> serviceData = const {};
  DateTime firstSeen;
  DateTime lastSeen;
  final List<RssiSample> samples;

  void update(ScanResult r) {
    final adv = r.advertisementData;
    if (adv.advName.isNotEmpty) {
      localName = adv.advName;
      name = adv.advName;
    } else if (r.device.platformName.isNotEmpty) {
      name = r.device.platformName;
    }
    currentRssi = r.rssi;
    txPower = adv.txPowerLevel;
    serviceUuids = adv.serviceUuids;

    if (adv.manufacturerData.isNotEmpty) {
      final first = adv.manufacturerData.entries.first;
      manufacturerId = first.key;
      rawManufacturerBytes = first.value;
    }

    if (adv.serviceData.isNotEmpty) {
      serviceData = {
        for (final e in adv.serviceData.entries) e.key.str.toLowerCase(): e.value,
      };
    }

    final now = DateTime.now();
    lastSeen = now;
    samples.add(RssiSample(now, r.rssi));
    if (samples.length > maxSamples) {
      samples.removeRange(0, samples.length - maxSamples);
    }
  }

  Duration get sinceLastSeen => DateTime.now().difference(lastSeen);

  bool isOfflineFor(Duration threshold) => sinceLastSeen >= threshold;

  int? get minRssi {
    if (samples.isEmpty) return null;
    return samples.map((s) => s.rssi).reduce((a, b) => a < b ? a : b);
  }

  int? get maxRssi {
    if (samples.isEmpty) return null;
    return samples.map((s) => s.rssi).reduce((a, b) => a > b ? a : b);
  }

  double? get avgRssi {
    if (samples.isEmpty) return null;
    final total = samples.fold<int>(0, (sum, s) => sum + s.rssi);
    return total / samples.length;
  }

  /// Average of the most recent [window] samples (for smoothing the gauge).
  /// Falls back to currentRssi if there's less data than the window asks for.
  int smoothedRssi(int window) {
    if (window <= 1 || samples.isEmpty) return currentRssi;
    final n = window > samples.length ? samples.length : window;
    final start = samples.length - n;
    var sum = 0;
    for (var i = start; i < samples.length; i++) {
      sum += samples[i].rssi;
    }
    return (sum / n).round();
  }

  /// +1 = signal getting stronger, -1 = weaker, 0 = stable or not enough data.
  /// Compares the average of the older half of recent samples to the newer half
  /// within roughly the last [window] seconds.
  int trend({Duration window = const Duration(seconds: 8)}) {
    if (samples.length < 6) return 0;
    final cutoff = DateTime.now().subtract(window);
    final recent = samples.where((s) => s.time.isAfter(cutoff)).toList();
    if (recent.length < 6) return 0;
    final mid = recent.length ~/ 2;
    final older = recent.take(mid).map((s) => s.rssi).reduce((a, b) => a + b) / mid;
    final newer = recent.skip(mid).map((s) => s.rssi).reduce((a, b) => a + b) /
        (recent.length - mid);
    final delta = newer - older;
    if (delta > 2) return 1;
    if (delta < -2) return -1;
    return 0;
  }

  /// Parsed iBeacon data if the advertisement matches the iBeacon prefix.
  IBeacon? get iBeacon {
    if (manufacturerId == null) return null;
    return parseIBeacon(
      companyId: manufacturerId!,
      bytes: rawManufacturerBytes,
    );
  }

  /// Parsed Eddystone frame if the device broadcasts the Eddystone service.
  Eddystone? get eddystone {
    const eddystoneUuid = '0000feaa-0000-1000-8000-00805f9b34fb';
    final data = serviceData[eddystoneUuid];
    if (data == null) return null;
    return parseEddystone(data);
  }

  /// CSV export of all samples in the current session.
  String toCsv() {
    final buf = StringBuffer('timestamp_iso,rssi_dbm\n');
    for (final s in samples) {
      buf.writeln('${s.time.toIso8601String()},${s.rssi}');
    }
    return buf.toString();
  }
}
