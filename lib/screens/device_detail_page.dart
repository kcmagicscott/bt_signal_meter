import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_record.dart';
import '../models/direction_fix.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../utils/beacon_parsers.dart';
import '../utils/bt_helpers.dart';
import '../utils/device_guess.dart';
import '../widgets/compass_dial.dart';
import '../widgets/rssi_chart.dart';
import '../widgets/signal_gauge.dart';
import '../widgets/sparkline.dart';
import '../widgets/sweep_sheet.dart';
import 'gatt_explorer_page.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final DeviceIdentifier deviceId;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  Timer? _hapticTimer;
  bool _findItMode = false;
  bool _audioOn = false;
  late final Listenable _appState = Listenable.merge([
    ScannerState.instance,
    DeviceMemory.instance,
    AppSettings.instance,
    BondedDeviceRegistry.instance,
  ]);

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    if (_findItMode) _scheduleHapticPulse();
    setState(() {});
  }

  @override
  void dispose() {
    _appState.removeListener(_onChange);
    _hapticTimer?.cancel();
    if (_findItMode) {
      WakelockPlus.disable().catchError((_) => false);
    }
    super.dispose();
  }

  /// Pulse rate scales with smoothed signal strength: stronger = faster pulses.
  /// When the device is offline, fall back to a slow ping so the user knows
  /// the app hasn't frozen — but no haptic, just a long idle.
  void _scheduleHapticPulse() {
    _hapticTimer?.cancel();
    final rec = ScannerState.instance.deviceFor(widget.deviceId);
    if (rec == null) return;
    final settings = AppSettings.instance;
    if (rec.isOfflineFor(settings.offlineThreshold)) {
      _hapticTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _findItMode) _scheduleHapticPulse();
      });
      return;
    }
    final r = rec.smoothedRssi(settings.smoothingWindow);
    // Map -50dBm..-100dBm to 120ms..1500ms; clamp outside.
    final t = ((-50 - r) / 50).clamp(0.0, 1.0);
    final interval = (120 + 1380 * t).round();
    _hapticTimer = Timer(Duration(milliseconds: interval), () {
      if (!mounted || !_findItMode) return;
      if (r >= -55) {
        HapticFeedback.heavyImpact();
      } else if (r >= -75) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
      if (_audioOn) {
        SystemSound.play(SystemSoundType.click);
      }
      _scheduleHapticPulse();
    });
  }

  Future<void> _toggleFindIt() async {
    setState(() => _findItMode = !_findItMode);
    if (_findItMode) {
      _scheduleHapticPulse();
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    } else {
      _hapticTimer?.cancel();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<void> _calibrateAt1m(DeviceRecord rec) async {
    final smoothed = rec.smoothedRssi(AppSettings.instance.smoothingWindow);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calibrate at 1 metre?'),
        content: Text(
          'Hold the device exactly 1 m away, then confirm. The current '
          'smoothed signal ($smoothed dBm) will be saved as this device\'s '
          'reference value, improving distance estimates.\n\n'
          'You can clear this anytime from the menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save as 1 m'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DeviceMemory.instance.setCalibratedTxPower(rec.id.str, smoothed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calibrated at $smoothed dBm = 1 m')),
      );
    }
  }

  Future<void> _clearCalibration(DeviceRecord rec) async {
    await DeviceMemory.instance.setCalibratedTxPower(rec.id.str, null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calibration cleared')),
    );
  }

  IconData _confidenceIcon(Confidence c) {
    switch (c) {
      case Confidence.certain:
        return Icons.check_circle_outline;
      case Confidence.likely:
        return Icons.lightbulb_outline;
      case Confidence.possible:
        return Icons.help_outline;
    }
  }

  String _confidencePrefix(Confidence c) {
    switch (c) {
      case Confidence.certain:
        return 'Identified as';
      case Confidence.likely:
        return 'Likely:';
      case Confidence.possible:
        return 'Possibly:';
    }
  }

  Future<void> _pair(DeviceRecord rec) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bt = BluetoothDevice.fromId(rec.id.str);
      await bt.createBond();
      await BondedDeviceRegistry.instance.refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pairing requested — confirm on the system prompt'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t pair: $e')),
      );
    }
  }

  Future<void> _unpair(DeviceRecord rec) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
          'The system will forget this device. You can re-pair from this screen '
          'or from Android Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final bt = BluetoothDevice.fromId(rec.id.str);
      await bt.removeBond();
      await BondedDeviceRegistry.instance.refresh();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Unpaired')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t unpair: $e')),
      );
    }
  }

  Future<void> _editLabel(DeviceRecord rec) async {
    final controller = TextEditingController(
      text: DeviceMemory.instance.labelFor(rec.id.str) ?? '',
    );
    try {
      final result = await showDialog<String?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Label this device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'e.g. Office speakers',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              Text(
                'Stored locally. Some phones rotate Bluetooth addresses for '
                'privacy, so labels may not follow the same device long-term.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            if ((DeviceMemory.instance.labelFor(rec.id.str) ?? '').isNotEmpty)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(''),
                child: const Text('Remove'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      await DeviceMemory.instance.setLabel(rec.id.str, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t save label: $e')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _exportCsv(DeviceRecord rec) async {
    try {
      final dir = await getTemporaryDirectory();
      final safeName = (DeviceMemory.instance.labelFor(rec.id.str) ?? rec.name)
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/bt_signal_${safeName}_$stamp.csv');
      await file.writeAsString(rec.toCsv());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'BT Signal Meter export: $safeName',
          text:
              'RSSI samples for ${rec.name} (${rec.id.str}) — ${rec.samples.length} points',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = ScannerState.instance.deviceFor(widget.deviceId);
    if (rec == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device')),
        body: const Center(child: Text('Device no longer in scan results.')),
      );
    }

    final theme = Theme.of(context);
    final mem = DeviceMemory.instance;
    final settings = AppSettings.instance;
    final label = mem.labelFor(rec.id.str);
    final bondedName = BondedDeviceRegistry.instance.bondedNameFor(rec.id.str);
    final isPaired = bondedName != null;
    final isFavorite = mem.isFavorite(rec.id.str);
    final calibration = mem.calibratedTxPowerFor(rec.id.str);
    final smoothedRssi = rec.smoothedRssi(settings.smoothingWindow);
    final isOffline = rec.isOfflineFor(settings.offlineThreshold);
    final dist = isOffline
        ? null
        : estimateDistanceMeters(
            rssi: smoothedRssi,
            measuredPowerAt1m: calibration ?? rec.txPower ?? -59,
          );
    final age = DateTime.now().difference(rec.lastSeen);
    final ibeacon = rec.iBeacon;
    final eddystone = rec.eddystone;
    final guess = guessDeviceType(rec);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          label ?? bondedName ?? rec.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Unfavorite' : 'Favorite',
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? Colors.amber.shade700 : null,
            ),
            onPressed: () =>
                DeviceMemory.instance.toggleFavorite(rec.id.str),
          ),
          IconButton(
            tooltip: 'Edit label',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editLabel(rec),
          ),
          IconButton(
            tooltip: _audioOn ? 'Mute beeps' : 'Beep on signal',
            icon: Icon(_audioOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => _audioOn = !_audioOn),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: rec.samples.isEmpty ? null : () => _exportCsv(rec),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'gatt':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GattExplorerPage(
                        deviceId: rec.id,
                        displayName: label ?? bondedName ?? rec.name,
                      ),
                    ),
                  );
                  break;
                case 'cal':
                  _calibrateAt1m(rec);
                  break;
                case 'clearCal':
                  _clearCalibration(rec);
                  break;
                case 'pair':
                  _pair(rec);
                  break;
                case 'unpair':
                  _unpair(rec);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'gatt',
                child: ListTile(
                  leading: Icon(Icons.account_tree_outlined),
                  title: Text('Connect & explore (GATT)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (isPaired)
                const PopupMenuItem(
                  value: 'unpair',
                  child: ListTile(
                    leading: Icon(Icons.bluetooth_disabled),
                    title: Text('Unpair'),
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'pair',
                  child: ListTile(
                    leading: Icon(Icons.bluetooth_connected),
                    title: Text('Pair with this device'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'cal',
                child: ListTile(
                  leading: Icon(Icons.straighten),
                  title: Text('Calibrate at 1 m'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (calibration != null)
                const PopupMenuItem(
                  value: 'clearCal',
                  child: ListTile(
                    leading: Icon(Icons.restore),
                    title: Text('Clear calibration'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isPaired)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.bluetooth_connected,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Paired with this phone',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (guess != null && !isPaired)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    _confidenceIcon(guess.confidence),
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_confidencePrefix(guess.confidence)} ${guess.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (label != null &&
              rec.name != label &&
              (bondedName == null || bondedName != label))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Bluetooth name: ${rec.name}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Center(child: SignalGauge(rssi: smoothedRssi, isOffline: isOffline)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 36,
              child: Sparkline(
                samples: rec.samples,
                color: qualityFromRssi(smoothedRssi).color,
                windowSeconds: 60,
                maxWindowSeconds: 600,
                offlineAfter: settings.offlineThreshold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              isOffline
                  ? 'Offline — last heard ${formatDuration(age)} ago'
                  : settings.smoothingWindow > 1
                      ? 'Smoothed over ${settings.smoothingWindow} samples · raw ${rec.currentRssi} dBm · last seen ${formatDuration(age)} ago'
                      : 'Last seen ${formatDuration(age)} ago',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          _FindItButton(
            active: _findItMode,
            onPressed: _toggleFindIt,
          ),
          const SizedBox(height: 12),
          _DirectionRow(
            fix: DeviceMemory.instance.directionFor(rec.id.str),
            onSweep: () => showSweepSheet(context, rec.id),
          ),
          const SizedBox(height: 16),
          _StatGrid(
            stats: [
              _Stat('Distance (est.)', formatDistance(dist)),
              _Stat('Avg RSSI',
                  rec.avgRssi == null ? '—' : '${rec.avgRssi!.toStringAsFixed(1)} dBm'),
              _Stat('Min',
                  rec.minRssi == null ? '—' : '${rec.minRssi} dBm'),
              _Stat('Max',
                  rec.maxRssi == null ? '—' : '${rec.maxRssi} dBm'),
              _Stat('Samples', '${rec.samples.length}'),
              _Stat(
                'Tx @ 1 m',
                calibration != null
                    ? '$calibration dBm (cal.)'
                    : (rec.txPower == null ? '—' : '${rec.txPower} dBm'),
              ),
            ],
          ),
          if (ibeacon != null || eddystone != null) ...[
            const SizedBox(height: 24),
            Text('Beacon', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (ibeacon != null) ...[
              _InfoRow('Type', 'iBeacon'),
              _InfoRow('UUID', ibeacon.uuid),
              _InfoRow('Major', '${ibeacon.major}'),
              _InfoRow('Minor', '${ibeacon.minor}'),
              _InfoRow('Measured power', '${ibeacon.measuredPower} dBm @ 1 m'),
            ],
            if (eddystone != null) ...[
              _InfoRow('Type', eddystoneTypeLabel(eddystone.frameType)),
              _InfoRow('Payload', eddystone.payload),
            ],
          ],
          const SizedBox(height: 24),
          Text(
            'Signal over time (last ${settings.chartWindowSeconds}s)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: RssiChart(
              samples: rec.samples,
              windowSeconds: settings.chartWindowSeconds,
            ),
          ),
          const SizedBox(height: 24),
          Text('Identity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _InfoRow('Address', rec.id.str),
          if (rec.localName != null && rec.localName!.isNotEmpty)
            _InfoRow('Advertised name', rec.localName!),
          if (rec.manufacturerId != null)
            _InfoRow(
              'Manufacturer',
              '${manufacturerNameFor(rec.manufacturerId!) ?? "Unknown"} '
                  '(0x${rec.manufacturerId!.toRadixString(16).padLeft(4, '0').toUpperCase()})',
            ),
          if (rec.rawManufacturerBytes.isNotEmpty)
            _InfoRow(
              'Mfr data',
              rec.rawManufacturerBytes
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(' '),
            ),
          _InfoRow('First seen', formatTime(rec.firstSeen)),
          _InfoRow('Last seen', formatTime(rec.lastSeen)),
          if (rec.serviceUuids.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Services advertised', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rec.serviceUuids.map((u) {
              final known = serviceNameFor(u.str);
              return _InfoRow(known ?? 'Service', u.str);
            }),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FindItButton extends StatelessWidget {
  const _FindItButton({required this.active, required this.onPressed});
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: active
          ? theme.colorScheme.primary
          : theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                active ? Icons.vibration : Icons.travel_explore,
                color: active
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Find it: ON' : 'Find it mode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: active
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      active
                          ? 'Move around — pulses speed up when you\'re closer.'
                          : 'Vibrate (and optionally beep) faster as signal strengthens.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: active
                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
                            : theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                active ? Icons.toggle_on : Icons.toggle_off,
                size: 32,
                color: active
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({required this.fix, required this.onSweep});
  final DirectionFix? fix;
  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fix;
    if (f == null) {
      return Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onSweep,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.explore_outlined,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sweep for direction',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          )),
                      Text(
                        'Rotate the phone a full circle — we\'ll estimate which way the device is.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CompassDial(fix: f, size: 110),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Estimated direction',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Heading shown is magnetic-north relative. Re-sweep after moving.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Sweep again'),
                  onPressed: onSweep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats.map((s) {
        return Container(
          width: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                s.value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
