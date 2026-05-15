import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Caches the OS's list of bonded/paired Bluetooth devices so we can
/// (a) mark scan results that match a paired device, and (b) use the
/// human-readable pairing name (e.g. "Bose QC45") as a fallback when
/// the BLE advertisement is anonymous.
class BondedDeviceRegistry extends ChangeNotifier {
  BondedDeviceRegistry._();
  static final BondedDeviceRegistry instance = BondedDeviceRegistry._();

  final Map<String, String> _bondedNames = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get pairedCount => _bondedNames.length;
  Iterable<MapEntry<String, String>> get all => _bondedNames.entries;

  Future<void> refresh() async {
    try {
      final devices = await FlutterBluePlus.bondedDevices;
      _bondedNames.clear();
      for (final d in devices) {
        final name = d.platformName.isNotEmpty
            ? d.platformName
            : d.advName.isNotEmpty
                ? d.advName
                : '(paired device)';
        _bondedNames[d.remoteId.str] = name;
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Older Android, missing permission, or not Android — keep empty.
      _loaded = true;
      notifyListeners();
    }
  }

  String? bondedNameFor(String id) => _bondedNames[id];
  bool isBonded(String id) => _bondedNames.containsKey(id);
}
