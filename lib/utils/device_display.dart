import '../models/device_record.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';

/// Derived display state for a single device, computed once at the top of a
/// build method instead of duplicating the same nine lookups in every widget.
///
/// Pulls together the singleton services (DeviceMemory, BondedDeviceRegistry,
/// AppSettings) so the rest of the UI just reads fields off this struct.
class DeviceDisplay {
  const DeviceDisplay({
    required this.record,
    required this.customLabel,
    required this.bondedName,
    required this.displayName,
    required this.isFavorite,
    required this.isPaired,
    required this.hasAdvertisedName,
    required this.smoothedRssi,
    required this.calibratedTxPower,
    required this.isStale,
    required this.isOffline,
    required this.ageSeconds,
  });

  final DeviceRecord record;
  final String? customLabel;
  final String? bondedName;
  final String displayName;
  final bool isFavorite;
  final bool isPaired;
  final bool hasAdvertisedName;
  final int smoothedRssi;
  final int? calibratedTxPower;
  final bool isStale;
  final bool isOffline;
  final int ageSeconds;

  /// Builds the derived display state by consulting the relevant singletons.
  /// Cheap — no I/O — so safe to call inside build methods.
  factory DeviceDisplay.from(DeviceRecord rec) {
    final mem = DeviceMemory.instance;
    final settings = AppSettings.instance;
    final id = rec.id.str;
    final customLabel = mem.labelFor(id);
    final bondedName = BondedDeviceRegistry.instance.bondedNameFor(id);
    final hasName = rec.localName != null && rec.localName!.isNotEmpty;
    final displayName =
        customLabel ?? bondedName ?? (hasName ? rec.name : '(unnamed)');
    final age = DateTime.now().difference(rec.lastSeen).inSeconds;

    return DeviceDisplay(
      record: rec,
      customLabel: customLabel,
      bondedName: bondedName,
      displayName: displayName,
      isFavorite: mem.isFavorite(id),
      isPaired: bondedName != null,
      hasAdvertisedName: hasName,
      smoothedRssi: rec.smoothedRssi(settings.smoothingWindow),
      calibratedTxPower: mem.calibratedTxPowerFor(id),
      isStale: age >= settings.staleAfterSeconds,
      isOffline: rec.isOfflineFor(settings.offlineThreshold),
      ageSeconds: age,
    );
  }
}
