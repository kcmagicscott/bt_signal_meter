// Pure-function math used by the DirectionFinder service. Extracted out
// so the algorithms (smoothing, peak interpolation, circular distance)
// can be unit-tested without bringing up the live sensor service.

/// Five-tap Gaussian-ish kernel used for circular bucket smoothing.
/// Hand-tuned for 16 buckets of 22.5° each; the centre weight dominates
/// while neighbours soften single-bucket multipath spikes.
const List<double> defaultSmoothingKernel = [0.10, 0.25, 0.30, 0.25, 0.10];

/// Median of [values]. Returns null when the list is empty.
double? medianOfInts(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = List<int>.from(values)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2].toDouble();
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Apply a circular kernel to a vector of per-bucket values. [raw] may
/// contain nulls (buckets without data); the returned vector has the
/// same length and contains nulls where the kernel's effective weight
/// over non-null neighbours is zero.
List<double?> smoothCircular(
  List<double?> raw, {
  List<double> kernel = defaultSmoothingKernel,
}) {
  final n = raw.length;
  final half = kernel.length ~/ 2;
  final smoothed = List<double?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    var weight = 0.0;
    for (var k = 0; k < kernel.length; k++) {
      final j = (i + k - half + n) % n;
      final v = raw[j];
      if (v != null) {
        sum += v * kernel[k];
        weight += kernel[k];
      }
    }
    if (weight > 0) smoothed[i] = sum / weight;
  }
  return smoothed;
}

/// Parabolic interpolation through (peak-1, peak, peak+1) returns a
/// sub-bucket offset in [-0.5, 0.5]. Returns 0 when either neighbour is
/// missing or the parabola is too flat to fit (avoids divide-by-zero).
double parabolicOffset(int peakBucket, List<double?> smoothed) {
  final n = smoothed.length;
  final left = smoothed[(peakBucket - 1 + n) % n];
  final center = smoothed[peakBucket];
  final right = smoothed[(peakBucket + 1) % n];
  if (left == null || center == null || right == null) return 0;
  final denom = left - 2 * center + right;
  if (denom.abs() < 1e-6) return 0;
  final offset = 0.5 * (left - right) / denom;
  return offset.clamp(-0.5, 0.5);
}

/// Circular (shortest-arc) distance between two bucket indices in a ring
/// of [bucketCount] equally-sized buckets.
int circularBucketDistance(int a, int b, int bucketCount) {
  final d = (a - b).abs();
  return d > bucketCount ~/ 2 ? bucketCount - d : d;
}
