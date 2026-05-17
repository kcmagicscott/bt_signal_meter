import 'package:flutter/material.dart';

import '../models/device_record.dart';
import '../services/app_settings.dart';
import '../services/bonded_device_registry.dart';
import '../services/device_memory.dart';
import '../services/new_device_monitor.dart';
import '../utils/bt_helpers.dart';
import '../utils/device_guess.dart';
import 'info_chip.dart';
import 'new_pulse_badge.dart';
import 'signal_gauge.dart';
import 'sparkline.dart';

/// One row in the scanner list. Renders one of three layouts depending on
/// the user's current [DensityMode] choice — comfortable (full ListTile
/// with chips and a sparkline), compact (single-row summary), or dense
/// (single line, name + bars + RSSI).
class DeviceListTile extends StatelessWidget {
  const DeviceListTile({
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
    final bondedName =
        BondedDeviceRegistry.instance.bondedNameFor(record.id.str);
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
            measuredPowerAt1m: mem.calibratedTxPowerFor(record.id.str) ??
                record.txPower ??
                -59,
          );
    final guess = guessDeviceType(record);
    final theme = Theme.of(context);

    switch (settings.densityMode) {
      case DensityMode.dense:
        return _buildDense(
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

    return _withSignalStrip(
      rssi: rssi,
      isOffline: isOffline,
      child: Opacity(
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
                  fontWeight: (customLabel != null || hasName)
                      ? FontWeight.w500
                      : FontWeight.w400,
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
              NewPulseBadge(age: newAge),
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
                    icon: Icons.bluetooth_connected,
                  ),
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
                        color:
                            record.trend() > 0 ? Colors.green : Colors.red,
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
    ),
    );
  }

  Widget _buildCompact({
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
      if (!isOffline)
        '~${formatDistance(dist, imperial: settings.imperialDistance)}',
      if (isPaired) 'paired',
      if (isOffline)
        'offline ${ageSeconds}s'
      else if (isStale)
        'stale ${ageSeconds}s',
    ].where((s) => s.isNotEmpty).toList();
    return _withSignalStrip(
      rssi: rssi,
      isOffline: isOffline,
      child: Opacity(
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
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 6),
                          NewPulseBadge(age: newAge),
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
    ),
    );
  }

  Widget _buildDense({
    required ThemeData theme,
    required int rssi,
    required String displayName,
    required bool isOffline,
    required bool isStale,
    required bool isFavorite,
    required DeviceMemory mem,
  }) {
    final qColor = qualityFromRssi(rssi).color;
    return _withSignalStrip(
      rssi: rssi,
      isOffline: isOffline,
      child: Opacity(
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
    ),
    );
  }

  /// Wraps a tile in a thin colored left strip keyed to signal quality.
  /// Lets the user scan the list at a glance — green/orange/red strip
  /// tells you signal strength without parsing dBm numbers.
  static Widget _withSignalStrip({
    required Widget child,
    required int rssi,
    required bool isOffline,
  }) {
    final color = isOffline ? Colors.grey.shade400 : qualityFromRssi(rssi).color;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: child,
    );
  }
}
