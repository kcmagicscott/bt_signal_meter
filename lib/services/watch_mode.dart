import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scanner_state.dart';
import 'app_settings.dart';
import 'device_memory.dart';

/// Watches favorited devices and posts a system notification whenever one
/// changes between "in range" and "out of range." Operates while the app is
/// in the foreground or recently backgrounded — true background-when-app-closed
/// would require an Android foreground service, which is a future addition.
class WatchMode extends ChangeNotifier {
  WatchMode._();
  static final WatchMode instance = WatchMode._();

  static const _prefsKey = 'watch_mode.enabled';
  static const _channelId = 'bt_watch';
  static const _channelName = 'Favorite device alerts';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _enabled = false;
  bool _initialized = false;

  /// Last-known in-range state per favorite remote ID.
  final Map<String, bool> _inRangeState = {};

  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;
    if (_enabled) {
      await _init();
      ScannerState.instance.addListener(_onScanChange);
    }
    notifyListeners();
  }

  Future<bool> _init() async {
    if (_initialized) return true;
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: init);
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications when a favorited device enters or leaves range',
        importance: Importance.high,
      );
      await android.createNotificationChannel(channel);
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    _initialized = true;
    return true;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    if (value) {
      await _init();
      _inRangeState.clear();
      ScannerState.instance.addListener(_onScanChange);
    } else {
      ScannerState.instance.removeListener(_onScanChange);
      _inRangeState.clear();
    }
    notifyListeners();
  }

  void _onScanChange() {
    if (!_enabled) return;
    final mem = DeviceMemory.instance;
    final scanner = ScannerState.instance;
    final offlineThreshold = AppSettings.instance.offlineThreshold;

    for (final d in scanner.allDevices.values) {
      if (!mem.isFavorite(d.id.str)) continue;
      final isInRange = !d.isOfflineFor(offlineThreshold);
      final wasInRange = _inRangeState[d.id.str];
      if (wasInRange == null) {
        // First observation in this session — record but don't alert
        // (avoids spamming on app start).
        _inRangeState[d.id.str] = isInRange;
        continue;
      }
      if (isInRange == wasInRange) continue;
      _inRangeState[d.id.str] = isInRange;
      _notify(d.id.str, mem.labelFor(d.id.str) ?? d.name, isInRange);
    }
  }

  Future<void> _notify(
    String id,
    String name,
    bool isInRange,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
    );
    final details = const NotificationDetails(android: androidDetails);
    final title = isInRange ? '🟢 $name nearby' : '🔴 $name out of range';
    final body = isInRange
        ? 'Signal strong enough to detect — last heard now.'
        : 'No signal for the last ${AppSettings.instance.offlineThreshold.inSeconds}s.';
    await _plugin.show(
      id: id.hashCode,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
