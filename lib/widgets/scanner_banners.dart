import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/session_recorder.dart';
import '../screens/session_detail_page.dart';

/// Red banner that overlays the scanner while a recording session is active.
/// Shows elapsed time and a STOP button that finalises the session and pushes
/// the detail page.
class RecordingBanner extends StatelessWidget {
  const RecordingBanner({super.key, required this.elapsed});
  final Duration? elapsed;

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFB71C1C),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record,
                color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                elapsed == null
                    ? 'Recording session'
                    : 'Recording session · ${_fmt(elapsed!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                SessionRecorder.instance.stopSession();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SessionDetailPage(),
                  ),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
              child: const Text('STOP'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amber transient-status banner — shown when the scanner has something to
/// say that isn't urgent enough for a SnackBar but should stay visible
/// (permission denied, scan failure, etc.). When [showSettingsAction] is
/// true, a button opens the app's permission screen via permission_handler.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    required this.showSettingsAction,
  });

  final String message;
  final bool showSettingsAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
            if (showSettingsAction)
              TextButton(
                onPressed: () async {
                  await openAppSettings();
                },
                child: const Text('Open settings'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Persistent banner shown whenever the Bluetooth adapter is off. Includes
/// a "Turn on" button — on Android pre-12 this triggers the system prompt
/// directly; on Android 12+ flutter_blue_plus opens the BT settings panel.
class AdapterOffBanner extends StatelessWidget {
  const AdapterOffBanner({super.key, required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.bluetooth_disabled,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bluetooth is off. Turn it on to scan for devices.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: onTurnOn,
              child: const Text('Turn on'),
            ),
          ],
        ),
      ),
    );
  }
}
