import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide tunables, persisted across launches.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _kChartWindow = 'settings.chart_window_s';
  static const _kStaleAfter = 'settings.stale_after_s';
  static const _kSmoothing = 'settings.smoothing_window';
  static const _kKeepScreenOn = 'settings.keep_screen_on';
  static const _kReorderInterval = 'settings.reorder_interval_s';
  static const _kMonitoringSensitivity = 'settings.monitoring_sensitivity';
  static const _kImperialDistance = 'settings.imperial_distance';

  int _chartWindowSeconds = 60;
  int _staleAfterSeconds = 5;
  int _smoothingWindow = 5;
  bool _keepScreenOn = false;
  int _reorderIntervalSeconds = 3;
  int _monitoringSensitivity = 3;
  bool _imperialDistance = false;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  int get chartWindowSeconds => _chartWindowSeconds;
  int get staleAfterSeconds => _staleAfterSeconds;
  int get smoothingWindow => _smoothingWindow;
  bool get keepScreenOn => _keepScreenOn;
  int get reorderIntervalSeconds => _reorderIntervalSeconds;
  int get monitoringSensitivity => _monitoringSensitivity;
  bool get imperialDistance => _imperialDistance;

  /// Length of silence after which we consider a device offline (vs. merely stale).
  Duration get offlineThreshold =>
      Duration(seconds: (_staleAfterSeconds * 3).clamp(6, 60));

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _chartWindowSeconds = prefs.getInt(_kChartWindow) ?? 60;
    _staleAfterSeconds = prefs.getInt(_kStaleAfter) ?? 5;
    _smoothingWindow = prefs.getInt(_kSmoothing) ?? 5;
    _keepScreenOn = prefs.getBool(_kKeepScreenOn) ?? false;
    _reorderIntervalSeconds = prefs.getInt(_kReorderInterval) ?? 3;
    _monitoringSensitivity = prefs.getInt(_kMonitoringSensitivity) ?? 3;
    _imperialDistance = prefs.getBool(_kImperialDistance) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setImperialDistance(bool v) async {
    _imperialDistance = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kImperialDistance, v);
  }

  Future<void> setChartWindowSeconds(int v) async {
    _chartWindowSeconds = v.clamp(15, 600);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kChartWindow, _chartWindowSeconds);
  }

  Future<void> setStaleAfterSeconds(int v) async {
    _staleAfterSeconds = v.clamp(2, 60);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStaleAfter, _staleAfterSeconds);
  }

  Future<void> setSmoothingWindow(int v) async {
    _smoothingWindow = v.clamp(1, 20);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSmoothing, _smoothingWindow);
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepScreenOn, v);
  }

  Future<void> setReorderIntervalSeconds(int v) async {
    _reorderIntervalSeconds = v.clamp(0, 30);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReorderInterval, _reorderIntervalSeconds);
  }

  Future<void> setMonitoringSensitivity(int v) async {
    _monitoringSensitivity = v.clamp(1, 5);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMonitoringSensitivity, _monitoringSensitivity);
  }
}
