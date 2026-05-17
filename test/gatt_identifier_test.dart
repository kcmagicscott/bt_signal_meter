import 'package:bt_signal_meter/services/gatt_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattIdentity serialization', () {
    test('round-trips a populated identity', () {
      final t = DateTime.utc(2026, 5, 16, 12, 34, 56);
      final orig = GattIdentity(
        manufacturer: 'ACME Wireless',
        modelNumber: 'X-300',
        firmwareRevision: '1.2.3',
        hardwareRevision: 'A2',
        queriedAt: t,
      );
      final copy = GattIdentity.fromJson(orig.toJson());
      expect(copy.manufacturer, 'ACME Wireless');
      expect(copy.modelNumber, 'X-300');
      expect(copy.firmwareRevision, '1.2.3');
      expect(copy.hardwareRevision, 'A2');
      expect(copy.queriedAt, t);
    });

    test('round-trips a partial identity', () {
      final copy = GattIdentity.fromJson(
        GattIdentity(modelNumber: 'AirThing 2').toJson(),
      );
      expect(copy.manufacturer, isNull);
      expect(copy.modelNumber, 'AirThing 2');
    });

    test('isEmpty true when all fields null', () {
      expect(const GattIdentity().isEmpty, isTrue);
      expect(GattIdentity(manufacturer: 'A').isEmpty, isFalse);
    });

    test('headline concatenates mfr + model with separator', () {
      expect(
        GattIdentity(manufacturer: 'Sony', modelNumber: 'WH-1000XM5').headline,
        'Sony · WH-1000XM5',
      );
    });

    test('headline uses just one part when the other is null', () {
      expect(GattIdentity(manufacturer: 'Sony').headline, 'Sony');
      expect(GattIdentity(modelNumber: 'X1').headline, 'X1');
    });

    test('headline reports placeholder when both are null', () {
      expect(const GattIdentity().headline, '(no DIS data)');
    });
  });
}
