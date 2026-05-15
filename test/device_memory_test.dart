import 'package:bt_signal_meter/services/device_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceNote serialization', () {
    test('round-trips a labelled favorite with calibration', () {
      final src = DeviceNote(
        label: 'My speakers',
        favorite: true,
        calibratedTxPower: -62,
      );
      final json = src.toJson();
      final back = DeviceNote.fromJson(json);
      expect(back.label, 'My speakers');
      expect(back.favorite, isTrue);
      expect(back.calibratedTxPower, -62);
    });

    test('round-trips an empty-label favorite', () {
      final src = DeviceNote(favorite: true);
      final back = DeviceNote.fromJson(src.toJson());
      expect(back.label, isNull);
      expect(back.favorite, isTrue);
      expect(back.calibratedTxPower, isNull);
    });

    test('isEmpty true when nothing meaningful is set', () {
      expect(DeviceNote().isEmpty, isTrue);
      expect(DeviceNote(label: '').isEmpty, isTrue);
    });

    test('isEmpty false when calibration is set', () {
      expect(DeviceNote(calibratedTxPower: -55).isEmpty, isFalse);
    });

    test('isEmpty false when favorite is on', () {
      expect(DeviceNote(favorite: true).isEmpty, isFalse);
    });
  });
}
