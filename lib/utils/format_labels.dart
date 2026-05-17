// One-line label formatters used by the device detail page.
// Kept as pure functions so they can be unit-tested without bringing up
// the widget tree.

/// Human-readable summary of a median advertisement interval in
/// milliseconds. Returns an em-dash placeholder when null.
///
///   125 ms  → "~125 ms"
///   1500 ms → "~1.5 s"
///   12_400  → "~12 s"
String intervalLabel(int? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '~$ms ms';
  final s = ms / 1000;
  return s < 10 ? '~${s.toStringAsFixed(1)} s' : '~${s.round()} s';
}

/// Stability descriptor for an RSSI standard-deviation value. Thresholds:
///   < 1.5 dB → "Stable"
///   < 3.5 dB → "Moderate"
///   otherwise → "Jumpy"
String stabilityLabel(double? sigma) {
  if (sigma == null) return '—';
  final label = sigma < 1.5
      ? 'Stable'
      : sigma < 3.5
          ? 'Moderate'
          : 'Jumpy';
  return '$label · ±${sigma.toStringAsFixed(1)} dB';
}
