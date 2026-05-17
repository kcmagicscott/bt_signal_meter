import '../models/device_record.dart';
import 'uuids.dart';

/// One snapshot of environmental sensor data extracted from a BLE advert.
/// Fields are nullable so a parser can report only the values it understood.
class SensorReading {
  const SensorReading({
    this.source,
    this.temperatureC,
    this.humidityPercent,
    this.pressureHpa,
    this.batteryPercent,
    this.txPowerDbm,
  });

  final String? source; // e.g. "Ruuvi v5", "Govee H5075", "Xiaomi ATC"
  final double? temperatureC;
  final double? humidityPercent;
  final double? pressureHpa;
  final int? batteryPercent;
  final int? txPowerDbm;

  bool get isEmpty =>
      temperatureC == null &&
      humidityPercent == null &&
      pressureHpa == null &&
      batteryPercent == null &&
      txPowerDbm == null;

  String temperatureF() =>
      temperatureC == null ? '—' : '${(temperatureC! * 9 / 5 + 32).toStringAsFixed(1)}°F';

  String temperatureCStr() =>
      temperatureC == null ? '—' : '${temperatureC!.toStringAsFixed(1)}°C';

  String humidityStr() =>
      humidityPercent == null ? '—' : '${humidityPercent!.toStringAsFixed(0)}%';
}

const String _xiaomiAtcServiceUuid = kEnvironmentalSensingServiceUuid;
const String _xiaomiNativeServiceUuid = kXiaomiMiBeaconServiceUuid;

/// Try every known sensor format in turn. Returns the first non-empty reading
/// it finds, or null if nothing matched.
SensorReading? parseSensorData(DeviceRecord r) {
  // Ruuvi: manufacturer ID 0x0499.
  if (r.manufacturerId == 0x0499) {
    final ruuvi = _parseRuuvi(r.rawManufacturerBytes);
    if (ruuvi != null) return ruuvi;
  }

  // Govee H5075 / H5072 / H5101: manufacturer ID 0xEC88.
  if (r.manufacturerId == 0xEC88) {
    final govee = _parseGoveeH5075(r.rawManufacturerBytes);
    if (govee != null) return govee;
  }

  // Xiaomi LYWSD03MMC with custom ATC/pvvx firmware: service data 0x181A.
  final atc = r.serviceData[_xiaomiAtcServiceUuid];
  if (atc != null) {
    final reading = _parseXiaomiAtc(atc);
    if (reading != null) return reading;
  }

  // Xiaomi native Mijia format: service data 0xFE95.
  final mijia = r.serviceData[_xiaomiNativeServiceUuid];
  if (mijia != null) {
    final reading = _parseXiaomiMijia(mijia);
    if (reading != null) return reading;
  }

  return null;
}

/// Ruuvi RAW v5 format. 24 bytes after the company ID byte.
/// Reference: https://docs.ruuvi.com/communication/bluetooth-advertisements/data-format-5-rawv2
SensorReading? _parseRuuvi(List<int> bytes) {
  if (bytes.isEmpty || bytes[0] != 0x05) return null;
  if (bytes.length < 23) return null;

  int signed16(int hi, int lo) {
    final v = (hi << 8) | lo;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  final tempRaw = signed16(bytes[1], bytes[2]);
  final humidRaw = (bytes[3] << 8) | bytes[4];
  final pressRaw = (bytes[5] << 8) | bytes[6];
  final battTx = (bytes[13] << 8) | bytes[14];

  final temp = tempRaw == 0x8000 ? null : tempRaw * 0.005;
  final humid = humidRaw == 0xFFFF ? null : humidRaw * 0.0025;
  final press = pressRaw == 0xFFFF ? null : (pressRaw + 50000) / 100.0;

  // Top 11 bits: battery voltage offset from 1.6 V in mV; bottom 5: TX power.
  final battMv = (battTx >> 5) == 0x7FF ? null : 1600 + (battTx >> 5);
  final txPower = (battTx & 0x1F) == 0x1F ? null : -40 + ((battTx & 0x1F) * 2);
  // Map battery mV to percent assuming CR2477 range (1.8-3.0V).
  int? battPct;
  if (battMv != null) {
    final pct = ((battMv - 1800) / (3000 - 1800) * 100).round();
    battPct = pct.clamp(0, 100);
  }

  return SensorReading(
    source: 'Ruuvi v5',
    temperatureC: temp,
    humidityPercent: humid,
    pressureHpa: press,
    batteryPercent: battPct,
    txPowerDbm: txPower,
  );
}

/// Govee H5075 / H5072 format. Manufacturer data layout:
///   [0x00] [byte1 byte2 byte3 -> packed temp+humid] [batt%] [...]
SensorReading? _parseGoveeH5075(List<int> bytes) {
  if (bytes.length < 5) return null;
  // The packed value spans bytes 1..3 (big-endian). High bit signals negative.
  final raw = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  final sign = (raw & 0x800000) != 0;
  final magnitude = raw & 0x7FFFFF;
  final tempC = (sign ? -1 : 1) * (magnitude / 10000).floorToDouble() / 1.0
      + ((sign ? -1 : 1) * (magnitude % 10000) / 10000.0);
  // Cleaner: temp = (magnitude / 1000) / 10.0 minus humidity contribution.
  // Govee packs as: combo = temp*10000 + humid (humid as 0..100.0 scaled).
  final tempIntPart = magnitude ~/ 1000;
  final humidIntPart = magnitude % 1000;
  final tempCleaned = (sign ? -1 : 1) * (tempIntPart / 10.0);
  final humidCleaned = humidIntPart / 10.0;
  final battery = bytes[4].clamp(0, 100);

  // Use the cleaned values when they look sane (Govee can ship 5072 vs 5075
  // with slightly different scales; the cleaned form matches H5075).
  return SensorReading(
    source: 'Govee H50xx',
    temperatureC: (tempCleaned.abs() > 100) ? tempC : tempCleaned,
    humidityPercent: (humidCleaned <= 100) ? humidCleaned : null,
    batteryPercent: battery,
  );
}

/// Xiaomi LYWSD03MMC with ATC / pvvx custom firmware (very common mod).
/// ATC layout: 6 bytes MAC, 2 bytes temp*10 (int16, big-endian), 2 bytes
/// humidity*100 (uint16, big-endian), 1 byte battery%, 2 bytes battery mV,
/// 1 byte counter.
SensorReading? _parseXiaomiAtc(List<int> bytes) {
  if (bytes.length < 13) return null;
  // ATC pvvx vs vanilla differ; vanilla ATC is big-endian, pvvx is little.
  // Heuristic: if bytes[6] is plausible as int16 high byte for room temp, use BE.
  int signed16(int hi, int lo) {
    final v = (hi << 8) | lo;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  final tempBe = signed16(bytes[6], bytes[7]) / 10.0;
  final tempLe = signed16(bytes[7], bytes[6]) / 100.0;
  final useBe = tempBe.abs() < 80;

  final tempC = useBe ? tempBe : tempLe;
  final humidRaw = useBe
      ? (bytes[8] << 8) | bytes[9]
      : (bytes[9] << 8) | bytes[8];
  final humid = useBe ? humidRaw / 100.0 : humidRaw / 100.0;
  final battery = bytes[10] <= 100 ? bytes[10] : null;

  return SensorReading(
    source: useBe ? 'Xiaomi ATC' : 'Xiaomi ATC (pvvx)',
    temperatureC: tempC,
    humidityPercent: humid > 100 ? null : humid,
    batteryPercent: battery,
  );
}

/// Xiaomi native Mijia frame is a multi-TLV format. We only extract the
/// common sub-events: temp (0x04), humidity (0x06), combo (0x0D), battery
/// (0x0A). Returns null if no recognizable TLV was found.
SensorReading? _parseXiaomiMijia(List<int> bytes) {
  // Look for an 11-byte minimum: frame-control(2) + dev-id(2) + counter +
  // mac(6) + capabilities... most consumer adverts are 14+ bytes. Scan from
  // a generous offset onward for TLV markers.
  if (bytes.length < 14) return null;
  double? temp;
  double? humid;
  int? batt;
  int i = 11;
  while (i + 3 < bytes.length) {
    final type = bytes[i];
    final len = bytes[i + 2];
    if (i + 3 + len > bytes.length) break;
    final payload = bytes.sublist(i + 3, i + 3 + len);
    switch (type) {
      case 0x04:
        if (payload.length >= 2) {
          final v = (payload[1] << 8) | payload[0];
          final s = v >= 0x8000 ? v - 0x10000 : v;
          temp = s / 10.0;
        }
        break;
      case 0x06:
        if (payload.length >= 2) {
          humid = ((payload[1] << 8) | payload[0]) / 10.0;
        }
        break;
      case 0x0D:
        if (payload.length >= 4) {
          final t = (payload[1] << 8) | payload[0];
          final h = (payload[3] << 8) | payload[2];
          temp = (t >= 0x8000 ? t - 0x10000 : t) / 10.0;
          humid = h / 10.0;
        }
        break;
      case 0x0A:
        if (payload.isNotEmpty) batt = payload[0];
        break;
    }
    i += 3 + len;
  }
  if (temp == null && humid == null && batt == null) return null;
  return SensorReading(
    source: 'Xiaomi Mijia',
    temperatureC: temp,
    humidityPercent: (humid != null && humid <= 100) ? humid : null,
    batteryPercent: batt,
  );
}
