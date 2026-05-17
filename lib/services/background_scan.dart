import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import 'app_settings.dart';
import 'device_memory.dart';

/// Keeps a persistent "ongoing" system notification pinned with the current
/// strongest device, so the user can glance at the shade during long site
/// surveys without bringing the app forward. Updates are throttled to once
/// per ~2s to avoid notification spam.
///
/// Scope note: This pins a notification while the Flutter process is alive.
/// Truly background-when-app-is-killed scanning needs a native Android
/// foreground service (Kotlin); the manifest already grants the permissions
/// for that follow-up. Today the notification + a screen-on session is the
/// practical answer for "leave the phone on the table and watch the shade."
class BackgroundScan extends ChangeNotifier {
  BackgroundScan._();
  static final BackgroundScan instance = BackgroundScan._();

  static const _prefsKey = 'background_scan.enabled';
  static const _channelId = 'bt_background_scan';
  static const _channelName = 'Persistent scan summary';
  static const _notificationId = 0xB7517; // arbitrary, stable

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _enabled = false;
  bool _initialized = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastBody = '';
  Timer? _refreshTimer;

  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;
    if (_enabled) {
      await _attach();
    }
    notifyListeners();
  }

  Future<bool> _init() async {
    if (_initialized) return true;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: init);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description:
            'Pinned summary of the strongest Bluetooth device while scanning',
        importance: Importance.low,
      );
      await android.createNotificationChannel(channel);
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    _initialized = true;
    return true;
  }

  Future<void> _attach() async {
    await _init();
    ScannerState.instance.addListener(_onScanChange);
    // Refresh every few seconds so the "x active" count decays even when
    // no new scan results arrive (e.g. quiet room, adapter throttling).
    _refreshTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _onScanChange(),
    );
    _onScanChange();
  }

  void _detach() {
    ScannerState.instance.removeListener(_onScanChange);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _plugin.cancel(id: _notificationId);
    _lastBody = '';
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    if (value) {
      await _attach();
    } else {
      _detach();
    }
    notifyListeners();
  }

  void _onScanChange() {
    if (!_enabled) return;
    final now = DateTime.now();
    // Throttle: at most one notification update every ~1.5s.
    if (now.difference(_lastUpdate).inMilliseconds < 1500) return;

    final scanner = ScannerState.instance;
    final offlineThreshold = AppSettings.instance.offlineThreshold;
    DeviceRecord? strongest;
    int active = 0;
    for (final d in scanner.allDevices.values) {
      if (d.isOfflineFor(offlineThreshold)) continue;
      active++;
      if (strongest == null || d.currentRssi > strongest.currentRssi) {
        strongest = d;
      }
    }

    final body = _bodyFor(strongest, active, scanner.isScanning);
    if (body == _lastBody) return;
    _lastBody = body;
    _lastUpdate = now;
    _post(body);
  }

  String _bodyFor(DeviceRecord? strongest, int active, bool scanning) {
    if (!scanning && strongest == null) {
      return 'Scanner idle — open the app to start a scan.';
    }
    if (strongest == null) {
      return 'Scanning · no devices in range yet';
    }
    final mem = DeviceMemory.instance;
    final name = mem.labelFor(strongest.id.str) ?? strongest.name;
    final activeLabel =
        active == 1 ? '1 device active' : '$active devices active';
    return '$name · ${strongest.currentRssi} dBm · $activeLabel';
  }

  Future<void> _post(String body) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      category: AndroidNotificationCategory.status,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: _notificationId,
      title: 'BT Signal Meter',
      body: body,
      notificationDetails: details,
    );
  }
}
