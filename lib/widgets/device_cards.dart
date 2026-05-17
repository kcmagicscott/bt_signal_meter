import 'package:flutter/material.dart';

import '../services/gatt_identifier.dart';
import '../utils/bt_helpers.dart';
import '../utils/sensor_parsers.dart';

/// Large find-it status panel. Renders one of two states:
///   - "Lost signal" (red, with peak-time hint) when the device is offline
///     or we just detected a loss
///   - Live tracker (big distance + dBm + "you're N dB weaker than peak"
///     hint) when we have data
///
/// Lifted out of device_detail_page.dart so the page stays focused on
/// orchestration; this widget is pure presentation.
class FindItPanel extends StatelessWidget {
  const FindItPanel({
    super.key,
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

/// Renders the cached GATT identity (manufacturer / model / firmware /
/// hardware revisions) as a labelled key/value card. Only shown when a
/// successful Identify call has populated GattIdentifier's cache.
class IdentityCard extends StatelessWidget {
  const IdentityCard({super.key, required this.identity});
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

/// Surfaces a [SensorReading] extracted from a device's advertisement
/// (Ruuvi / Govee / Xiaomi etc). Shows whichever fields the parser was
/// able to populate — temp, humidity, pressure, battery.
class SensorCard extends StatelessWidget {
  const SensorCard({super.key, required this.reading});
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
