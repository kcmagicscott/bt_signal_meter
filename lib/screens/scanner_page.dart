import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../services/gatt_identifier.dart';
import '../services/new_device_monitor.dart';
import '../services/session_recorder.dart';
import '../utils/bt_helpers.dart';
import '../utils/device_guess.dart';
import '../widgets/info_chip.dart';
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
            _StatusBanner(
              message: state.statusMessage!,
              showSettingsAction:
                  state.statusMessage!.toLowerCase().contains('permission'),
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
                    child: _AnimatedDeviceList(
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
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

/// Stack-based scrolling list where each device tile is in an
/// [AnimatedPositioned]. When the sort order changes (or a new device
/// pushes one above another), tiles physically slide between their old
/// and new Y positions instead of cross-fading in place. Each tile's
/// height is measured on first layout so variable-content rows still
/// stack correctly.
class _AnimatedDeviceList extends StatefulWidget {
  const _AnimatedDeviceList({
    required this.devices,
    required this.onTap,
    required this.onLongPress,
  });

  final List<DeviceRecord> devices;
  final void Function(DeviceRecord) onTap;
  final void Function(DeviceRecord) onLongPress;

  @override
  State<_AnimatedDeviceList> createState() => _AnimatedDeviceListState();
}

class _AnimatedDeviceListState extends State<_AnimatedDeviceList> {
  static const Duration _slideDuration = Duration(milliseconds: 380);
  static const Curve _slideCurve = Curves.easeOutCubic;
  // Above this many devices the Stack-of-AnimatedPositioned approach gets
  // too heavy (every tile lives in the widget tree at once). Fall back to
  // a virtualized ListView — no slide animation, but it scrolls smoothly
  // through hundreds of items.
  static const int _virtualizeThreshold = 80;

  final Map<String, double> _heights = {};
  Set<String> _knownIds = const {};
  DensityMode _lastDensity = DensityMode.comfortable;

  double _estimatedHeightFor(DensityMode m) => switch (m) {
        DensityMode.comfortable => 124.0,
        DensityMode.compact => 64.0,
        DensityMode.dense => 36.0,
      };

  double _topFor(int index, double estimated) {
    var top = 0.0;
    for (var i = 0; i < index; i++) {
      top += _heights[widget.devices[i].id.str] ?? estimated;
    }
    return top;
  }

  double _totalHeight(double estimated) {
    var h = 0.0;
    for (final d in widget.devices) {
      h += _heights[d.id.str] ?? estimated;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _knownIds = widget.devices.map((d) => d.id.str).toSet();
    _lastDensity = AppSettings.instance.densityMode;
  }

  @override
  void didUpdateWidget(_AnimatedDeviceList old) {
    super.didUpdateWidget(old);
    final newIds = widget.devices.map((d) => d.id.str).toSet();
    if (newIds.length != _knownIds.length ||
        !newIds.containsAll(_knownIds)) {
      _heights.removeWhere((id, _) => !newIds.contains(id));
      _knownIds = newIds;
    }
    final density = AppSettings.instance.densityMode;
    if (density != _lastDensity) {
      // Tile sizes are about to change drastically — drop stale measurements.
      _heights.clear();
      _lastDensity = density;
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = AppSettings.instance.densityMode;
    final estimated = _estimatedHeightFor(density);

    if (widget.devices.length > _virtualizeThreshold) {
      // Virtualized path — no slide animation, but renders fine at 400+.
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.devices.length,
        itemBuilder: (_, i) {
          final d = widget.devices[i];
          return _DeviceListTile(
            key: ValueKey(d.id),
            record: d,
            onTap: () => widget.onTap(d),
            onLongPress: () => widget.onLongPress(d),
          );
        },
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: _totalHeight(estimated) + 8,
        child: Stack(
          children: [
            for (var i = 0; i < widget.devices.length; i++)
              AnimatedPositioned(
                key: ValueKey(widget.devices[i].id),
                duration: _slideDuration,
                curve: _slideCurve,
                top: _topFor(i, estimated),
                left: 0,
                right: 0,
                child: _MeasuredTile(
                  onHeight: (h) {
                    final id = widget.devices[i].id.str;
                    if ((_heights[id] ?? -1) != h) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _heights[id] = h);
                      });
                    }
                  },
                  child: _DeviceListTile(
                    record: widget.devices[i],
                    onTap: () => widget.onTap(widget.devices[i]),
                    onLongPress: () => widget.onLongPress(widget.devices[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reports its child's rendered height back to the parent via [onHeight]
/// after each layout pass. Used so the parent stack can position the next
/// tile correctly without hard-coding row heights.
class _MeasuredTile extends StatefulWidget {
  const _MeasuredTile({required this.child, required this.onHeight});
  final Widget child;
  final ValueChanged<double> onHeight;

  @override
  State<_MeasuredTile> createState() => _MeasuredTileState();
}

class _MeasuredTileState extends State<_MeasuredTile> {
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      final h = box?.size.height;
      if (h != null && h > 0) widget.onHeight(h);
    });
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    super.key,
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

    switch (settings.densityMode) {
      case DensityMode.dense:
        return _buildDense(
          context: context,
          theme: theme,
          rssi: rssi,
          displayName: displayName,
          isOffline: isOffline,
          isStale: isStale,
          isFavorite: isFavorite,
          mem: mem,
        );
      case DensityMode.compact:
        return _buildCompact(
          context: context,
          theme: theme,
          rssi: rssi,
          displayName: displayName,
          manufacturer: manufacturer,
          guess: guess,
          isOffline: isOffline,
          isStale: isStale,
          isFavorite: isFavorite,
          isNew: isNew,
          newAge: newAge,
          isPaired: isPaired,
          dist: dist,
          ageSeconds: ageSeconds,
          settings: settings,
          mem: mem,
        );
      case DensityMode.comfortable:
        break;
    }

    return Opacity(
      opacity: isStale ? 0.55 : 1.0,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: IconButton(
          tooltip: isFavorite ? 'Unstar' : 'Star',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => mem.toggleFavorite(record.id.str),
          icon: Icon(
            isFavorite ? Icons.star : Icons.star_border,
            color: isFavorite
                ? Colors.amber.shade700
                : theme.colorScheme.outline,
            size: 22,
          ),
        ),
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
            if (isNew) ...[
              const SizedBox(width: 6),
              _NewPulseBadge(age: newAge),
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
                if (isPaired)
                  const InfoChip(
                      text: 'Paired',
                      accent: true,
                      icon: Icons.bluetooth_connected),
                if (guess != null)
                  InfoChip(text: guess.label, icon: guess.icon)
                else if (manufacturer != null)
                  InfoChip(text: manufacturer, icon: Icons.devices_other),
                if (!isOffline)
                  InfoChip(
                    text:
                        '~${formatDistance(dist, imperial: settings.imperialDistance)}',
                  ),
                InfoChip(text: '${record.samples.length} samples'),
                if (isOffline)
                  InfoChip(text: 'offline ${ageSeconds}s')
                else if (isStale)
                  InfoChip(text: 'stale ${ageSeconds}s'),
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

  Widget _buildCompact({
    required BuildContext context,
    required ThemeData theme,
    required int rssi,
    required String displayName,
    required String? manufacturer,
    required DeviceGuess? guess,
    required bool isOffline,
    required bool isStale,
    required bool isFavorite,
    required bool isNew,
    required Duration? newAge,
    required bool isPaired,
    required double? dist,
    required int ageSeconds,
    required AppSettings settings,
    required DeviceMemory mem,
  }) {
    final qColor = qualityFromRssi(rssi).color;
    final subtitleParts = <String>[
      ?guess?.label,
      if (guess == null) ?manufacturer,
      if (!isOffline) '~${formatDistance(dist, imperial: settings.imperialDistance)}',
      if (isPaired) 'paired',
      if (isOffline) 'offline ${ageSeconds}s' else if (isStale) 'stale ${ageSeconds}s',
    ].where((s) => s.isNotEmpty).toList();
    return Opacity(
      opacity: isStale ? 0.55 : 1.0,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => mem.toggleFavorite(record.id.str),
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite
                      ? Colors.amber.shade700
                      : theme.colorScheme.outline,
                  size: 18,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 6),
                          _NewPulseBadge(age: newAge),
                        ],
                      ],
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SignalBars(rssi: rssi, isOffline: isOffline, height: 16),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                child: Text(
                  isOffline ? '—' : '$rssi',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isOffline ? Colors.grey.shade500 : qColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDense({
    required BuildContext context,
    required ThemeData theme,
    required int rssi,
    required String displayName,
    required bool isOffline,
    required bool isStale,
    required bool isFavorite,
    required DeviceMemory mem,
  }) {
    final qColor = qualityFromRssi(rssi).color;
    return Opacity(
      opacity: isStale ? 0.55 : 1.0,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => mem.toggleFavorite(record.id.str),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite
                        ? Colors.amber.shade700
                        : theme.colorScheme.outline.withValues(alpha: 0.6),
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isOffline ? Colors.grey.shade500 : null,
                  ),
                ),
              ),
              SignalBars(rssi: rssi, isOffline: isOffline, height: 12),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  isOffline ? '—' : '$rssi',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isOffline ? Colors.grey.shade500 : qColor,
                  ),
                ),
              ),
            ],
          ),
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
