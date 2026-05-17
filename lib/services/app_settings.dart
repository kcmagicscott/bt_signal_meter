import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How tightly device tiles are packed in the scanner list. Cycling
/// through these is the main way to handle scenes with many devices
/// (e.g., 400+ in a crowded space).
enum DensityMode {
  comfortable,
  compact,
  dense;

  String get _key => switch (this) {
        DensityMode.comfortable => 'comfortable',
        DensityMode.compact => 'compact',
        DensityMode.dense => 'dense',
      };

  static DensityMode fromKey(String? s) => switch (s) {
        'compact' => DensityMode.compact,
        'dense' => DensityMode.dense,
        _ => DensityMode.comfortable,
      };

  DensityMode get next => switch (this) {
        DensityMode.comfortable => DensityMode.compact,
        DensityMode.compact => DensityMode.dense,
        DensityMode.dense => DensityMode.comfortable,
      };
}

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
  static const _kDensityMode = 'settings.density_mode';

  int _chartWindowSeconds = 60;
  int _staleAfterSeconds = 5;
  int _smoothingWindow = 5;
  bool _keepScreenOn = false;
  int _reorderIntervalSeconds = 3;
  int _monitoringSensitivity = 3;
  bool _imperialDistance = false;
  DensityMode _densityMode = DensityMode.comfortable;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  int get chartWindowSeconds => _chartWindowSeconds;
  int get staleAfterSeconds => _staleAfterSeconds;
  int get smoothingWindow => _smoothingWindow;
  bool get keepScreenOn => _keepScreenOn;
  int get reorderIntervalSeconds => _reorderIntervalSeconds;
  int get monitoringSensitivity => _monitoringSensitivity;
  bool get imperialDistance => _imperialDistance;
  DensityMode get densityMode => _densityMode;

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
    _densityMode = DensityMode.fromKey(prefs.getString(_kDensityMode));
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDensityMode(DensityMode mode) async {
    _densityMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDensityMode, mode._key);
  }

  Future<void> cycleDensityMode() => setDensityMode(_densityMode.next);

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
