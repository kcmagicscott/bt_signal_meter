import 'package:bt_signal_meter/utils/direction_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('medianOfInts', () {
    test('null on empty', () {
      expect(medianOfInts(const []), isNull);
    });
    test('single value', () {
      expect(medianOfInts([7]), 7.0);
    });
    test('odd length picks middle', () {
      expect(medianOfInts([5, 1, 3]), 3.0);
    });
    test('even length averages two middles', () {
      expect(medianOfInts([1, 2, 3, 4]), 2.5);
    });
    test('robust to extreme outliers', () {
      // -70 dBm baseline with one freak high-RSSI spike.
      expect(medianOfInts([-70, -71, -69, -45]), closeTo(-69.5, 1e-9));
    });
  });

  group('smoothCircular', () {
    test('constant signal smooths to itself', () {
      final raw = List<double?>.filled(8, 1.0);
      final s = smoothCircular(raw);
      for (final v in s) {
        expect(v, closeTo(1.0, 1e-9));
      }
    });
    test('isolated peak is softened, neighbours lifted', () {
      final raw = List<double?>.filled(8, 0.0);
      raw[3] = 10.0;
      final s = smoothCircular(raw);
      // Centre weight from defaultSmoothingKernel is 0.30 → 10 * 0.3 = 3.0.
      expect(s[3], closeTo(3.0, 1e-9));
      // Each immediate neighbour gets 0.25 * 10 = 2.5.
      expect(s[2], closeTo(2.5, 1e-9));
      expect(s[4], closeTo(2.5, 1e-9));
      // Two-away neighbours get 0.10 * 10 = 1.0.
      expect(s[1], closeTo(1.0, 1e-9));
      expect(s[5], closeTo(1.0, 1e-9));
    });
    test('wraps circularly', () {
      final raw = List<double?>.filled(8, 0.0);
      raw[0] = 10.0;
      final s = smoothCircular(raw);
      // Bucket 0's left neighbour is bucket 7 (wrap).
      expect(s[7], closeTo(2.5, 1e-9));
      expect(s[6], closeTo(1.0, 1e-9));
    });
    test('null buckets are skipped without breaking', () {
      final raw = <double?>[null, null, 4.0, 4.0, 4.0, null, null, null];
      final s = smoothCircular(raw);
      // Bucket 3 sees 3 non-null neighbours (2, 3, 4) all equal to 4 →
      // weighted mean is 4.
      expect(s[3], closeTo(4.0, 1e-9));
    });
  });

  group('parabolicOffset', () {
    test('symmetric peak → no shift', () {
      final s = <double?>[1.0, 5.0, 1.0];
      expect(parabolicOffset(1, s), closeTo(0.0, 1e-9));
    });
    test('left-leaning peak → negative offset', () {
      // Higher left neighbour means the true peak sits left of bucket 1.
      final s = <double?>[4.0, 5.0, 1.0];
      final off = parabolicOffset(1, s);
      expect(off, lessThan(0));
      expect(off, greaterThanOrEqualTo(-0.5));
    });
    test('right-leaning peak → positive offset', () {
      final s = <double?>[1.0, 5.0, 4.0];
      final off = parabolicOffset(1, s);
      expect(off, greaterThan(0));
      expect(off, lessThanOrEqualTo(0.5));
    });
    test('clamps to [-0.5, 0.5] for pathological inputs', () {
      // Flat-ish parabola — would give a huge offset without clamp.
      final s = <double?>[4.99, 5.0, 4.98];
      final off = parabolicOffset(1, s);
      expect(off, lessThanOrEqualTo(0.5));
      expect(off, greaterThanOrEqualTo(-0.5));
    });
    test('zero when neighbour is missing', () {
      final s = <double?>[null, 5.0, 4.0];
      expect(parabolicOffset(1, s), 0.0);
    });
  });

  group('circularBucketDistance', () {
    test('adjacent buckets → 1', () {
      expect(circularBucketDistance(3, 4, 16), 1);
    });
    test('wraps shortest way', () {
      // From bucket 1 to bucket 15 in a 16-ring: shortest is 2 (via 0).
      expect(circularBucketDistance(1, 15, 16), 2);
    });
    test('opposite bucket → bucketCount / 2', () {
      expect(circularBucketDistance(0, 8, 16), 8);
    });
    test('zero when equal', () {
      expect(circularBucketDistance(5, 5, 16), 0);
    });
  });
}
