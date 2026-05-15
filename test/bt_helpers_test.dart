import 'package:bt_signal_meter/utils/bt_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manufacturer lookup', () {
    test('Apple resolves', () {
      expect(manufacturerNameFor(0x004C), 'Apple');
    });
    test('Google resolves', () {
      expect(manufacturerNameFor(0x00E0), 'Google');
    });
    test('Unknown ID returns null', () {
      expect(manufacturerNameFor(0xFFFF), isNull);
    });
  });

  group('service lookup', () {
    test('Battery service resolves', () {
      expect(
        serviceNameFor('0000180f-0000-1000-8000-00805f9b34fb'),
        'Battery',
      );
    });
    test('Uppercase still resolves (lowercased internally)', () {
      expect(
        serviceNameFor('0000180F-0000-1000-8000-00805F9B34FB'),
        'Battery',
      );
    });
    test('Unknown UUID returns null', () {
      expect(serviceNameFor('00000000-0000-0000-0000-000000000000'), isNull);
    });
  });

  group('distance estimate', () {
    test('rssi equal to measuredPower means 1m', () {
      final d = estimateDistanceMeters(rssi: -59);
      expect(d, closeTo(1.0, 0.001));
    });
    test('weaker signal means farther', () {
      final near = estimateDistanceMeters(rssi: -50)!;
      final far = estimateDistanceMeters(rssi: -90)!;
      expect(far, greaterThan(near));
    });
    test('returns null for zero rssi', () {
      expect(estimateDistanceMeters(rssi: 0), isNull);
    });
  });

  group('signal quality buckets', () {
    test('excellent at -40', () {
      expect(qualityFromRssi(-40).label, 'Excellent');
      expect(qualityFromRssi(-40).bars, 4);
    });
    test('good at -65', () {
      expect(qualityFromRssi(-65).label, 'Good');
      expect(qualityFromRssi(-65).bars, 3);
    });
    test('fair at -80', () {
      expect(qualityFromRssi(-80).label, 'Fair');
      expect(qualityFromRssi(-80).bars, 2);
    });
    test('poor at -95', () {
      expect(qualityFromRssi(-95).label, 'Poor');
      expect(qualityFromRssi(-95).bars, 1);
    });
    test('very poor below -100', () {
      expect(qualityFromRssi(-110).label, 'Very Poor');
      expect(qualityFromRssi(-110).bars, 0);
    });
  });

  group('formatting', () {
    test('distance under 1m shows cm', () {
      expect(formatDistance(0.4), '40 cm');
    });
    test('distance 1-10m shows one decimal', () {
      expect(formatDistance(2.3), '2.3 m');
    });
    test('distance over 10m shows rounded meters', () {
      expect(formatDistance(15.7), '16 m');
    });
    test('null distance shows em dash', () {
      expect(formatDistance(null), '—');
    });

    test('duration under 60s shows seconds', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
    });
    test('duration 1-60m shows minutes+seconds', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 12)), '3m 12s');
    });
    test('duration over 1h shows hours+minutes', () {
      expect(formatDuration(const Duration(hours: 2, minutes: 5)), '2h 5m');
    });
  });
}
