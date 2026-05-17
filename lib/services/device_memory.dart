import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/direction_fix.dart';

class DeviceNote {
  DeviceNote({
    this.label,
    this.favorite = false,
    this.calibratedTxPower,
    this.direction,
    this.baselineRssi,
    this.baselineSetAt,
  });

  String? label;
  bool favorite;

  /// User-measured RSSI value at exactly 1m for this device; overrides the
  /// generic -59 dBm assumption when present.
  int? calibratedTxPower;

  /// Last sweep-to-find result for this device.
  DirectionFix? direction;

  /// Reference RSSI captured at a known good moment. Lets the app warn
  /// the user when the current reading drifts unexpectedly from this
  /// baseline (movement, interference, low battery in the peripheral).
  int? baselineRssi;

  /// When [baselineRssi] was captured. Lets the UI surface "set 5 min ago"
  /// vs "set 3 days ago" so the user can judge whether the baseline is
  /// still meaningful.
  DateTime? baselineSetAt;

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        'favorite': favorite,
        if (calibratedTxPower != null) 'tx': calibratedTxPower,
        if (direction != null) 'dir': direction!.toJson(),
        if (baselineRssi != null) 'bl': baselineRssi,
        if (baselineSetAt != null) 'blt': baselineSetAt!.toIso8601String(),
      };

  factory DeviceNote.fromJson(Map<String, dynamic> j) => DeviceNote(
        label: j['label'] as String?,
        favorite: j['favorite'] as bool? ?? false,
        calibratedTxPower: j['tx'] as int?,
        direction: j['dir'] == null
            ? null
            : DirectionFix.fromJson(j['dir'] as Map<String, dynamic>),
        baselineRssi: j['bl'] as int?,
        baselineSetAt: j['blt'] == null
            ? null
            : DateTime.tryParse(j['blt'] as String),
      );

  bool get isEmpty =>
      (label == null || label!.isEmpty) &&
      !favorite &&
      calibratedTxPower == null &&
      direction == null &&
      baselineRssi == null;
}

/// Persists user-added labels and favorite flags keyed by Bluetooth remote ID.
///
/// Caveat: Some devices (Apple, modern Android) rotate their MAC address every
/// 15 min for privacy, so saved notes won't follow them. Works fine for beacons,
/// IoT devices, headphones, smart watches.
class DeviceMemory extends ChangeNotifier {
  DeviceMemory._();

  static final DeviceMemory instance = DeviceMemory._();

  static const _prefsKey = 'device_notes_v1';
  final Map<String, DeviceNote> _notes = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _notes[entry.key] =
              DeviceNote.fromJson(entry.value as Map<String, dynamic>);
        }
      } catch (_) {
        // Corrupt prefs — drop them silently.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode({
      for (final e in _notes.entries) e.key: e.value.toJson(),
    });
    await prefs.setString(_prefsKey, encoded);
  }

  DeviceNote noteFor(String id) => _notes[id] ?? DeviceNote();

  String? labelFor(String id) => _notes[id]?.label;

  bool isFavorite(String id) => _notes[id]?.favorite ?? false;

  int? calibratedTxPowerFor(String id) => _notes[id]?.calibratedTxPower;

  DirectionFix? directionFor(String id) => _notes[id]?.direction;

  int? baselineRssiFor(String id) => _notes[id]?.baselineRssi;
  DateTime? baselineSetAtFor(String id) => _notes[id]?.baselineSetAt;

  Future<void> setBaseline(String id, int? rssi) async {
    final existing = _notes[id] ?? DeviceNote();
    existing.baselineRssi = rssi;
    existing.baselineSetAt = rssi == null ? null : DateTime.now();
    if (existing.isEmpty) {
      _notes.remove(id);
    } else {
      _notes[id] = existing;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setDirection(String id, DirectionFix? fix) async {
    final existing = _notes[id] ?? DeviceNote();
    existing.direction = fix;
    if (existing.isEmpty) {
      _notes.remove(id);
    } else {
      _notes[id] = existing;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setCalibratedTxPower(String id, int? value) async {
    final existing = _notes[id] ?? DeviceNote();
    existing.calibratedTxPower = value;
    if (existing.isEmpty) {
      _notes.remove(id);
    } else {
      _notes[id] = existing;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setLabel(String id, String? label) async {
    final trimmed = label?.trim();
    final existing = _notes[id] ?? DeviceNote();
    existing.label = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (existing.isEmpty) {
      _notes.remove(id);
    } else {
      _notes[id] = existing;
    }
    notifyListeners();
    await _save();
  }

  Future<void> toggleFavorite(String id) async {
    final existing = _notes[id] ?? DeviceNote();
    existing.favorite = !existing.favorite;
    if (existing.isEmpty) {
      _notes.remove(id);
    } else {
      _notes[id] = existing;
    }
    notifyListeners();
    await _save();
  }

  /// All known IDs (devices that have a label and/or favorite flag).
  Iterable<String> get knownIds => _notes.keys;
}
