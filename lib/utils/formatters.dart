/// Formats a distance estimate in either metric (m/cm) or imperial (ft/in).
String formatDistance(double? meters, {bool imperial = false}) {
  if (meters == null) return '—';
  if (imperial) {
    final feet = meters * 3.28084;
    if (feet < 1) return '${(feet * 12).round()} in';
    if (feet < 10) return '${feet.toStringAsFixed(1)} ft';
    return '${feet.round()} ft';
  }
  if (meters < 1) return '${(meters * 100).round()} cm';
  if (meters < 10) return '${meters.toStringAsFixed(1)} m';
  return '${meters.round()} m';
}

String formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

String formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
