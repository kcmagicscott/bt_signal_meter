/// GATT service / characteristic lookup tables, plus a value decoder for the
/// handful of standard characteristics we render directly.
///
/// Other Bluetooth helpers live in dedicated modules:
///   - [signal_quality.dart] — quality bands, RSSI colour ramps, distance
///   - [formatters.dart]     — distance / duration / time strings
///   - [manufacturer_ids.dart] — SIG company-identifier table
///
/// All three are re-exported here so existing `import bt_helpers.dart`
/// callers keep working unchanged.
library;

export 'formatters.dart';
export 'manufacturer_ids.dart' show kManufacturerNames, manufacturerNameFor;
export 'signal_quality.dart';

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
        return String.fromCharCodes(bytes)
            .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
            .trim();
      } catch (_) {
        return null;
      }
    default:
      return null;
  }
}
