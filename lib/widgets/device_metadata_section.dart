import 'package:flutter/material.dart';

import '../models/device_record.dart';
import '../utils/beacon_parsers.dart';
import '../utils/bt_helpers.dart';
import 'info_row.dart';
import 'rssi_chart.dart';

/// The "everything you might want to know about this device" tail of the
/// device detail page: beacon details (when present), the historical RSSI
/// chart, and the read-only Identity / Services info rows.
///
/// All data comes from the [DeviceRecord] directly — no service lookups —
/// so this widget is cheap to rebuild and trivial to use elsewhere
/// (e.g. session detail screen could surface the same metadata).
class DeviceMetadataSection extends StatelessWidget {
  const DeviceMetadataSection({
    super.key,
    required this.record,
    required this.chartWindowSeconds,
  });

  final DeviceRecord record;
  final int chartWindowSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ibeacon = record.iBeacon;
    final eddystone = record.eddystone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ibeacon != null || eddystone != null) ...[
          const SizedBox(height: 24),
          Text('Beacon', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (ibeacon != null) ...[
            InfoRow('Type', 'iBeacon'),
            InfoRow('UUID', ibeacon.uuid),
            InfoRow('Major', '${ibeacon.major}'),
            InfoRow('Minor', '${ibeacon.minor}'),
            InfoRow('Measured power', '${ibeacon.measuredPower} dBm @ 1 m'),
          ],
          if (eddystone != null) ...[
            InfoRow('Type', eddystoneTypeLabel(eddystone.frameType)),
            InfoRow('Payload', eddystone.payload),
          ],
        ],
        const SizedBox(height: 24),
        Text(
          'Signal over time (last ${chartWindowSeconds}s)',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: RssiChart(
            samples: record.samples,
            windowSeconds: chartWindowSeconds,
          ),
        ),
        const SizedBox(height: 24),
        Text('Identity', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        InfoRow('Address', record.id.str),
        if (record.localName != null && record.localName!.isNotEmpty)
          InfoRow('Advertised name', record.localName!),
        if (record.manufacturerId != null)
          InfoRow(
            'Manufacturer',
            '${manufacturerNameFor(record.manufacturerId!) ?? "Unknown"} '
                '(0x${record.manufacturerId!.toRadixString(16).padLeft(4, '0').toUpperCase()})',
          ),
        if (record.rawManufacturerBytes.isNotEmpty)
          InfoRow(
            'Mfr data',
            record.rawManufacturerBytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(' '),
          ),
        InfoRow('First seen', formatTime(record.firstSeen)),
        InfoRow('Last seen', formatTime(record.lastSeen)),
        if (record.serviceUuids.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Services advertised', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...record.serviceUuids.map((u) {
            final known = serviceNameFor(u.str);
            return InfoRow(known ?? 'Service', u.str);
          }),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}
