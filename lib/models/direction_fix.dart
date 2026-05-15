/// Result of a "rotate to find" sweep — the inferred bearing toward a
/// device, plus how much to trust it.
class DirectionFix {
  const DirectionFix({
    required this.time,
    required this.bearingDeg,
    required this.confidence,
    required this.peakRssi,
    required this.rangeDb,
    required this.sampleCount,
  });

  /// When the sweep finished.
  final DateTime time;

  /// Inferred compass bearing toward the device, 0..360°, 0 = magnetic north.
  final double bearingDeg;

  /// 0..1; how strongly the peak heading stood out over the rotation.
  final double confidence;

  /// Average RSSI seen at the peak heading bucket.
  final int peakRssi;

  /// Peak − trough across the rotation. Higher = clearer direction signal.
  final int rangeDb;

  /// Number of (heading, RSSI) samples that fed the buckets.
  final int sampleCount;

  Duration ageFrom(DateTime now) => now.difference(time);

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'b': bearingDeg,
        'c': confidence,
        'p': peakRssi,
        'r': rangeDb,
        'n': sampleCount,
      };

  factory DirectionFix.fromJson(Map<String, dynamic> j) => DirectionFix(
        time: DateTime.parse(j['t'] as String),
        bearingDeg: (j['b'] as num).toDouble(),
        confidence: (j['c'] as num).toDouble(),
        peakRssi: j['p'] as int,
        rangeDb: j['r'] as int,
        sampleCount: j['n'] as int,
      );
}
