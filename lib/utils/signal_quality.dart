import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Discrete signal-quality band — used for the gauge label, list-tile colour,
/// signal-bars count, and similar UI affordances.
class SignalQuality {
  const SignalQuality(this.label, this.color, this.bars);
  final String label;
  final Color color;
  final int bars; // 0-4
}

SignalQuality qualityFromRssi(int rssi) {
  if (rssi >= -55) return const SignalQuality('Excellent', Color(0xFF2E7D32), 4);
  if (rssi >= -70) return const SignalQuality('Good', Color(0xFF66BB6A), 3);
  if (rssi >= -85) return const SignalQuality('Fair', Color(0xFFFFA726), 2);
  if (rssi >= -100) return const SignalQuality('Poor', Color(0xFFEF5350), 1);
  return const SignalQuality('Very Poor', Color(0xFFB71C1C), 0);
}

/// Continuous red → orange → green mapping over the usable RSSI range.
/// Used by the sparkline so the line can fade between qualities smoothly
/// instead of snapping between the discrete bands in [qualityFromRssi].
Color colorForRssi(int rssi) {
  const red = Color(0xFFB71C1C);
  const orange = Color(0xFFFFA726);
  const green = Color(0xFF2E7D32);
  final t = ((rssi + 100) / 50).clamp(0.0, 1.0);
  if (t < 0.5) return Color.lerp(red, orange, t * 2)!;
  return Color.lerp(orange, green, (t - 0.5) * 2)!;
}

/// Crude free-space distance estimate from RSSI.
/// `measuredPower` is the RSSI observed at 1m (often broadcast as TX power).
/// `n` is the path-loss exponent — 2 for line-of-sight, 3-4 indoors.
double? estimateDistanceMeters({
  required int rssi,
  int measuredPowerAt1m = -59,
  double n = 2.0,
}) {
  if (rssi == 0) return null;
  final ratio = (measuredPowerAt1m - rssi) / (10 * n);
  return math.pow(10, ratio).toDouble();
}
