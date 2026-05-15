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
}
