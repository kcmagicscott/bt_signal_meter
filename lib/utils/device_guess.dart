import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/device_record.dart';

class DeviceGuess {
  const DeviceGuess(this.label, {this.confidence = Confidence.likely});
  final String label;
  final Confidence confidence;
}

enum Confidence { certain, likely, possible }

/// Best-effort guess at what a Bluetooth device actually is based on the
/// signals available in its advertisement: manufacturer data subtype bytes,
/// advertised service UUIDs, and a few well-known patterns.
///
/// We err on the side of saying nothing rather than guessing wildly — many
/// BLE devices broadcast minimal info.
DeviceGuess? guessDeviceType(DeviceRecord r) {
  if (r.iBeacon != null) {
    return const DeviceGuess('iBeacon', confidence: Confidence.certain);
  }
  if (r.eddystone != null) {
    return const DeviceGuess('Eddystone beacon',
        confidence: Confidence.certain);
  }

  if (r.manufacturerId == 0x004C && r.rawManufacturerBytes.isNotEmpty) {
    final apple = _guessApple(r.rawManufacturerBytes);
    if (apple != null) return apple;
  }

  if (r.manufacturerId == 0x0006 &&
      r.rawManufacturerBytes.length >= 2 &&
      r.rawManufacturerBytes[0] == 0x01) {
    return const DeviceGuess('Microsoft device (Swift Pair)');
  }

  if (r.manufacturerId == 0x0245) {
    return const DeviceGuess('Tile tracker', confidence: Confidence.certain);
  }

  if (r.manufacturerId == 0x0075) {
    // Many Samsung Galaxy Buds, watches, etc. start with specific prefixes.
    return const DeviceGuess('Samsung device (Galaxy ecosystem)',
        confidence: Confidence.possible);
  }

  if (r.manufacturerId == 0x00E0 || r.manufacturerId == 0x008C) {
    return const DeviceGuess('Google device',
        confidence: Confidence.possible);
  }

  final services = _guessFromServices(r.serviceUuids);
  if (services != null) return services;

  // Fallback: a known manufacturer ID with no payload subtype we recognise.
  if (r.manufacturerId != null) {
    final name = _vendorName(r.manufacturerId!);
    if (name != null) {
      return DeviceGuess('$name device', confidence: Confidence.possible);
    }
  }

  return null;
}

DeviceGuess? _guessApple(List<int> data) {
  if (data.isEmpty) return null;
  final type = data[0];
  switch (type) {
    case 0x02:
      return const DeviceGuess('iBeacon', confidence: Confidence.certain);
    case 0x03:
      return const DeviceGuess('AirPrint');
    case 0x05:
      return const DeviceGuess('Apple device (AirDrop)');
    case 0x06:
      return const DeviceGuess('HomeKit accessory');
    case 0x07:
      return const DeviceGuess('AirPods / Beats (pair mode)',
          confidence: Confidence.likely);
    case 0x08:
      return const DeviceGuess('Apple device ("Hey Siri")');
    case 0x09:
      return const DeviceGuess('Apple TV or HomePod (AirPlay)');
    case 0x0A:
      return const DeviceGuess('Apple device (AirPlay source)');
    case 0x0B:
      return const DeviceGuess('Apple Magic Switch');
    case 0x0C:
      return const DeviceGuess('Apple device (Handoff)');
    case 0x0D:
      return const DeviceGuess('Personal Hotspot (Tethering target)');
    case 0x0E:
      return const DeviceGuess('Personal Hotspot (Tethering source)');
    case 0x0F:
      return const DeviceGuess('Apple device (Nearby Action)');
    case 0x10:
      return const DeviceGuess('Apple iPhone / iPad (Nearby Info)',
          confidence: Confidence.likely);
    case 0x12:
      return const DeviceGuess('AirTag or Find My device',
          confidence: Confidence.likely);
    case 0x16:
      return const DeviceGuess('AirPods (status update)');
    default:
      return DeviceGuess(
        'Apple device (Continuity 0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()})',
        confidence: Confidence.possible,
      );
  }
}

DeviceGuess? _guessFromServices(List<Guid> uuids) {
  final s = uuids.map((u) => u.str.toLowerCase()).toSet();
  if (s.contains('0000180d-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Heart rate monitor');
  }
  if (s.contains('00001812-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Keyboard, mouse, or gamepad (HID)');
  }
  if (s.contains('0000fdf0-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Tile tracker',
        confidence: Confidence.certain);
  }
  if (s.contains('0000fe2c-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Google Fast Pair device');
  }
  if (s.contains('0000fef3-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Google Fast Pair device');
  }
  if (s.contains('0000fe9f-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Google device');
  }
  if (s.contains('0000fd6f-0000-1000-8000-00805f9b34fb')) {
    return const DeviceGuess('Exposure Notification (contact tracing)');
  }
  if (s.contains('0000180f-0000-1000-8000-00805f9b34fb') &&
      uuids.length == 1) {
    return const DeviceGuess('Battery-reporting peripheral');
  }
  return null;
}

String? _vendorName(int id) {
  switch (id) {
    case 0x004C:
      return 'Apple';
    case 0x0006:
      return 'Microsoft';
    case 0x0075:
      return 'Samsung';
    case 0x00E0:
    case 0x008C:
      return 'Google';
    case 0x0245:
      return 'Tile';
    case 0x0157:
      return 'Xiaomi/Amazfit';
    case 0x0399:
      return 'Nintendo';
    case 0x05A7:
      return 'Sonos';
    case 0x0220:
      return 'Logitech';
    case 0x0087:
      return 'Garmin';
    case 0x0181:
      return 'Polar';
    default:
      return null;
  }
}
