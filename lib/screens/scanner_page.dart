import 'package:animated_list_plus/animated_list_plus.dart';
import 'package:animated_list_plus/transitions.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../services/new_device_monitor.dart';
import '../services/session_recorder.dart';
import '../utils/bt_helpers.dart';
import '../utils/device_guess.dart';
import '../widgets/signal_gauge.dart';
import '../widgets/sparkline.dart';
import 'about_page.dart';
import 'device_detail_page.dart';
import 'identify_device_page.dart';
import 'radar_page.dart';
import 'session_detail_page.dart';
import 'settings_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  late final Listenable _appState = Listenable.merge([
    ScannerState.instance,
    DeviceMemory.instance,
    AppSettings.instance,
    NewDeviceMonitor.instance,
    BondedDeviceRegistry.instance,
    SessionRecorder.instance,
  ]);

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChange);
    _applyWakelock();
  }

  void _onStateChange() {
    if (!mounted) return;
    _applyWakelock();
    setState(() {});
  }

  Future<void> _applyWakelock() async {
    final want = AppSettings.instance.keepScreenOn &&
        ScannerState.instance.isScanning;
    try {
      if (want) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChange);
    WakelockPlus.disable().catchError((_) => false);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleScan() {
    final s = ScannerState.instance;
    if (s.isScanning) {
      s.stopScan();
    } else {
      s.startScan();
    }
  }

  Future<void> _confirmRemove(BuildContext context, DeviceRecord rec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from list?'),
        content: Text(
          'Remove "${rec.name}" from the scan results? '
          'It\'ll come back if it advertises again while scanning.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ScannerState.instance.removeDevice(rec.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ScannerState.instance;
    final devices = state.visibleDevices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BT Signal Meter'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        actions: [
          IconButton(
            tooltip: 'Radar view',
            icon: const Icon(Icons.radar),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RadarPage()),
            ),
          ),
          IconButton(
            tooltip: 'Clear list',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: state.allDevices.isEmpty ? null : state.clearAll,
          ),
          PopupMenuButton<SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: state.sortMode,
            onSelected: state.setSortMode,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: SortMode.signalDesc,
                child: Text('Strongest first'),
              ),
              PopupMenuItem(
                value: SortMode.signalAsc,
                child: Text('Weakest first'),
              ),
              PopupMenuItem(
                value: SortMode.nameAsc,
                child: Text('Name A→Z'),
              ),
              PopupMenuItem(
                value: SortMode.lastSeenDesc,
                child: Text('Most recent'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'identify':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const IdentifyDevicePage()),
                  );
                  break;
                case 'session':
                  final rec = SessionRecorder.instance;
                  if (rec.isRecording) {
                    rec.stopSession();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SessionDetailPage()),
                    );
                  } else {
                    rec.startSession();
                    if (!ScannerState.instance.isScanning) {
                      ScannerState.instance.startScan();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Recording session — stop from the menu'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  break;
                case 'about':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  );
                  break;
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  break;
                case 'stale':
                  final n = state.removeStale(
                    staleAfter: Duration(
                      seconds: AppSettings.instance.staleAfterSeconds * 6,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(n == 0
                          ? 'No stale devices to remove'
                          : 'Removed $n stale device${n == 1 ? '' : 's'}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) {
              final isRecording = SessionRecorder.instance.isRecording;
              return [
                const PopupMenuItem(
                  value: 'identify',
                  child: ListTile(
                    leading: Icon(Icons.center_focus_strong),
                    title: Text('What is this device?'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'session',
                  child: ListTile(
                    leading: Icon(isRecording
                        ? Icons.stop_circle_outlined
                        : Icons.fiber_manual_record),
                    title:
                        Text(isRecording ? 'Stop session' : 'Start session'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'stale',
                  child: ListTile(
                    leading: Icon(Icons.timer_off_outlined),
                    title: Text('Remove stale devices'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.tune),
                    title: Text('Settings'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'about',
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('About & Help'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!state.isAdapterOn)
            _AdapterOffBanner(
              onTurnOn: state.tryTurnOnAdapter,
            ),
          if (SessionRecorder.instance.isRecording)
            _RecordingBanner(elapsed: SessionRecorder.instance.elapsed),
          _SearchBar(
            controller: _searchCtrl,
            onChanged: state.setSearchQuery,
            hideUnnamed: state.hideUnnamed,
            onToggleUnnamed: state.toggleHideUnnamed,
            favoritesOnly: state.favoritesOnly,
            onToggleFavorites: state.toggleFavoritesOnly,
          ),
          _ManufacturerFilterStrip(
            present: state.manufacturersPresent,
            selected: state.manufacturerFilter,
            onSelect: state.setManufacturerFilter,
            countFor: (id) => state.allDevices.values
                .where((d) => (d.manufacturerId ?? -1) == id)
                .length,
          ),
          if (state.statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.statusMessage!)),
                ],
              ),
            ),
          _SummaryBar(
            total: state.allDevices.length,
            shown: devices.length,
            active: state.activeCount(),
            scanning: state.isScanning,
          ),
          Expanded(
            child: devices.isEmpty
                ? _EmptyState(
                    scanning: state.isScanning,
                    favoritesOnly: state.favoritesOnly,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      state.removeStale();
                    },
                    child: ImplicitlyAnimatedList<DeviceRecord>(
                      items: devices,
                      areItemsTheSame: (a, b) => a.id == b.id,
                      insertDuration: const Duration(milliseconds: 300),
                      removeDuration: const Duration(milliseconds: 200),
                      updateDuration: const Duration(milliseconds: 400),
                      itemBuilder: (ctx, animation, item, i) {
                        return SizeFadeTransition(
                          sizeFraction: 0.7,
                          curve: Curves.easeInOut,
                          animation: animation,
                          child: _DeviceListTile(
                            record: item,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DeviceDetailPage(deviceId: item.id),
                              ),
                            ),
                            onLongPress: () => _confirmRemove(context, item),
                          ),
                        );
                      },
                      updateItemBuilder: (ctx, animation, item) {
                        return FadeTransition(
                          opacity: animation,
                          child: _DeviceListTile(
                            record: item,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DeviceDetailPage(deviceId: item.id),
                              ),
                            ),
                            onLongPress: () => _confirmRemove(context, item),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(state.isScanning ? Icons.stop : Icons.search),
        label: Text(state.isScanning ? 'Stop' : 'Scan'),
        backgroundColor: state.isScanning
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({required this.elapsed});
  final Duration? elapsed;

  String _fmt(Duration d) {
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

class _ManufacturerFilterStrip extends StatelessWidget {
  const _ManufacturerFilterStrip({
    required this.present,
    required this.selected,
    required this.onSelect,
    required this.countFor,
  });

  final Set<int> present;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final int Function(int) countFor;

  @override
  Widget build(BuildContext context) {
    if (present.length < 2) return const SizedBox.shrink();

    // Sort: known manufacturers first (by descending count), unknown bucket last.
    final ids = present.toList()
      ..sort((a, b) {
        if (a == -1) return 1;
        if (b == -1) return -1;
        return countFor(b).compareTo(countFor(a));
      });

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: ids.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return FilterChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            );
          }
          final id = ids[i - 1];
          final name =
              id == -1 ? 'Unknown' : (manufacturerNameFor(id) ?? '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}');
          final count = countFor(id);
          return FilterChip(
            label: Text('$name · $count'),
            selected: selected == id,
            onSelected: (_) => onSelect(selected == id ? null : id),
          );
        },
      ),
    );
  }
}

class _AdapterOffBanner extends StatelessWidget {
  const _AdapterOffBanner({required this.onTurnOn});
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.hideUnnamed,
    required this.onToggleUnnamed,
    required this.favoritesOnly,
    required this.onToggleFavorites,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hideUnnamed;
  final VoidCallback onToggleUnnamed;
  final bool favoritesOnly;
  final VoidCallback onToggleFavorites;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or address',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: favoritesOnly
                ? 'Show all devices'
                : 'Show favorites only',
            onPressed: onToggleFavorites,
            icon: Icon(
              favoritesOnly ? Icons.star : Icons.star_border,
            ),
            color: favoritesOnly ? Colors.amber.shade700 : null,
          ),
          IconButton(
            tooltip: hideUnnamed
                ? 'Show unnamed devices'
                : 'Hide unnamed devices',
            onPressed: onToggleUnnamed,
            icon: Icon(
              hideUnnamed ? Icons.label : Icons.label_off_outlined,
            ),
            color: hideUnnamed ? Theme.of(context).colorScheme.primary : null,
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.total,
    required this.shown,
    required this.active,
    required this.scanning,
  });

  final int total;
  final int shown;
  final int active;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          if (scanning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.bluetooth_disabled,
                size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            scanning ? 'Scanning…' : 'Idle',
            style: theme.textTheme.bodySmall,
          ),
          if (scanning) ...[
            const SizedBox(width: 12),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active > 0
                    ? Colors.green
                    : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$active active',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Spacer(),
          Text(
            shown == total ? '$total devices' : '$shown of $total devices',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.record,
    required this.onTap,
    required this.onLongPress,
  });

  final DeviceRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final manufacturer = record.manufacturerId == null
        ? null
        : manufacturerNameFor(record.manufacturerId!);
    final rssi = record.smoothedRssi(settings.smoothingWindow);
    final mem = DeviceMemory.instance;
    final customLabel = mem.labelFor(record.id.str);
    final isFavorite = mem.isFavorite(record.id.str);
    final newAge = NewDeviceMonitor.instance.sinceFirstSeen(record.id.str);
    final isNew = NewDeviceMonitor.instance.isNew(record.id.str);
    final bondedName = BondedDeviceRegistry.instance.bondedNameFor(record.id.str);
    final isPaired = bondedName != null;
    final hasName = record.localName != null && record.localName!.isNotEmpty;
    final displayName =
        customLabel ?? bondedName ?? (hasName ? record.name : '(unnamed)');
    final ageSeconds = DateTime.now().difference(record.lastSeen).inSeconds;
    final isStale = ageSeconds >= settings.staleAfterSeconds;
    final isOffline = record.isOfflineFor(settings.offlineThreshold);
    final dist = isOffline
        ? null
        : estimateDistanceMeters(
            rssi: rssi,
            measuredPowerAt1m:
                mem.calibratedTxPowerFor(record.id.str) ?? record.txPower ?? -59,
          );
    final guess = guessDeviceType(record);
    final theme = Theme.of(context);

    return Opacity(
      opacity: isStale ? 0.55 : 1.0,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: isFavorite
            ? Icon(Icons.star, color: Colors.amber.shade700, size: 20)
            : (isNew
                ? _NewPulseBadge(age: newAge)
                : null),
        title: Row(
          children: [
            Flexible(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      (customLabel != null || hasName) ? FontWeight.w500 : FontWeight.w400,
                  color: (customLabel != null || hasName)
                      ? null
                      : theme.colorScheme.outline,
                  fontStyle: customLabel != null ? FontStyle.italic : null,
                ),
              ),
            ),
            if (customLabel != null && hasName) ...[
              const SizedBox(width: 6),
              Text(
                '· ${record.name}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.id.str,
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isPaired) const _Chip(text: 'Paired', accent: true),
                if (guess != null)
                  _Chip(text: guess.label)
                else if (manufacturer != null)
                  _Chip(text: manufacturer),
                if (!isOffline) _Chip(text: '~${formatDistance(dist)}'),
                _Chip(text: '${record.samples.length} samples'),
                if (isOffline)
                  _Chip(text: 'offline ${ageSeconds}s')
                else if (isStale)
                  _Chip(text: 'stale ${ageSeconds}s'),
              ],
            ),
            const SizedBox(height: 6),
            Sparkline(
              samples: record.samples,
              color: qualityFromRssi(rssi).color,
              maxWindowSeconds: 300,
              offlineAfter: settings.offlineThreshold,
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SignalBars(rssi: rssi, isOffline: isOffline),
            const SizedBox(height: 4),
            if (isOffline)
              Text(
                '—',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (record.trend() != 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        record.trend() > 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        size: 14,
                        color: record.trend() > 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  Text(
                    '$rssi dBm',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: qualityFromRssi(rssi).color,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NewPulseBadge extends StatefulWidget {
  const _NewPulseBadge({this.age});
  final Duration? age;

  @override
  State<_NewPulseBadge> createState() => _NewPulseBadgeState();
}

class _NewPulseBadgeState extends State<_NewPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _ageLabel(Duration? d) {
    if (d == null) return 'NEW';
    if (d.inMinutes < 1) return 'NEW';
    return 'NEW · ${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final showPulse = widget.age == null || widget.age!.inSeconds < 90;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.redAccent.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _ageLabel(widget.age),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
    if (!showPulse) return badge;
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.08).animate(_ctrl),
      child: badge,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.accent = false});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: accent ? theme.colorScheme.onPrimaryContainer : null,
          fontWeight: accent ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning, this.favoritesOnly = false});
  final bool scanning;
  final bool favoritesOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData icon;
    final String title;
    final String body;
    if (favoritesOnly) {
      icon = Icons.star_border;
      title = 'No favorites in range';
      body =
          'Tap the star icon again to show all devices, '
          'or open a device and star it to add it here.';
    } else if (scanning) {
      icon = Icons.bluetooth_searching;
      title = 'Listening…';
      body = 'Nearby Bluetooth devices will appear here as they advertise.';
    } else {
      icon = Icons.bluetooth_outlined;
      title = 'Tap Scan to start';
      body =
          'This app finds Bluetooth Low Energy devices around you '
          'and tracks their signal strength.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
