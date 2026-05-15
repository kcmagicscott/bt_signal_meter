import 'package:bt_signal_meter/utils/beacon_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iBeacon parser', () {
    test('parses standard frame', () {
      // Apple company ID 0x004C handled by caller; payload is:
      // 0x02 0x15 + 16 UUID bytes + 2 major + 2 minor + 1 power
      final payload = [
        0x02, 0x15,
        // UUID f0018b9b-7509-4c31-a905-1a27d39f88a8
        0xf0, 0x01, 0x8b, 0x9b, 0x75, 0x09, 0x4c, 0x31,
        0xa9, 0x05, 0x1a, 0x27, 0xd3, 0x9f, 0x88, 0xa8,
        0x00, 0x05, // major = 5
        0x01, 0x00, // minor = 256
        0xc5, // measured power = -59 (0xc5 = 197 -> -59)
      ];
      final b = parseIBeacon(companyId: 0x004C, bytes: payload);
      expect(b, isNotNull);
      expect(b!.uuid, 'f0018b9b-7509-4c31-a905-1a27d39f88a8');
      expect(b.major, 5);
      expect(b.minor, 256);
      expect(b.measuredPower, -59);
    });
    test('returns null for non-Apple manufacturer', () {
      final payload = List.filled(25, 0x00);
      payload[0] = 0x02;
      payload[1] = 0x15;
      expect(parseIBeacon(companyId: 0x0006, bytes: payload), isNull);
    });
    test('returns null when prefix bytes do not match', () {
      final payload = List.filled(25, 0x00);
      expect(parseIBeacon(companyId: 0x004C, bytes: payload), isNull);
    });
  });

  group('Eddystone parser', () {
    test('parses UID frame', () {
      final data = <int>[
        0x00, // type
        0xC5, // tx power
        // namespace (10 bytes)
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a,
        // instance (6 bytes)
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15,
      ];
      final e = parseEddystone(data);
      expect(e, isNotNull);
      expect(e!.frameType, EddystoneFrameType.uid);
      expect(e.payload.contains('0102030405060708090a'), isTrue);
      expect(e.payload.contains('101112131415'), isTrue);
    });

    test('parses URL frame for https://example.com', () {
      // 0x10 + tx power + scheme=0x03(https) + 'example' + 0x07('.com')
      final data = <int>[
        0x10,
        0xC5,
        0x03,
        ...'example'.codeUnits,
        0x07,
      ];
      final e = parseEddystone(data);
      expect(e, isNotNull);
      expect(e!.frameType, EddystoneFrameType.url);
      expect(e.payload, 'https://example.com');
    });

    test('parses TLM frame battery + temperature', () {
      final data = <int>[
        0x20, // type
        0x00, // version
        0x0C, 0x80, // battery 3200mV
        0x18, 0x00, // temp 24.0 C
        0x00, 0x00, 0x00, 0x05, // adv count
        0x00, 0x00, 0x00, 0x0A, // uptime
      ];
      final e = parseEddystone(data);
      expect(e, isNotNull);
      expect(e!.frameType, EddystoneFrameType.tlm);
      expect(e.payload.contains('3200mV'), isTrue);
      expect(e.payload.contains('24.0'), isTrue);
    });
  });
}
