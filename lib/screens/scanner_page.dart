import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../services/gatt_identifier.dart';
import '../services/new_device_monitor.dart';
import '../services/session_recorder.dart';
import '../widgets/animated_device_list.dart';
import '../widgets/scanner_banners.dart';
import '../widgets/scanner_chrome.dart';
import 'about_page.dart';
import 'device_detail_page.dart';
import 'identify_device_page.dart';
import 'session_detail_page.dart';

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
    _maybeShowMilestone();
    setState(() {});
  }

  void _maybeShowMilestone() {
    final m = NewDeviceMonitor.instance.popPendingMilestone();
    if (m == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(_milestoneEmoji(m), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(_milestoneText(m))),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _milestoneEmoji(int m) => switch (m) {
        1 => '👋',
        10 => '🎯',
        50 => '🌟',
        100 => '🎉',
        250 => '🚀',
        500 => '🏆',
        1000 => '💎',
        _ => '✨',
      };

  static String _milestoneText(int m) => switch (m) {
        1 => 'First device discovered!',
        _ => '$m distinct devices seen — nice scanning.',
      };

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

  Future<void> _markWaypoint(BuildContext context) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final label = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add waypoint'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. "entryway", "row 6"',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Mark'),
            ),
          ],
        ),
      );
      if (label == null || label.trim().isEmpty) return;
      final wp = SessionRecorder.instance.markWaypoint(label);
      if (wp != null && context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Waypoint dropped: ${wp.label}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  void _toggleScan() {
    final s = ScannerState.instance;
    if (s.isScanning) {
      s.stopScan();
    } else {
      s.startScan();
    }
  }

  Future<void> _showDeviceActions(BuildContext context, DeviceRecord rec) async {
    final mem = DeviceMemory.instance;
    final isFav = mem.isFavorite(rec.id.str);
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final displayName = mem.labelFor(rec.id.str) ?? rec.name;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  displayName,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav ? Colors.amber.shade700 : null,
                ),
                title: Text(isFav ? 'Unstar' : 'Star'),
                onTap: () => Navigator.of(ctx).pop('toggleFav'),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open details'),
                onTap: () => Navigator.of(ctx).pop('open'),
              ),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Identify via GATT'),
                subtitle: const Text('Read manufacturer + model from device'),
                onTap: () => Navigator.of(ctx).pop('identify'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                title: const Text(
                  'Remove from list',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'toggleFav':
        await mem.toggleFavorite(rec.id.str);
        break;
      case 'open':
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceDetailPage(deviceId: rec.id),
            ),
          );
        }
        break;
      case 'identify':
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Connecting and reading identity…')),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );
        final result = await GattIdentifier.instance.lookup(rec.id);
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result == null || result.isEmpty
                  ? 'Could not read identity — device may not expose '
                      'the standard Device Information service.'
                  : 'Identified: ${result.headline}',
            ),
          ),
        );
        break;
      case 'remove':
        ScannerState.instance.removeDevice(rec.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Removed ${rec.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                // The device will reappear on its next advertisement. No
                // explicit undo needed — show feedback only.
              },
            ),
          ),
        );
        break;
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
            tooltip: 'Clear list',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: state.allDevices.isEmpty ? null : state.clearAll,
          ),
          IconButton(
            tooltip: switch (AppSettings.instance.densityMode) {
              DensityMode.comfortable => 'Density: comfortable',
              DensityMode.compact => 'Density: compact',
              DensityMode.dense => 'Density: dense',
            },
            icon: Icon(switch (AppSettings.instance.densityMode) {
              DensityMode.comfortable => Icons.density_large,
              DensityMode.compact => Icons.density_medium,
              DensityMode.dense => Icons.density_small,
            }),
            onPressed: AppSettings.instance.cycleDensityMode,
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
            AdapterOffBanner(
              onTurnOn: state.tryTurnOnAdapter,
            ),
          if (SessionRecorder.instance.isRecording)
            RecordingBanner(
              elapsed: SessionRecorder.instance.elapsed,
              waypointCount: SessionRecorder.instance.waypoints.length,
              onMarkWaypoint: () => _markWaypoint(context),
            ),
          ScannerSearchBar(
            controller: _searchCtrl,
            onChanged: state.setSearchQuery,
            hideUnnamed: state.hideUnnamed,
            onToggleUnnamed: state.toggleHideUnnamed,
            favoritesOnly: state.favoritesOnly,
            onToggleFavorites: state.toggleFavoritesOnly,
          ),
          ManufacturerFilterStrip(
            present: state.manufacturersPresent,
            selected: state.manufacturerFilter,
            onSelect: state.setManufacturerFilter,
            countFor: (id) => state.allDevices.values
                .where((d) => (d.manufacturerId ?? -1) == id)
                .length,
          ),
          if (state.statusMessage != null)
            StatusBanner(
              message: state.statusMessage!,
              showSettingsAction:
                  state.statusMessage!.toLowerCase().contains('permission'),
            ),
          SummaryBar(
            total: state.allDevices.length,
            shown: devices.length,
            active: state.activeCount(),
            scanning: state.isScanning,
          ),
          Expanded(
            child: devices.isEmpty
                ? ScannerEmptyState(
                    scanning: state.isScanning,
                    favoritesOnly: state.favoritesOnly,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      state.removeStale();
                    },
                    child: AnimatedDeviceList(
                      devices: devices,
                      onTap: (item) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DeviceDetailPage(deviceId: item.id),
                        ),
                      ),
                      onLongPress: (item) =>
                          _showDeviceActions(context, item),
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
