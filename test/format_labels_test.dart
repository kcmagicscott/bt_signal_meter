import 'package:bt_signal_meter/utils/format_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intervalLabel', () {
    test('null → em-dash', () {
      expect(intervalLabel(null), '—');
    });
    test('sub-second → ms', () {
      expect(intervalLabel(125), '~125 ms');
      expect(intervalLabel(0), '~0 ms');
      expect(intervalLabel(999), '~999 ms');
    });
    test('1–10 s → one decimal', () {
      expect(intervalLabel(1000), '~1.0 s');
      expect(intervalLabel(1500), '~1.5 s');
      expect(intervalLabel(9499), '~9.5 s');
    });
    test('>= 10 s → integer seconds', () {
      expect(intervalLabel(10000), '~10 s');
      expect(intervalLabel(12400), '~12 s');
      expect(intervalLabel(60000), '~60 s');
    });
  });

  group('stabilityLabel', () {
    test('null → em-dash', () {
      expect(stabilityLabel(null), '—');
    });
    test('< 1.5 → Stable', () {
      expect(stabilityLabel(0.0), startsWith('Stable'));
      expect(stabilityLabel(1.4), startsWith('Stable'));
    });
    test('1.5 to 3.5 → Moderate', () {
      expect(stabilityLabel(1.5), startsWith('Moderate'));
      expect(stabilityLabel(2.7), startsWith('Moderate'));
      expect(stabilityLabel(3.4), startsWith('Moderate'));
    });
    test('>= 3.5 → Jumpy', () {
      expect(stabilityLabel(3.5), startsWith('Jumpy'));
      expect(stabilityLabel(8.0), startsWith('Jumpy'));
    });
    test('includes formatted sigma', () {
      expect(stabilityLabel(0.83), 'Stable · ±0.8 dB');
      expect(stabilityLabel(2.71828), 'Moderate · ±2.7 dB');
    });
  });
}
