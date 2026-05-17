import 'package:bt_signal_meter/models/device_record.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceRecord _record() => DeviceRecord(
      id: const DeviceIdentifier('AA:BB:CC:DD:EE:FF'),
      name: 'Test',
      firstSeen: DateTime(2026, 1, 1),
    );

void main() {
  group('DeviceRecord stats', () {
    test('empty record has null stats', () {
      final r = _record();
      expect(r.avgRssi, isNull);
      expect(r.minRssi, isNull);
      expect(r.maxRssi, isNull);
      expect(r.samples, isEmpty);
    });

    test('manual samples produce correct min/max/avg', () {
      final r = _record();
      r.samples.add(RssiSample(DateTime(2026), -60));
      r.samples.add(RssiSample(DateTime(2026), -70));
      r.samples.add(RssiSample(DateTime(2026), -50));
      expect(r.minRssi, -70);
      expect(r.maxRssi, -50);
      expect(r.avgRssi, closeTo(-60.0, 0.001));
    });

    test('CSV header is fixed; line per sample', () {
      final r = _record();
      r.samples.add(RssiSample(DateTime.utc(2026, 5, 13, 12, 0, 0), -55));
      r.samples.add(RssiSample(DateTime.utc(2026, 5, 13, 12, 0, 1), -56));
      final csv = r.toCsv();
      final lines = csv.trim().split('\n');
      expect(lines.first, 'timestamp_iso,rssi_dbm');
      expect(lines.length, 3);
      expect(lines[1], '2026-05-13T12:00:00.000Z,-55');
      expect(lines[2], '2026-05-13T12:00:01.000Z,-56');
    });
  });

  group('DeviceRecord smoothing', () {
    test('window 1 returns currentRssi', () {
      final r = _record();
      r.currentRssi = -55;
      r.samples.add(RssiSample(DateTime(2026), -90));
      expect(r.smoothedRssi(1), -55);
    });
    test('averages last N samples', () {
      final r = _record();
      r.samples.addAll([
        RssiSample(DateTime(2026), -60),
        RssiSample(DateTime(2026), -70),
        RssiSample(DateTime(2026), -80),
      ]);
      expect(r.smoothedRssi(3), -70);
    });
    test('uses available samples when N exceeds length', () {
      final r = _record();
      r.samples.add(RssiSample(DateTime(2026), -60));
      expect(r.smoothedRssi(10), -60);
    });
    test('empty samples fall back to currentRssi', () {
      final r = _record();
      r.currentRssi = -42;
      expect(r.smoothedRssi(5), -42);
    });
  });

  group('DeviceRecord trend', () {
    test('returns 0 with too few samples', () {
      final r = _record();
      r.samples.add(RssiSample(DateTime.now(), -70));
      expect(r.trend(), 0);
    });
    test('detects strengthening signal', () {
      final r = _record();
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        final rssi = -80 + i * 4;
        r.samples.add(
            RssiSample(now.subtract(Duration(milliseconds: 1000 - i * 100)), rssi));
      }
      expect(r.trend(), 1);
    });
    test('detects weakening signal', () {
      final r = _record();
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        final rssi = -60 - i * 4;
        r.samples.add(
            RssiSample(now.subtract(Duration(milliseconds: 1000 - i * 100)), rssi));
      }
      expect(r.trend(), -1);
    });
    test('returns 0 for stable signal', () {
      final r = _record();
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        r.samples.add(
            RssiSample(now.subtract(Duration(milliseconds: 1000 - i * 100)), -70));
      }
      expect(r.trend(), 0);
    });
  });

  group('DeviceRecord medianIntervalMs', () {
    test('returns null with fewer than 3 samples', () {
      final r = _record();
      final now = DateTime.now();
      r.samples.add(RssiSample(now.subtract(const Duration(seconds: 1)), -70));
      r.samples.add(RssiSample(now, -70));
      expect(r.medianIntervalMs(), isNull);
    });

    test('computes median of consecutive gaps', () {
      final r = _record();
      final now = DateTime.now();
      // Gaps: 100ms, 200ms, 100ms, 300ms → sorted [100, 100, 200, 300]
      // → median (index 2) = 200
      r.samples.addAll([
        RssiSample(now.subtract(const Duration(milliseconds: 700)), -70),
        RssiSample(now.subtract(const Duration(milliseconds: 600)), -70),
        RssiSample(now.subtract(const Duration(milliseconds: 400)), -70),
        RssiSample(now.subtract(const Duration(milliseconds: 300)), -70),
        RssiSample(now, -70),
      ]);
      expect(r.medianIntervalMs(), 200);
    });

    test('ignores samples outside the window', () {
      final r = _record();
      final now = DateTime.now();
      // Two old samples, then three recent ones at 100ms intervals.
      r.samples.addAll([
        RssiSample(now.subtract(const Duration(minutes: 10)), -70),
        RssiSample(now.subtract(const Duration(minutes: 9)), -70),
        RssiSample(now.subtract(const Duration(milliseconds: 200)), -70),
        RssiSample(now.subtract(const Duration(milliseconds: 100)), -70),
        RssiSample(now, -70),
      ]);
      expect(r.medianIntervalMs(), 100);
    });
  });

  group('DeviceRecord rssiStdDev', () {
    test('returns null with fewer than 4 samples in window', () {
      final r = _record();
      final now = DateTime.now();
      r.samples.addAll([
        RssiSample(now, -70),
        RssiSample(now, -70),
        RssiSample(now, -70),
      ]);
      expect(r.rssiStdDev(), isNull);
    });

    test('zero stddev when all samples equal', () {
      final r = _record();
      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        r.samples
            .add(RssiSample(now.subtract(Duration(seconds: i)), -70));
      }
      expect(r.rssiStdDev(), closeTo(0.0, 1e-9));
    });

    test('nonzero stddev when samples vary', () {
      final r = _record();
      final now = DateTime.now();
      // Mean = -70, deviations [-2, -1, 0, 1, 2]; population stddev
      // = sqrt((4+1+0+1+4)/5) = sqrt(2) ≈ 1.4142.
      final values = [-72, -71, -70, -69, -68];
      for (var i = 0; i < values.length; i++) {
        r.samples
            .add(RssiSample(now.subtract(Duration(seconds: i)), values[i]));
      }
      expect(r.rssiStdDev(), closeTo(1.4142, 0.001));
    });

    test('ignores samples outside the window', () {
      final r = _record();
      final now = DateTime.now();
      // Big outliers way in the past should not affect recent stddev.
      r.samples.addAll([
        RssiSample(now.subtract(const Duration(minutes: 10)), -20),
        RssiSample(now.subtract(const Duration(minutes: 9)), -100),
        RssiSample(now.subtract(const Duration(seconds: 3)), -70),
        RssiSample(now.subtract(const Duration(seconds: 2)), -70),
        RssiSample(now.subtract(const Duration(seconds: 1)), -70),
        RssiSample(now, -70),
      ]);
      expect(r.rssiStdDev(), closeTo(0.0, 1e-9));
    });
  });
}
