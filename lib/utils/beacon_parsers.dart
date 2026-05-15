// Parsers for common BLE beacon formats.
//
// iBeacon: Apple manufacturer data (company 0x004C) starting with bytes
//   0x02, 0x15, then 16-byte proximity UUID, 2-byte major, 2-byte minor,
//   1-byte measured power.
//
// Eddystone: service data UUID 0xFEAA with frame type in byte 0:
//   0x00 = UID, 0x10 = URL, 0x20 = TLM.

class IBeacon {
  const IBeacon({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.measuredPower,
  });

  final String uuid;
  final int major;
  final int minor;
  final int measuredPower;

  @override
  String toString() => 'iBeacon $uuid major=$major minor=$minor tx=$measuredPower';
}

IBeacon? parseIBeacon({required int companyId, required List<int> bytes}) {
  if (companyId != 0x004C) return null;
  if (bytes.length < 23) return null;
  if (bytes[0] != 0x02 || bytes[1] != 0x15) return null;
  final uuidBytes = bytes.sublist(2, 18);
  final hex = uuidBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final uuid = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  final major = (bytes[18] << 8) | bytes[19];
  final minor = (bytes[20] << 8) | bytes[21];
  // measured power is signed int8
  final mp = bytes[22] > 127 ? bytes[22] - 256 : bytes[22];
  return IBeacon(uuid: uuid, major: major, minor: minor, measuredPower: mp);
}

enum EddystoneFrameType { uid, url, tlm, eid, unknown }

class Eddystone {
  const Eddystone({required this.frameType, required this.payload});
  final EddystoneFrameType frameType;
  final String payload;
}

/// Decode the [serviceData] for the Eddystone service UUID 0xFEAA.
Eddystone? parseEddystone(List<int> serviceData) {
  if (serviceData.isEmpty) return null;
  final type = serviceData[0];
  switch (type) {
    case 0x00:
      if (serviceData.length < 18) return null;
      final namespace = serviceData
          .sublist(2, 12)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final instance = serviceData
          .sublist(12, 18)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      return Eddystone(
        frameType: EddystoneFrameType.uid,
        payload: 'namespace=$namespace instance=$instance',
      );
    case 0x10:
      if (serviceData.length < 4) return null;
      const schemes = ['http://www.', 'https://www.', 'http://', 'https://'];
      const encodings = {
        0x00: '.com/',
        0x01: '.org/',
        0x02: '.edu/',
        0x03: '.net/',
        0x04: '.info/',
        0x05: '.biz/',
        0x06: '.gov/',
        0x07: '.com',
        0x08: '.org',
        0x09: '.edu',
        0x0A: '.net',
        0x0B: '.info',
        0x0C: '.biz',
        0x0D: '.gov',
      };
      final schemeByte = serviceData[2];
      if (schemeByte >= schemes.length) return null;
      final buf = StringBuffer(schemes[schemeByte]);
      for (final b in serviceData.sublist(3)) {
        if (encodings.containsKey(b)) {
          buf.write(encodings[b]);
        } else if (b >= 0x20 && b < 0x7F) {
          buf.writeCharCode(b);
        }
      }
      return Eddystone(
        frameType: EddystoneFrameType.url,
        payload: buf.toString(),
      );
    case 0x20:
      if (serviceData.length < 14) return null;
      final batteryMv = (serviceData[2] << 8) | serviceData[3];
      final tempRaw = (serviceData[4] << 8) | serviceData[5];
      final tempC = tempRaw / 256.0;
      return Eddystone(
        frameType: EddystoneFrameType.tlm,
        payload: 'battery=${batteryMv}mV temp=${tempC.toStringAsFixed(1)}°C',
      );
    case 0x30:
      return Eddystone(frameType: EddystoneFrameType.eid, payload: '(EID)');
    default:
      return Eddystone(
          frameType: EddystoneFrameType.unknown, payload: 'frame=0x${type.toRadixString(16)}');
  }
}

String eddystoneTypeLabel(EddystoneFrameType t) {
  switch (t) {
    case EddystoneFrameType.uid:
      return 'Eddystone-UID';
    case EddystoneFrameType.url:
      return 'Eddystone-URL';
    case EddystoneFrameType.tlm:
      return 'Eddystone-TLM';
    case EddystoneFrameType.eid:
      return 'Eddystone-EID';
    case EddystoneFrameType.unknown:
      return 'Eddystone (unknown frame)';
  }
}
