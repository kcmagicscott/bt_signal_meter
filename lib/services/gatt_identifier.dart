import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/uuids.dart';

/// Identity readout pulled from a BLE peripheral's Device Information service
/// (0x180A). Most consumer products implement at least the manufacturer and
/// model number characteristics, giving us an authoritative product name.
class GattIdentity {
  const GattIdentity({
    this.manufacturer,
    this.modelNumber,
    this.firmwareRevision,
    this.hardwareRevision,
    this.queriedAt,
  });

  final String? manufacturer;
  final String? modelNumber;
  final String? firmwareRevision;
  final String? hardwareRevision;
  final DateTime? queriedAt;

  bool get isEmpty =>
      manufacturer == null && modelNumber == null &&
      firmwareRevision == null && hardwareRevision == null;

  /// Concatenated headline string for list display.
  String get headline {
    final parts = <String>[
      ?manufacturer,
      ?modelNumber,
    ];
    return parts.isEmpty ? '(no DIS data)' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        if (manufacturer != null) 'mfr': manufacturer,
        if (modelNumber != null) 'model': modelNumber,
        if (firmwareRevision != null) 'fw': firmwareRevision,
        if (hardwareRevision != null) 'hw': hardwareRevision,
        if (queriedAt != null) 't': queriedAt!.toIso8601String(),
      };

  factory GattIdentity.fromJson(Map<String, dynamic> j) => GattIdentity(
        manufacturer: j['mfr'] as String?,
        modelNumber: j['model'] as String?,
        firmwareRevision: j['fw'] as String?,
        hardwareRevision: j['hw'] as String?,
        queriedAt:
            j['t'] == null ? null : DateTime.tryParse(j['t'] as String),
      );
}

/// Connects to a BLE device on demand, reads the Device Information service,
/// caches the result. Once cached, repeated lookups return immediately.
class GattIdentifier extends ChangeNotifier {
  GattIdentifier._();
  static final GattIdentifier instance = GattIdentifier._();

  static const _prefsKey = 'gatt_identities_v1';

  final Map<String, GattIdentity> _cache = {};

  /// IDs the user has explicitly asked us not to retry (cached miss).
  final Set<String> _inFlight = {};

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _cache[entry.key] =
              GattIdentity.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Corrupt prefs — drop them.
    }
    _loaded = true;
  }

  GattIdentity? cached(String id) => _cache[id];

  bool isPending(String id) => _inFlight.contains(id);

  /// Connects, reads DIS, disconnects. Returns the parsed identity or null
  /// if the device couldn't be reached. Caches successful results.
  Future<GattIdentity?> lookup(
    DeviceIdentifier id, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final key = id.str;
    if (_inFlight.contains(key)) return _cache[key];
    _inFlight.add(key);
    notifyListeners();

    final device = BluetoothDevice.fromId(key);
    GattIdentity? result;
    try {
      await device.connect(
        timeout: timeout,
        license: License.free,
        autoConnect: false,
      );
      final services = await device.discoverServices(timeout: 10);
      final dis = services.where(
        (s) => s.serviceUuid.str.toLowerCase() == kDeviceInformationServiceUuid,
      );
      if (dis.isNotEmpty) {
        result = await _readDis(dis.first);
      }
    } catch (_) {
      // Connection failed, device out of range, doesn't implement GATT, etc.
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
      _inFlight.remove(key);
    }

    if (result != null && !result.isEmpty) {
      _cache[key] = result;
      _persist();
    }
    notifyListeners();
    return result;
  }

  Future<GattIdentity> _readDis(BluetoothService dis) async {
    String? mfr;
    String? model;
    String? fw;
    String? hw;
    for (final c in dis.characteristics) {
      final uuid = c.characteristicUuid.str.toLowerCase();
      if (!c.properties.read) continue;
      try {
        final value = await c.read(timeout: 5);
        final s = _decodeAscii(value);
        if (s == null) continue;
        switch (uuid) {
          case kManufacturerNameCharUuid:
            mfr = s;
            break;
          case kModelNumberCharUuid:
            model = s;
            break;
          case kFirmwareRevisionCharUuid:
            fw = s;
            break;
          case kHardwareRevisionCharUuid:
            hw = s;
            break;
        }
      } catch (_) {
        // Skip this characteristic and keep going.
      }
    }
    return GattIdentity(
      manufacturer: mfr,
      modelNumber: model,
      firmwareRevision: fw,
      hardwareRevision: hw,
      queriedAt: DateTime.now(),
    );
  }

  String? _decodeAscii(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final str = String.fromCharCodes(bytes)
          .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
          .trim();
      return str.isEmpty ? null : str;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode({
        for (final e in _cache.entries) e.key: e.value.toJson(),
      });
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  Future<void> forget(String id) async {
    _cache.remove(id);
    _persist();
    notifyListeners();
  }

  Future<void> forgetAll() async {
    _cache.clear();
    _persist();
    notifyListeners();
  }
}
