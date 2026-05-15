import 'package:flutter/foundation.dart';

/// Tracks the active recording window. We don't snapshot scan data ourselves —
/// the ScannerState already accumulates samples per device, so reviewing a
/// session just means filtering existing samples to the start/end window.
class SessionRecorder extends ChangeNotifier {
  SessionRecorder._();
  static final SessionRecorder instance = SessionRecorder._();

  DateTime? _start;
  DateTime? _end;

  bool get isRecording => _start != null && _end == null;
  bool get hasResult => _start != null && _end != null;
  DateTime? get start => _start;
  DateTime? get end => _end;

  Duration? get elapsed {
    if (_start == null) return null;
    return (_end ?? DateTime.now()).difference(_start!);
  }

  void startSession() {
    _start = DateTime.now();
    _end = null;
    notifyListeners();
  }

  void stopSession() {
    if (_start == null) return;
    _end = DateTime.now();
    notifyListeners();
  }

  void clear() {
    _start = null;
    _end = null;
    notifyListeners();
  }
}
