import 'package:flutter/foundation.dart';

/// One waypoint within a recording session — a user-stamped "I'm here
/// now" moment. The label is free-text ("entryway", "corner office",
/// "row 6 seat 12"); the timestamp is captured automatically.
class Waypoint {
  const Waypoint({required this.time, required this.label});
  final DateTime time;
  final String label;
}

/// Tracks the active recording window. We don't snapshot scan data ourselves —
/// the ScannerState already accumulates samples per device, so reviewing a
/// session just means filtering existing samples to the start/end window.
///
/// Optionally the user can drop [Waypoint]s while recording so the
/// resulting session can be sliced into "what did we see at each spot".
class SessionRecorder extends ChangeNotifier {
  SessionRecorder._();
  static final SessionRecorder instance = SessionRecorder._();

  DateTime? _start;
  DateTime? _end;
  final List<Waypoint> _waypoints = [];

  bool get isRecording => _start != null && _end == null;
  bool get hasResult => _start != null && _end != null;
  DateTime? get start => _start;
  DateTime? get end => _end;
  List<Waypoint> get waypoints => List.unmodifiable(_waypoints);

  Duration? get elapsed {
    if (_start == null) return null;
    return (_end ?? DateTime.now()).difference(_start!);
  }

  void startSession() {
    _start = DateTime.now();
    _end = null;
    _waypoints.clear();
    notifyListeners();
  }

  void stopSession() {
    if (_start == null) return;
    _end = DateTime.now();
    notifyListeners();
  }

  /// Drop a waypoint at the current moment. No-op if no session is active
  /// (waypoints outside a recording window have nothing to anchor to).
  /// Returns the new waypoint, or null if rejected.
  Waypoint? markWaypoint(String label) {
    if (!isRecording) return null;
    final wp = Waypoint(time: DateTime.now(), label: label.trim());
    _waypoints.add(wp);
    notifyListeners();
    return wp;
  }

  void removeWaypoint(int index) {
    if (index < 0 || index >= _waypoints.length) return;
    _waypoints.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _start = null;
    _end = null;
    _waypoints.clear();
    notifyListeners();
  }
}
