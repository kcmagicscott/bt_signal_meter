import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/background_scan.dart';
import '../services/new_device_monitor.dart';
import '../services/watch_mode.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onChange);
    WatchMode.instance.addListener(_onChange);
    BackgroundScan.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onChange);
    WatchMode.instance.removeListener(_onChange);
    BackgroundScan.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(text: 'Display'),
          ListTile(
            title: const Text('Chart window'),
            subtitle: Text('${s.chartWindowSeconds} seconds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInt(
              context,
              title: 'Chart window (seconds)',
              current: s.chartWindowSeconds,
              choices: const [15, 30, 60, 120, 300, 600],
              suffix: 's',
              onPicked: s.setChartWindowSeconds,
            ),
          ),
          ListTile(
            title: const Text('Mark device stale after'),
            subtitle: Text(
              s.staleAfterSeconds == 1
                  ? '1 second of silence'
                  : '${s.staleAfterSeconds} seconds of silence',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInt(
              context,
              title: 'Stale threshold (seconds)',
              current: s.staleAfterSeconds,
              choices: const [2, 3, 5, 10, 15, 30],
              suffix: 's',
              onPicked: s.setStaleAfterSeconds,
            ),
          ),
          SwitchListTile(
            title: const Text('Keep screen on while scanning'),
            subtitle: const Text(
              'Useful for find-it mode; uses more battery.',
            ),
            value: s.keepScreenOn,
            onChanged: s.setKeepScreenOn,
          ),
          SwitchListTile(
            title: const Text('Distance in feet'),
            subtitle: Text(
              s.imperialDistance
                  ? 'Showing distances in feet/inches'
                  : 'Showing distances in metres/centimetres',
            ),
            value: s.imperialDistance,
            onChanged: s.setImperialDistance,
          ),
          ListTile(
            title: const Text('Reorder interval'),
            subtitle: Text(
              s.reorderIntervalSeconds == 0
                  ? 'Reorder on every scan result (jumpy)'
                  : 'Reorder at most every ${s.reorderIntervalSeconds}s',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInt(
              context,
              title: 'Reorder interval',
              current: s.reorderIntervalSeconds,
              choices: const [0, 1, 3, 5, 10, 30],
              suffix: 's',
              labelFor: (v) => v == 0 ? 'Live (jumpy)' : '$v seconds',
              onPicked: s.setReorderIntervalSeconds,
            ),
          ),
          const Divider(),
          _SectionHeader(text: 'Signal smoothing'),
          ListTile(
            title: const Text('Smoothing window'),
            subtitle: Text(
              s.smoothingWindow == 1
                  ? 'Off — show raw signal value'
                  : 'Average of last ${s.smoothingWindow} samples',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInt(
              context,
              title: 'Smoothing window',
              current: s.smoothingWindow,
              choices: const [1, 3, 5, 8, 12, 20],
              suffix: '',
              labelFor: (v) => v == 1 ? 'Off' : '$v samples',
              onPicked: s.setSmoothingWindow,
            ),
          ),
          const Divider(),
          _SectionHeader(text: 'Watch mode'),
          SwitchListTile(
            title: const Text('Notify on favorite range changes'),
            subtitle: const Text(
              'Posts a system notification when any starred device enters or leaves range. '
              'Works while the app is open or recently backgrounded.',
            ),
            value: WatchMode.instance.enabled,
            onChanged: (v) => WatchMode.instance.setEnabled(v),
          ),
          SwitchListTile(
            title: const Text('Pinned strongest-device notification'),
            subtitle: const Text(
              'Keeps an ongoing notification in the shade with the current '
              'strongest device while the app is running — useful for site '
              'surveys without keeping the screen on.',
            ),
            value: BackgroundScan.instance.enabled,
            onChanged: (v) => BackgroundScan.instance.setEnabled(v),
          ),
          const Divider(),
          _SectionHeader(text: 'New-device monitoring'),
          ListTile(
            title: const Text('Sensitivity'),
            subtitle: Text(_sensitivityLabel(s.monitoringSensitivity)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInt(
              context,
              title: 'Monitoring sensitivity',
              current: s.monitoringSensitivity,
              choices: const [1, 2, 3, 4, 5],
              suffix: '',
              labelFor: _sensitivityLabel,
              onPicked: s.setMonitoringSensitivity,
            ),
          ),
          ListTile(
            title: const Text('Forget all known devices'),
            subtitle: Text(
              '${NewDeviceMonitor.instance.knownCount} device IDs remembered',
            ),
            leading: const Icon(Icons.delete_outline),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Forget all known devices?'),
                  content: const Text(
                    'Every Bluetooth ID this app has ever seen will be cleared. '
                    'New devices will be re-flagged the next time they appear.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Forget'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await NewDeviceMonitor.instance.forgetAll();
              }
            },
          ),
          const Divider(),
          _SectionHeader(text: 'About'),
          ListTile(
            title: const Text('Reset all settings'),
            leading: const Icon(Icons.restore),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset settings?'),
                  content: const Text(
                    'This resets chart window, smoothing, and stale threshold '
                    'to defaults. Device labels and favorites are not affected.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await s.setChartWindowSeconds(60);
                await s.setStaleAfterSeconds(5);
                await s.setSmoothingWindow(5);
                await s.setKeepScreenOn(false);
              }
            },
          ),
        ],
      ),
    );
  }

  String _sensitivityLabel(int v) {
    final rssi = NewDeviceMonitor.rssiThreshold(v);
    final size = switch (v) {
      1 => 'arm\'s length',
      2 => 'same room',
      3 => 'across a room',
      4 => 'next room',
      _ => 'whole floor',
    };
    return 'Level $v — about $size  (≥ $rssi dBm)';
  }

  Future<void> _pickInt(
    BuildContext context, {
    required String title,
    required int current,
    required List<int> choices,
    required ValueChanged<int> onPicked,
    String suffix = '',
    String Function(int)? labelFor,
  }) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: choices.map((c) {
          final label = labelFor != null ? labelFor(c) : '$c$suffix';
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(c),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                if (c == current) const Icon(Icons.check),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (picked != null) onPicked(picked);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
