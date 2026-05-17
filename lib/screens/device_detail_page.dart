import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_record.dart';
import '../models/direction_fix.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../services/gatt_identifier.dart';
import '../utils/beacon_parsers.dart';
import '../utils/bt_helpers.dart';
import '../utils/device_display.dart';
import '../utils/device_guess.dart';
import '../utils/sensor_parsers.dart';
import '../widgets/compass_dial.dart';
import '../widgets/hot_cold_indicator.dart';
import '../widgets/rssi_chart.dart';
import '../widgets/signal_gauge.dart';
import '../widgets/sparkline.dart';
import '../widgets/stat_grid.dart';
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
  Timer? _lostSignalTimer;
  bool _findItMode = false;
  bool _audioOn = false;

  /// Best (least-negative) RSSI seen since find-it was engaged. Resets each
  /// time find-it toggles on. Lets us tell the user "you're 8 dB weaker than
  /// peak — turn around" while hunting.
  int? _findItPeakRssi;
  DateTime? _findItPeakTime;

  /// True once we've detected the device dropping offline while find-it was
  /// active. Triggers the visual + haptic "lost signal!" alert.
  bool _lostSignal = false;

  /// True when the smoothed signal was within 1 dB of peak last tick. Used
  /// to detect *entering* the lock-on zone (transition false→true) so the
  /// celebratory haptic + chime fires exactly once per lock-on.
  bool _wasAtPeak = false;
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
    if (_findItMode) {
      _updatePeakAndOfflineCheck();
      _scheduleHapticPulse();
    }
    setState(() {});
  }

  /// Tracks the best RSSI seen since find-it engaged, and triggers the
  /// lost-signal alert if the device drops offline mid-hunt.
  void _updatePeakAndOfflineCheck() {
    final rec = ScannerState.instance.deviceFor(widget.deviceId);
    if (rec == null) return;
    final settings = AppSettings.instance;
    final isOffline = rec.isOfflineFor(settings.offlineThreshold);
    if (isOffline) {
      if (!_lostSignal) {
        _lostSignal = true;
        // Burst of three medium haptics to grab attention.
        HapticFeedback.heavyImpact();
        Timer(const Duration(milliseconds: 250),
            () => HapticFeedback.heavyImpact());
        Timer(const Duration(milliseconds: 500),
            () => HapticFeedback.heavyImpact());
      }
      return;
    }
    if (_lostSignal) {
      // Signal recovered.
      _lostSignal = false;
    }
    final r = rec.smoothedRssi(settings.smoothingWindow);
    if (_findItPeakRssi == null || r > _findItPeakRssi!) {
      _findItPeakRssi = r;
      _findItPeakTime = DateTime.now();
    }

    // Lock-on detection: when smoothed RSSI comes within 1 dB of the peak
    // (and we actually have a peak, i.e. there's data to compare against),
    // fire a triple-pulse "locked!" haptic + alert chime once per entry.
    if (_findItPeakRssi != null && r >= _findItPeakRssi! - 1) {
      if (!_wasAtPeak) {
        _wasAtPeak = true;
        HapticFeedback.mediumImpact();
        Timer(const Duration(milliseconds: 120),
            () => HapticFeedback.mediumImpact());
        Timer(const Duration(milliseconds: 280),
            () => HapticFeedback.heavyImpact());
        if (_audioOn) {
          SystemSound.play(SystemSoundType.alert);
        }
      }
    } else {
      // Hysteresis: only un-set when we've dropped well below peak so the
      // lock-on doesn't re-fire on small jitter.
      if (_wasAtPeak && r < _findItPeakRssi! - 3) {
        _wasAtPeak = false;
      }
    }
  }

  @override
  void dispose() {
    _appState.removeListener(_onChange);
    _hapticTimer?.cancel();
    _lostSignalTimer?.cancel();
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
    setState(() {
      _findItMode = !_findItMode;
      // Reset session-local find-it state on every toggle (both on and off
      // — toggling off then on starts a fresh hunt).
      _findItPeakRssi = null;
      _findItPeakTime = null;
      _lostSignal = false;
      _wasAtPeak = false;
    });
    if (_findItMode) {
      _updatePeakAndOfflineCheck();
      _scheduleHapticPulse();
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    } else {
      _hapticTimer?.cancel();
      _lostSignalTimer?.cancel();
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

  Future<void> _clearDirection(DeviceRecord rec) async {
    await DeviceMemory.instance.setDirection(rec.id.str, null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved direction cleared — tap Sweep to start fresh'),
      ),
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

  Future<void> _identifyViaGatt(DeviceRecord rec) async {
    final messenger = ScaffoldMessenger.of(context);
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
        // Lookups can take ~15s on slow devices; keep the indicator up until
        // we dismiss it manually so the user sees that work is still pending.
        duration: const Duration(seconds: 60),
      ),
    );
    setState(() {});
    final result = await GattIdentifier.instance.lookup(rec.id);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (result == null || result.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Could not read identity — device may not expose the standard service.'),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Identified: ${result.headline}')),
      );
    }
    setState(() {});
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
    final settings = AppSettings.instance;
    final d = DeviceDisplay.from(rec);
    // Aliases for readability in the long Scaffold body below.
    final label = d.customLabel;
    final bondedName = d.bondedName;
    final isPaired = d.isPaired;
    final isFavorite = d.isFavorite;
    final calibration = d.calibratedTxPower;
    final smoothedRssi = d.smoothedRssi;
    final isOffline = d.isOffline;
    final dist = isOffline
        ? null
        : estimateDistanceMeters(
            rssi: smoothedRssi,
            measuredPowerAt1m: calibration ?? rec.txPower ?? -59,
          );
    final age = Duration(seconds: d.ageSeconds);
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
                case 'identify':
                  _identifyViaGatt(rec);
                  break;
                case 'clearDir':
                  _clearDirection(rec);
                  break;
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
              PopupMenuItem(
                value: 'identify',
                enabled: !GattIdentifier.instance.isPending(rec.id.str),
                child: const ListTile(
                  leading: Icon(Icons.fingerprint),
                  title: Text('Identify via GATT'),
                  subtitle: Text('Read manufacturer + model from the device'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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
              if (DeviceMemory.instance.directionFor(rec.id.str) != null)
                const PopupMenuItem(
                  value: 'clearDir',
                  child: ListTile(
                    leading: Icon(Icons.explore_off),
                    title: Text('Clear saved direction'),
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
          if (GattIdentifier.instance.cached(rec.id.str) != null)
            _IdentityCard(identity: GattIdentifier.instance.cached(rec.id.str)!),
          if (parseSensorData(rec) != null)
            _SensorCard(reading: parseSensorData(rec)!),
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
          if (_findItMode) ...[
            const SizedBox(height: 12),
            _FindItPanel(
              currentRssi: smoothedRssi,
              peakRssi: _findItPeakRssi,
              peakTime: _findItPeakTime,
              distance: dist,
              imperial: settings.imperialDistance,
              isOffline: isOffline,
              lostSignal: _lostSignal,
            ),
            if (!isOffline) ...[
              const SizedBox(height: 12),
              HotColdIndicator(deviceRecord: rec),
            ],
          ],
          const SizedBox(height: 12),
          _DirectionRow(
            fix: DeviceMemory.instance.directionFor(rec.id.str),
            onSweep: () => showSweepSheet(context, rec.id),
          ),
          const SizedBox(height: 16),
          StatGrid(
            stats: [
              Stat('Distance (est.)',
                  formatDistance(dist, imperial: settings.imperialDistance)),
              Stat('Avg RSSI',
                  rec.avgRssi == null ? '—' : '${rec.avgRssi!.toStringAsFixed(1)} dBm'),
              Stat('Min',
                  rec.minRssi == null ? '—' : '${rec.minRssi} dBm'),
              Stat('Max',
                  rec.maxRssi == null ? '—' : '${rec.maxRssi} dBm'),
              Stat('Samples', '${rec.samples.length}'),
              Stat(
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

class _FindItPanel extends StatelessWidget {
  const _FindItPanel({
    required this.currentRssi,
    required this.peakRssi,
    required this.peakTime,
    required this.distance,
    required this.imperial,
    required this.isOffline,
    required this.lostSignal,
  });

  final int currentRssi;
  final int? peakRssi;
  final DateTime? peakTime;
  final double? distance;
  final bool imperial;
  final bool isOffline;
  final bool lostSignal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lostSignal || isOffline) {
      return Card(
        color: theme.colorScheme.errorContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.signal_wifi_bad,
                  size: 48, color: theme.colorScheme.onErrorContainer),
              const SizedBox(height: 8),
              Text(
                'Lost signal',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Move closer or back where signal was last strong.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              if (peakRssi != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Peak was $peakRssi dBm '
                  '${peakTime != null ? formatDuration(DateTime.now().difference(peakTime!)) : ""} ago',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final delta = peakRssi == null ? 0 : currentRssi - peakRssi!;
    final atPeak = delta >= -1;
    final near = delta >= -4;
    final hint = atPeak
        ? 'At peak — getting it'
        : near
            ? 'Close to peak — fine-tune your direction'
            : 'You\'re ${delta.abs()} dB weaker than peak — try turning around';
    final hintColor = atPeak
        ? Colors.green.shade700
        : near
            ? Colors.orange.shade700
            : theme.colorScheme.outline;

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Distance',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        formatDistance(distance, imperial: imperial),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: qualityFromRssi(currentRssi).color,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Now',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$currentRssi',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: qualityFromRssi(currentRssi).color,
                      ),
                    ),
                    Text('dBm', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    peakRssi == null
                        ? Icons.hourglass_empty
                        : (atPeak
                            ? Icons.gps_fixed
                            : (near ? Icons.adjust : Icons.gps_not_fixed)),
                    size: 18,
                    color: hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peakRssi == null
                              ? 'Move around to find a peak…'
                              : hint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hintColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (peakRssi != null && peakTime != null)
                          Text(
                            'Peak: $peakRssi dBm · '
                            '${formatDuration(DateTime.now().difference(peakTime!))} ago',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
      return _SweepStartButton(onPressed: onSweep);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Text('Estimated direction', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _LiveCompassDial(fix: f, size: 150),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Sweep again'),
            onPressed: onSweep,
          ),
        ],
      ),
    );
  }
}

/// CompassDial that subscribes to the device's magnetometer and rotates
/// dynamically so the bearing arrow always points at the target device,
/// not just at the absolute compass bearing. Lets the saved-fix view
/// behave like a "follow me" pointer even after the sweep finalized.
class _LiveCompassDial extends StatefulWidget {
  const _LiveCompassDial({required this.fix, this.size = 140});
  final DirectionFix fix;
  final double size;

  @override
  State<_LiveCompassDial> createState() => _LiveCompassDialState();
}

class _LiveCompassDialState extends State<_LiveCompassDial> {
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;

  @override
  void initState() {
    super.initState();
    final stream = FlutterCompass.events;
    if (stream != null) {
      _sub = stream.listen((e) {
        if (!mounted) return;
        final h = e.heading;
        if (h == null) return;
        setState(() => _heading = h < 0 ? h + 360 : h);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompassDial(
      fix: widget.fix,
      deviceHeadingDeg: _heading,
      size: widget.size,
    );
  }
}

class _SweepStartButton extends StatefulWidget {
  const _SweepStartButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_SweepStartButton> createState() => _SweepStartButtonState();
}

class _SweepStartButtonState extends State<_SweepStartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    return CustomPaint(
                      painter: _StartCompassPainter(
                        angleRad: _ctrl.value * 2 * math.pi,
                        primary: theme.colorScheme.onTertiaryContainer,
                        outline: theme.colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.5),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Find the direction',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Spin in a circle — we\'ll point you at it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCompassPainter extends CustomPainter {
  _StartCompassPainter({
    required this.angleRad,
    required this.primary,
    required this.outline,
  });
  final double angleRad;
  final Color primary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 1;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    for (var i = 0; i < 4; i++) {
      final a = i * (math.pi / 2) - math.pi / 2;
      canvas.drawLine(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        center + Offset(math.cos(a) * (r - 3), math.sin(a) * (r - 3)),
        Paint()
          ..color = outline
          ..strokeWidth = 1.4,
      );
    }
    final tipA = angleRad - math.pi / 2;
    final tip = center +
        Offset(math.cos(tipA) * r * 0.75, math.sin(tipA) * r * 0.75);
    final back = math.pi - 0.45;
    final left = center +
        Offset(math.cos(tipA + back) * r * 0.28,
            math.sin(tipA + back) * r * 0.28);
    final right = center +
        Offset(math.cos(tipA - back) * r * 0.28,
            math.sin(tipA - back) * r * 0.28);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = primary,
    );
    canvas.drawCircle(center, 2.4, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(_StartCompassPainter old) =>
      old.angleRad != angleRad ||
      old.primary != primary ||
      old.outline != outline;
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

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.identity});
  final GattIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fingerprint,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Device identity',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 6),
            if (identity.manufacturer != null)
              _kv(theme, 'Manufacturer', identity.manufacturer!),
            if (identity.modelNumber != null)
              _kv(theme, 'Model', identity.modelNumber!),
            if (identity.firmwareRevision != null)
              _kv(theme, 'Firmware', identity.firmwareRevision!),
            if (identity.hardwareRevision != null)
              _kv(theme, 'Hardware', identity.hardwareRevision!),
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(k, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({required this.reading});
  final SensorReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors,
                    size: 18, color: theme.colorScheme.tertiary),
                const SizedBox(width: 6),
                Text(
                  'Live sensor data${reading.source != null ? ' · ${reading.source}' : ''}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (reading.temperatureC != null)
                  _stat(theme, Icons.thermostat,
                      '${reading.temperatureCStr()}  /  ${reading.temperatureF()}'),
                if (reading.humidityPercent != null)
                  _stat(theme, Icons.water_drop_outlined,
                      reading.humidityStr()),
                if (reading.pressureHpa != null)
                  _stat(theme, Icons.speed,
                      '${reading.pressureHpa!.toStringAsFixed(0)} hPa'),
                if (reading.batteryPercent != null)
                  _stat(theme, Icons.battery_full,
                      '${reading.batteryPercent}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
