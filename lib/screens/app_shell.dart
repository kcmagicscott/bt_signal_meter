import 'package:flutter/material.dart';

import '../services/session_recorder.dart';
import 'radar_page.dart';
import 'scanner_page.dart';
import 'session_detail_page.dart';
import 'settings_page.dart';

/// Top-level shell with a bottom navigation bar. Each tab keeps its own
/// state via an [IndexedStack] so switching tabs doesn't rebuild the page
/// (preserving scroll position and any in-flight work like an open
/// device-detail navigation stack).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _labels = ['Scanner', 'Radar', 'Session', 'Settings'];
  static const _icons = [
    Icons.search,
    Icons.radar,
    Icons.fiber_manual_record,
    Icons.tune,
  ];
  static const _selectedIcons = [
    Icons.bluetooth_searching,
    Icons.radar,
    Icons.fiber_manual_record_outlined,
    Icons.tune,
  ];

  @override
  void initState() {
    super.initState();
    SessionRecorder.instance.addListener(_onSessionChange);
  }

  void _onSessionChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionRecorder.instance.removeListener(_onSessionChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = SessionRecorder.instance.isRecording;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ScannerPage(),
          RadarPage(),
          _SessionTab(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(_icons[i]),
                  if (i == 2 && recording)
                    const Positioned(
                      right: -4,
                      top: -4,
                      child: _RecordingDot(),
                    ),
                ],
              ),
              selectedIcon: Icon(_selectedIcons[i]),
              label: _labels[i],
            ),
        ],
      ),
    );
  }
}

/// A small red dot overlay on the Session nav icon while recording is
/// active. Subtle but reassuring — confirms the recording is still running
/// no matter which tab you're on.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
      ),
    );
  }
}

/// The Session tab shows the recorder UI when a session has results
/// (either currently recording or just-finished). Otherwise an empty-state
/// that explains how to start one.
class _SessionTab extends StatefulWidget {
  const _SessionTab();

  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> {
  @override
  void initState() {
    super.initState();
    SessionRecorder.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionRecorder.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rec = SessionRecorder.instance;
    if (rec.start == null) {
      return _SessionEmpty(onStart: () => rec.startSession());
    }
    return const SessionDetailPage();
  }
}

class _SessionEmpty extends StatelessWidget {
  const _SessionEmpty({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fiber_manual_record,
                  size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'No session recorded yet',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Start a session to capture a slice of scan history you can '
                'review or export as CSV.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Start session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
