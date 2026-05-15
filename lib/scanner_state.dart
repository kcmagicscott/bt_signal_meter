import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/device_record.dart';
import 'services/app_settings.dart';
import 'services/bonded_device_registry.dart';
import 'services/device_memory.dart';
import 'services/new_device_monitor.dart';

enum SortMode { signalDesc, signalAsc, nameAsc, lastSeenDesc }

const _kFavoritesOnly = 'scanner.favorites_only';
const _kHideUnnamed = 'scanner.hide_unnamed';
const _kSortMode = 'scanner.sort_mode';

class ScannerState extends ChangeNotifier {
  ScannerState._() {
    void swallow(Object _, StackTrace _) {
      // Plugin is unavailable (e.g. unit-test environment).
    }
    try {
      _isScanningSub = FlutterBluePlus.isScanning.listen(
        (scanning) {
          _isScanning = scanning;
          _restartTickTimer();
          notifyListeners();
        },
        onError: swallow,
      );
      _scanResultsSub = FlutterBluePlus.scanResults.listen(
        _handleResults,
        onError: swallow,
      );
      _adapterStateSub = FlutterBluePlus.adapterState.listen(
        (state) {
          _adapterState = state;
          notifyListeners();
        },
        onError: swallow,
      );
    } catch (_) {
      // Plugin construction itself failed; soft-fail.
    }
  }

  Timer? _tickTimer;

  void _restartTickTimer() {
    _tickTimer?.cancel();
    if (_isScanning) {
      _tickTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else {
      _tickTimer = null;
    }
  }

  static final ScannerState instance = ScannerState._();

  final Map<DeviceIdentifier, DeviceRecord> _devices = {};
  bool _isScanning = false;
  String? _statusMessage;
  String _searchQuery = '';
  SortMode _sortMode = SortMode.signalDesc;
  bool _hideUnnamed = false;
  bool _favoritesOnly = false;
  int? _manufacturerFilter; // null = no filter; -1 = "unknown" bucket

  /// Set of distinct manufacturer IDs seen in current results.
  /// Includes the sentinel `-1` if any device has no manufacturer.
  Set<int> get manufacturersPresent {
    final s = <int>{};
    for (final d in _devices.values) {
      s.add(d.manufacturerId ?? -1);
    }
    return s;
  }

  int? get manufacturerFilter => _manufacturerFilter;
  void setManufacturerFilter(int? id) {
    _manufacturerFilter = id;
    _invalidateSort();
    notifyListeners();
  }

  // Cached sort order so signal jitter doesn't reshuffle the list every result.
  List<DeviceIdentifier> _sortedIds = [];
  DateTime _lastSortAt = DateTime.fromMillisecondsSinceEpoch(0);
  SortMode? _lastSortedMode;

  void _invalidateSort() {
    _sortedIds = [];
    _lastSortAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  bool get isScanning => _isScanning;
  String? get statusMessage => _statusMessage;
  String get searchQuery => _searchQuery;
  SortMode get sortMode => _sortMode;
  bool get hideUnnamed => _hideUnnamed;
  bool get favoritesOnly => _favoritesOnly;
  BluetoothAdapterState get adapterState => _adapterState;
  bool get isAdapterOn => _adapterState == BluetoothAdapterState.on;

  Future<void> tryTurnOnAdapter() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}
  }

  /// Loads persisted UI filter state. Safe to call multiple times.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _favoritesOnly = prefs.getBool(_kFavoritesOnly) ?? false;
      _hideUnnamed = prefs.getBool(_kHideUnnamed) ?? false;
      final mode = prefs.getInt(_kSortMode);
      if (mode != null && mode >= 0 && mode < SortMode.values.length) {
        _sortMode = SortMode.values[mode];
      }
      notifyListeners();
    } catch (_) {
      // Plugin unavailable (e.g. unit test); ignore.
    }
  }

  Future<void> _persistBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _persistInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {}
  }

  Map<DeviceIdentifier, DeviceRecord> get allDevices =>
      Map.unmodifiable(_devices);

  DeviceRecord? deviceFor(DeviceIdentifier id) => _devices[id];

  List<DeviceRecord> get visibleDevices {
    final mem = DeviceMemory.instance;
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _devices.values.where((d) {
      if (_favoritesOnly && !mem.isFavorite(d.id.str)) return false;
      if (_hideUnnamed && (d.localName == null || d.localName!.isEmpty)) {
        return false;
      }
      if (_manufacturerFilter != null) {
        final mfr = d.manufacturerId ?? -1;
        if (mfr != _manufacturerFilter) return false;
      }
      if (q.isEmpty) return true;
      final label = mem.labelFor(d.id.str)?.toLowerCase() ?? '';
      return d.name.toLowerCase().contains(q) ||
          d.id.str.toLowerCase().contains(q) ||
          label.contains(q);
    }).toList();

    int compareBase(DeviceRecord a, DeviceRecord b) {
      switch (_sortMode) {
        case SortMode.signalDesc:
          return b.currentRssi.compareTo(a.currentRssi);
        case SortMode.signalAsc:
          return a.currentRssi.compareTo(b.currentRssi);
        case SortMode.nameAsc:
          final an = (mem.labelFor(a.id.str) ?? a.name).toLowerCase();
          final bn = (mem.labelFor(b.id.str) ?? b.name).toLowerCase();
          return an.compareTo(bn);
        case SortMode.lastSeenDesc:
          return b.lastSeen.compareTo(a.lastSeen);
      }
    }

    int compareWithFavorites(DeviceRecord a, DeviceRecord b) {
      final aFav = mem.isFavorite(a.id.str);
      final bFav = mem.isFavorite(b.id.str);
      if (aFav != bFav) return aFav ? -1 : 1;
      return compareBase(a, b);
    }

    final intervalS = AppSettings.instance.reorderIntervalSeconds;
    final timeUp = DateTime.now().difference(_lastSortAt).inSeconds >= intervalS;
    final modeChanged = _lastSortedMode != _sortMode;

    if (intervalS == 0 || timeUp || modeChanged || _sortedIds.isEmpty) {
      filtered.sort(compareWithFavorites);
      _sortedIds = filtered.map((d) => d.id).toList();
      _lastSortAt = DateTime.now();
      _lastSortedMode = _sortMode;
      return filtered;
    }

    final rank = <DeviceIdentifier, int>{
      for (var i = 0; i < _sortedIds.length; i++) _sortedIds[i]: i,
    };
    filtered.sort((a, b) {
      final aFav = mem.isFavorite(a.id.str);
      final bFav = mem.isFavorite(b.id.str);
      if (aFav != bFav) return aFav ? -1 : 1;
      final ar = rank[a.id] ?? 1 << 30;
      final br = rank[b.id] ?? 1 << 30;
      if (ar != br) return ar.compareTo(br);
      return compareBase(a, b);
    });
    return filtered;
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setSortMode(SortMode m) {
    _sortMode = m;
    _invalidateSort();
    notifyListeners();
    _persistInt(_kSortMode, m.index);
  }

  void toggleHideUnnamed() {
    _hideUnnamed = !_hideUnnamed;
    notifyListeners();
    _persistBool(_kHideUnnamed, _hideUnnamed);
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    notifyListeners();
    _persistBool(_kFavoritesOnly, _favoritesOnly);
  }

  void clearAll() {
    _devices.clear();
    _statusMessage = null;
    notifyListeners();
  }

  void removeDevice(DeviceIdentifier id) {
    if (_devices.remove(id) != null) notifyListeners();
  }

  /// Remove devices that haven't advertised in [staleAfter]. Returns count removed.
  int removeStale({Duration staleAfter = const Duration(seconds: 30)}) {
    final cutoff = DateTime.now().subtract(staleAfter);
    final before = _devices.length;
    _devices.removeWhere((_, r) => r.lastSeen.isBefore(cutoff));
    final removed = before - _devices.length;
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Devices seen in the last [freshWindow] (default 5s).
  int activeCount({Duration freshWindow = const Duration(seconds: 5)}) {
    final cutoff = DateTime.now().subtract(freshWindow);
    return _devices.values.where((d) => d.lastSeen.isAfter(cutoff)).length;
  }

  void _handleResults(List<ScanResult> results) {
    var changed = false;
    final now = DateTime.now();
    for (final r in results) {
      final id = r.device.remoteId;
      final existing = _devices[id];
      if (existing == null) {
        final rec = DeviceRecord(
          id: id,
          name: _bestName(r),
          firstSeen: now,
        );
        rec.update(r);
        _devices[id] = rec;
      } else {
        existing.update(r);
      }
      NewDeviceMonitor.instance.observe(id.str, r.rssi);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  String _bestName(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    return '(unnamed)';
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    return scan && connect;
  }

  Future<void> startScan({Duration? timeout}) async {
    _statusMessage = null;
    notifyListeners();

    if (!await _ensurePermissions()) {
      _statusMessage = 'Bluetooth permissions denied. Open Settings to enable.';
      notifyListeners();
      return;
    }
    if (!await FlutterBluePlus.isSupported) {
      _statusMessage = 'Bluetooth is not supported on this device.';
      notifyListeners();
      return;
    }
    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      _statusMessage = 'Bluetooth is off. Turn it on and try again.';
      notifyListeners();
      return;
    }
    // Refresh the paired-device list at scan start in case the user paired
    // something new in system settings since the app launched.
    BondedDeviceRegistry.instance.refresh();
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );
    } catch (e) {
      _statusMessage = 'Scan failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  @override
  void dispose() {
    _isScanningSub?.cancel();
    _scanResultsSub?.cancel();
    _adapterStateSub?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }
}
