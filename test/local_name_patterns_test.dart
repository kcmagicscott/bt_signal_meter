import 'package:bt_signal_meter/utils/device_guess.dart';
import 'package:bt_signal_meter/utils/local_name_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('local-name pattern matching', () {
    test('Sony WH-1000XM5 matches', () {
      final g = guessFromLocalName('WH-1000XM5');
      expect(g, isNotNull);
      expect(g!.label, contains('WH-1000XM'));
      expect(g.confidence, Confidence.certain);
    });

    test('Sony WF-1000XM4 matches', () {
      expect(guessFromLocalName('WF-1000XM4')?.label, contains('WF-1000XM'));
    });

    test('case-insensitive: lowercase Sony name still matches', () {
      expect(guessFromLocalName('wh-1000xm5'), isNotNull);
    });

    test('Bose QuietComfort matches', () {
      final g = guessFromLocalName('QuietComfort Ultra');
      expect(g, isNotNull);
      expect(g!.label, contains('Bose QuietComfort'));
    });

    test('Galaxy Buds matches', () {
      final g = guessFromLocalName('Galaxy Buds Pro');
      expect(g?.label, contains('Galaxy Buds'));
      expect(g?.confidence, Confidence.certain);
    });

    test('Galaxy phone model code matches', () {
      expect(guessFromLocalName('Galaxy S24 Ultra'), isNotNull);
    });

    test('Samsung SM- model code matches', () {
      expect(guessFromLocalName('SM-S948U')?.label, contains('Samsung'));
    });

    test('Pixel Buds matches', () {
      expect(guessFromLocalName('Pixel Buds Pro')?.label,
          contains('Pixel Buds'));
    });

    test('MX Master matches Logitech pattern', () {
      expect(guessFromLocalName('MX Master 3S')?.label, contains('Logitech'));
    });

    test('Tile_ prefix matches', () {
      expect(guessFromLocalName('Tile_ABCD')?.label, contains('Tile'));
    });

    test('Garmin Fenix matches', () {
      expect(guessFromLocalName('Fenix 7')?.label, contains('Fenix'));
    });

    test('falls back to generic Headphones pattern when no brand', () {
      final g = guessFromLocalName('Something Headphones');
      expect(g?.label, 'Headphones');
      expect(g?.confidence, Confidence.possible);
    });

    test('unknown random name returns null', () {
      expect(guessFromLocalName('XJ77-Random-9'), isNull);
    });

    test('null and empty names return null', () {
      expect(guessFromLocalName(null), isNull);
      expect(guessFromLocalName(''), isNull);
      expect(guessFromLocalName('   '), isNull);
    });

    test('icon is always set on a match', () {
      final names = ['WH-1000XM5', 'Galaxy Buds Pro', 'Pixel 8', 'Tile_AB'];
      for (final n in names) {
        final g = guessFromLocalName(n);
        expect(g, isNotNull, reason: 'no match for $n');
        expect(g!.icon, isNotNull, reason: 'no icon for $n');
      }
    });
  });
}
