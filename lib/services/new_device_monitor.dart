import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Tracks which Bluetooth IDs we've *ever* seen (above the sensitivity floor),
/// so we can flag genuinely-new devices with a NEW badge.
///
/// Caveat: many devices rotate their MAC address every ~15 min for privacy.
/// Those will keep registering as "new" every rotation. That's fine — it's
/// honest behavior: from this app's perspective the device really is new.
class NewDeviceMonitor extends ChangeNotifier {
  NewDeviceMonitor._();

  static final NewDeviceMonitor instance = NewDeviceMonitor._();

  static const _prefsKey = 'known_device_ids_v1';
  static const _milestonePrefsKey = 'highest_milestone_reached_v1';
  static const _maxKnownIds = 2000;
  static const Duration _newBadgeDuration = Duration(minutes: 30);

  /// Lifetime totals that trigger a celebratory toast when crossed. Tuned so
  /// the early ones feel rewarding and the later ones aren't spammy.
  static const List<int> _milestones = [1, 10, 50, 100, 250, 500, 1000, 2500];

  final Set<String> _knownIds = {};
  final Map<String, DateTime> _firstSeenThisSession = {};
  int _highestMilestoneReached = 0;

  /// The next milestone we've crossed but haven't yet displayed (consumed
  /// by the UI via [popPendingMilestone]). Null when nothing's pending.
  int? _pendingMilestone;

  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get knownCount => _knownIds.length;

  /// Returns and clears any unshown milestone. UI calls this on each
  /// notifyListeners tick and shows a toast if non-null.
  int? popPendingMilestone() {
    final m = _pendingMilestone;
    _pendingMilestone = null;
    return m;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey);
    if (list != null) _knownIds.addAll(list);
    _highestMilestoneReached = prefs.getInt(_milestonePrefsKey) ?? 0;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    var ids = _knownIds.toList();
    if (ids.length > _maxKnownIds) {
      ids = ids.sublist(ids.length - _maxKnownIds);
      _knownIds
        ..clear()
        ..addAll(ids);
    }
    await prefs.setStringList(_prefsKey, ids);
  }

  /// Map sensitivity 1-5 to a minimum RSSI in dBm. Higher sensitivity =
  /// register weaker signals = bigger area.
  static int rssiThreshold(int sensitivity) {
    switch (sensitivity.clamp(1, 5)) {
      case 1:
        return -50;
      case 2:
        return -65;
      case 3:
        return -75;
      case 4:
        return -85;
      default:
        return -95;
    }
  }

  /// Call from the scanner when a device is observed. If this is the first
  /// time we've ever seen it AND its current signal beats the sensitivity
  /// floor, it gets registered and badged as new.
  void observe(String id, int rssi) {
    final threshold = rssiThreshold(AppSettings.instance.monitoringSensitivity);
    if (rssi < threshold) return;
    if (_knownIds.contains(id)) return;
    _knownIds.add(id);
    _firstSeenThisSession[id] = DateTime.now();
    _checkMilestone();
    _save();
    notifyListeners();
  }

  void _checkMilestone() {
    final count = _knownIds.length;
    for (final m in _milestones) {
      if (count >= m && m > _highestMilestoneReached) {
        _highestMilestoneReached = m;
        _pendingMilestone = m;
        // Persist asynchronously so we don't re-fire the same milestone if
        // the app is killed and restarted before save completes.
        SharedPreferences.getInstance().then(
          (p) => p.setInt(_milestonePrefsKey, m),
        );
      }
    }
  }

  /// True if this device was added to the known set during the current
  /// session and the NEW badge hasn't yet aged out.
  bool isNew(String id) {
    final age = sinceFirstSeen(id);
    return age != null && age < _newBadgeDuration;
  }

  /// How long ago we first noticed this device this session. Null if we
  /// never saw it appear (i.e., it was already in the known set on load).
  Duration? sinceFirstSeen(String id) {
    final firstSeen = _firstSeenThisSession[id];
    if (firstSeen == null) return null;
    return DateTime.now().difference(firstSeen);
  }

  Future<void> forgetAll() async {
    _knownIds.clear();
    _firstSeenThisSession.clear();
    _highestMilestoneReached = 0;
    _pendingMilestone = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_milestonePrefsKey);
  }
}
