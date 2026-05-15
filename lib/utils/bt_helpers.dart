import 'dart:math' as math;

import 'package:flutter/material.dart';

export 'manufacturer_ids.dart' show kManufacturerNames, manufacturerNameFor;

/// Common BLE assigned service UUIDs (16-bit) expanded to 128-bit form.
const Map<String, String> kWellKnownServices = {
  '00001800-0000-1000-8000-00805f9b34fb': 'Generic Access',
  '00001801-0000-1000-8000-00805f9b34fb': 'Generic Attribute',
  '0000180a-0000-1000-8000-00805f9b34fb': 'Device Information',
  '0000180d-0000-1000-8000-00805f9b34fb': 'Heart Rate',
  '0000180f-0000-1000-8000-00805f9b34fb': 'Battery',
  '00001812-0000-1000-8000-00805f9b34fb': 'HID',
  '0000fd6f-0000-1000-8000-00805f9b34fb': 'Exposure Notification',
  '0000fe9f-0000-1000-8000-00805f9b34fb': 'Google',
  '0000feaa-0000-1000-8000-00805f9b34fb': 'Eddystone',
  '0000fef3-0000-1000-8000-00805f9b34fb': 'Google Fast Pair',
};

String? serviceNameFor(String uuid) => kWellKnownServices[uuid.toLowerCase()];

/// Common assigned-number GATT characteristics (full UUID form).
const Map<String, String> kWellKnownCharacteristics = {
  '00002a00-0000-1000-8000-00805f9b34fb': 'Device Name',
  '00002a01-0000-1000-8000-00805f9b34fb': 'Appearance',
  '00002a19-0000-1000-8000-00805f9b34fb': 'Battery Level',
  '00002a24-0000-1000-8000-00805f9b34fb': 'Model Number',
  '00002a25-0000-1000-8000-00805f9b34fb': 'Serial Number',
  '00002a26-0000-1000-8000-00805f9b34fb': 'Firmware Revision',
  '00002a27-0000-1000-8000-00805f9b34fb': 'Hardware Revision',
  '00002a28-0000-1000-8000-00805f9b34fb': 'Software Revision',
  '00002a29-0000-1000-8000-00805f9b34fb': 'Manufacturer Name',
  '00002a2b-0000-1000-8000-00805f9b34fb': 'Current Time',
  '00002a37-0000-1000-8000-00805f9b34fb': 'Heart Rate Measurement',
  '00002a38-0000-1000-8000-00805f9b34fb': 'Body Sensor Location',
  '00002a23-0000-1000-8000-00805f9b34fb': 'System ID',
  '00002a50-0000-1000-8000-00805f9b34fb': 'PnP ID',
};

String? characteristicNameFor(String uuid) =>
    kWellKnownCharacteristics[uuid.toLowerCase()];

/// Decode a value blob for known characteristics into a human-readable string.
/// Returns null if we don't know how to decode this UUID, leaving callers to
/// fall back to hex/ASCII dumps.
String? decodeCharacteristicValue(String uuid, List<int> bytes) {
  if (bytes.isEmpty) return '(empty)';
  switch (uuid.toLowerCase()) {
    case '00002a19-0000-1000-8000-00805f9b34fb':
      return '${bytes[0]}%';
    case '00002a37-0000-1000-8000-00805f9b34fb':
      if (bytes.length >= 2) {
        final hr = (bytes[0] & 0x01) == 0
            ? bytes[1]
            : (bytes.length >= 3 ? (bytes[1] | (bytes[2] << 8)) : bytes[1]);
        return '$hr bpm';
      }
      return null;
    case '00002a00-0000-1000-8000-00805f9b34fb':
    case '00002a24-0000-1000-8000-00805f9b34fb':
    case '00002a25-0000-1000-8000-00805f9b34fb':
    case '00002a26-0000-1000-8000-00805f9b34fb':
    case '00002a27-0000-1000-8000-00805f9b34fb':
    case '00002a28-0000-1000-8000-00805f9b34fb':
    case '00002a29-0000-1000-8000-00805f9b34fb':
      try {
        return String.fromCharCodes(bytes).replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
      } catch (_) {
        return null;
      }
    default:
      return null;
  }
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

class SignalQuality {
  final String label;
  final Color color;
  final int bars; // 0-4

  const SignalQuality(this.label, this.color, this.bars);
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

/// Formats a distance estimate in either metric (m/cm) or imperial (ft/in).
///
/// Without [imperial], defaults to metric to stay compatible with existing
/// callers that don't yet thread AppSettings through.
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
