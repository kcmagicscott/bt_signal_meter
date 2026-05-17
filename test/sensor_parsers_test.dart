import 'package:bt_signal_meter/models/device_record.dart';
import 'package:bt_signal_meter/utils/sensor_parsers.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceRecord _record({
  int? mfrId,
  List<int> mfrBytes = const [],
  Map<String, List<int>> svcData = const {},
}) {
  final r = DeviceRecord(
    id: DeviceIdentifier('AA:BB:CC:DD:EE:FF'),
    name: 'test',
    firstSeen: DateTime.now(),
  );
  r.manufacturerId = mfrId;
  r.rawManufacturerBytes = mfrBytes;
  r.serviceData = svcData;
  return r;
}

void main() {
  group('Ruuvi RAW v5', () {
    test('decodes a known good frame', () {
      // Crafted: temp=20.0°C (0x0FA0=4000 raw*0.005), humid=50.0% (0x4E20*0.0025),
      // pressure=1013.25 hPa ((101325-50000)/1 = 51325 → 0xC87D), batt+tx packed.
      const bytes = [
        0x05, // data format
        0x0F, 0xA0, // temp 4000 * 0.005 = 20.0
        0x4E, 0x20, // humid 20000 * 0.0025 = 50.0
        0xC8, 0x7D, // pressure 51325 + 50000 = 101325 Pa = 1013.25 hPa
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // accel xyz
        0x4B, 0x57, // batt+tx (0x4B5 = 1205mv offset, 0x17 = 23 tx bits)
        0x00, // movement
        0x00, 0x01, // seq
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // mac
      ];
      final r = _record(mfrId: 0x0499, mfrBytes: bytes);
      final reading = parseSensorData(r);
      expect(reading, isNotNull);
      expect(reading!.source, 'Ruuvi v5');
      expect(reading.temperatureC, closeTo(20.0, 0.01));
      expect(reading.humidityPercent, closeTo(50.0, 0.01));
      expect(reading.pressureHpa, closeTo(1013.25, 0.1));
    });

    test('rejects non-Ruuvi manufacturer ID', () {
      final r = _record(mfrId: 0x004C, mfrBytes: [0x05, 0x0F, 0xA0]);
      expect(parseSensorData(r), isNull);
    });

    test('rejects wrong data format byte', () {
      final r = _record(mfrId: 0x0499, mfrBytes: [0x03, 0x0F, 0xA0]);
      expect(parseSensorData(r), isNull);
    });

    test('rejects truncated frame', () {
      final r = _record(mfrId: 0x0499, mfrBytes: [0x05, 0x0F]);
      expect(parseSensorData(r), isNull);
    });
  });

  group('Govee H50xx', () {
    test('decodes positive temperature + humidity + battery', () {
      // combo = 23.4°C × 1000 + 47.5%×10 = 23475 (0x5BB3)
      // packed into bytes 1..3 big-endian: 0x00, 0x5B, 0xB3
      // Wait, magnitude must fit in 23 bits. Our impl uses tempIntPart = magnitude ~/ 1000.
      // So if magnitude = 234475 then tempIntPart = 234, humidIntPart = 475.
      // temp = 234 / 10.0 = 23.4°C, humid = 475 / 10.0 = 47.5%.
      // 234475 in hex is 0x0393EB → bytes 0x03, 0x93, 0xEB.
      const bytes = [
        0x00, // padding
        0x03, 0x93, 0xEB, // packed combo
        0x4A, // battery 74%
        0x00,
      ];
      final r = _record(mfrId: 0xEC88, mfrBytes: bytes);
      final reading = parseSensorData(r);
      expect(reading, isNotNull);
      expect(reading!.source, 'Govee H50xx');
      expect(reading.temperatureC, closeTo(23.4, 0.05));
      expect(reading.humidityPercent, closeTo(47.5, 0.05));
      expect(reading.batteryPercent, 74);
    });

    test('rejects truncated frame', () {
      final r = _record(mfrId: 0xEC88, mfrBytes: [0x00, 0x01]);
      expect(parseSensorData(r), isNull);
    });
  });

  group('Xiaomi ATC', () {
    test('decodes BE (vanilla ATC) format', () {
      // ATC vanilla: 6 bytes MAC, 2 bytes temp*10 (BE int16), 2 bytes humid*100 (BE),
      // 1 byte battery%, 2 bytes batt mV, 1 byte counter.
      const bytes = [
        0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, // mac (6)
        0x00, 0xDC, // temp 220 / 10 = 22.0°C
        0x10, 0x68, // humidity 4200 / 100 = 42.0%
        0x55, // battery 85%
        0x0B, 0xB8, // batt mV
        0x07, // counter
      ];
      final r = _record(
          svcData: {'0000181a-0000-1000-8000-00805f9b34fb': bytes});
      final reading = parseSensorData(r);
      expect(reading, isNotNull);
      expect(reading!.source, contains('Xiaomi ATC'));
      expect(reading.temperatureC, closeTo(22.0, 0.05));
      expect(reading.humidityPercent, closeTo(42.0, 0.05));
      expect(reading.batteryPercent, 85);
    });

    test('rejects truncated service data', () {
      final r = _record(
          svcData: {'0000181a-0000-1000-8000-00805f9b34fb': [0x00, 0x01]});
      expect(parseSensorData(r), isNull);
    });
  });

  group('SensorReading formatting', () {
    test('°F conversion from °C', () {
      final r = SensorReading(temperatureC: 25.0);
      expect(r.temperatureF(), '77.0°F');
    });

    test('null temperature shows em-dash', () {
      expect(const SensorReading().temperatureF(), '—');
      expect(const SensorReading().temperatureCStr(), '—');
      expect(const SensorReading().humidityStr(), '—');
    });

    test('isEmpty when all fields null', () {
      expect(const SensorReading().isEmpty, isTrue);
      expect(SensorReading(temperatureC: 1.0).isEmpty, isFalse);
    });
  });
}
