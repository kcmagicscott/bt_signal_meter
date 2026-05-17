import 'package:bt_signal_meter/utils/device_guess.dart';
import 'package:bt_signal_meter/utils/fast_pair.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fast Pair model ID lookup', () {
    test('known product (Pixel Buds Pro) resolves to certain name', () {
      // 0x40A88B big-endian.
      final guess = guessFromFastPair({
        fastPairServiceUuid: [0x40, 0xA8, 0x8B],
      });
      expect(guess, isNotNull);
      expect(guess!.label, 'Pixel Buds Pro');
      expect(guess.confidence, Confidence.certain);
      expect(guess.icon, isNotNull);
    });

    test('known product (Sony WH-1000XM5) resolves', () {
      final guess = guessFromFastPair({
        fastPairServiceUuid: [0xF2, 0xD9, 0xC6],
      });
      expect(guess?.label, 'Sony WH-1000XM5');
    });

    test('unknown model ID falls back to generic Fast Pair label', () {
      final guess = guessFromFastPair({
        fastPairServiceUuid: [0x12, 0x34, 0x56],
      });
      expect(guess, isNotNull);
      expect(guess!.label, contains('Fast Pair device'));
      expect(guess.label, contains('123456'));
      expect(guess.confidence, Confidence.possible);
    });

    test('payload longer than 3 bytes still parses (non-discoverable form)', () {
      // First 3 bytes are still the model ID; extra bytes are account data.
      final guess = guessFromFastPair({
        fastPairServiceUuid: [
          0x40, 0xA8, 0x8B,
          0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE,
        ],
      });
      expect(guess?.label, 'Pixel Buds Pro');
    });

    test('payload shorter than 3 bytes returns null', () {
      final guess = guessFromFastPair({
        fastPairServiceUuid: [0x40, 0xA8],
      });
      expect(guess, isNull);
    });

    test('service data without Fast Pair UUID returns null', () {
      final guess = guessFromFastPair({
        '0000180f-0000-1000-8000-00805f9b34fb': [0x40, 0xA8, 0x8B],
      });
      expect(guess, isNull);
    });

    test('empty service data returns null', () {
      expect(guessFromFastPair({}), isNull);
    });
  });
}
