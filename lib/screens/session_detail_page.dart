import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/device_memory.dart';
import '../services/session_recorder.dart';
import '../utils/bt_helpers.dart';
import '../widgets/sparkline.dart';
import 'device_detail_page.dart';

class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final recorder = SessionRecorder.instance;
    final start = recorder.start;
    final end = recorder.end;
    if (start == null || end == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('No session to display')),
      );
    }

    final devices = ScannerState.instance.allDevices.values
        .where((d) =>
            d.samples.any((s) => !s.time.isBefore(start) && !s.time.isAfter(end)))
        .toList();

    int samplesInWindow(DeviceRecord d) =>
        d.samples.where((s) => !s.time.isBefore(start) && !s.time.isAfter(end)).length;

    devices.sort((a, b) => samplesInWindow(b).compareTo(samplesInWindow(a)));

    final duration = end.difference(start);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            tooltip: 'Export combined CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _exportCombinedCsv(context, devices, start, end),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatGrid(stats: [
            _Stat('Duration', formatDuration(duration)),
            _Stat('Devices seen', '${devices.length}'),
            _Stat(
              'Total samples',
              '${devices.fold<int>(0, (sum, d) => sum + samplesInWindow(d))}',
            ),
            _Stat('Started', formatTime(start)),
            _Stat('Ended', formatTime(end)),
            _Stat('Avg RSSI', _avgRssi(devices, start, end)),
          ]),
          const SizedBox(height: 16),
          Text('Devices in this session', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...devices.map((d) => _DeviceRow(
                record: d,
                windowStart: start,
                windowEnd: end,
              )),
        ],
      ),
    );
  }

  String _avgRssi(List<DeviceRecord> devices, DateTime start, DateTime end) {
    int sum = 0;
    int n = 0;
    for (final d in devices) {
      for (final s in d.samples) {
        if (s.time.isBefore(start) || s.time.isAfter(end)) continue;
        sum += s.rssi;
        n++;
      }
    }
    if (n == 0) return '—';
    return '${(sum / n).toStringAsFixed(1)} dBm';
  }

  Future<void> _exportCombinedCsv(
    BuildContext context,
    List<DeviceRecord> devices,
    DateTime start,
    DateTime end,
  ) async {
    final mem = DeviceMemory.instance;
    final buf = StringBuffer('timestamp_iso,device_id,device_name,rssi_dbm\n');
    for (final d in devices) {
      final name = (mem.labelFor(d.id.str) ?? d.name)
          .replaceAll(',', ' ')
          .replaceAll('\n', ' ');
      for (final s in d.samples) {
        if (s.time.isBefore(start) || s.time.isAfter(end)) continue;
        buf.writeln('${s.time.toIso8601String()},${d.id.str},$name,${s.rssi}');
      }
    }
    try {
      final dir = await getTemporaryDirectory();
      final stamp = start.toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/bt_session_$stamp.csv');
      await file.writeAsString(buf.toString());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'BT Signal Meter session',
          text: 'Session ${start.toIso8601String()} → ${end.toIso8601String()}',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.record,
    required this.windowStart,
    required this.windowEnd,
  });
  final DeviceRecord record;
  final DateTime windowStart;
  final DateTime windowEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = record.samples
        .where(
            (s) => !s.time.isBefore(windowStart) && !s.time.isAfter(windowEnd))
        .toList(growable: false);
    if (samples.isEmpty) return const SizedBox.shrink();
    final values = samples.map((s) => s.rssi).toList();
    final minR = values.reduce((a, b) => a < b ? a : b);
    final maxR = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final name = DeviceMemory.instance.labelFor(record.id.str) ?? record.name;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailPage(deviceId: record.id),
          ),
        ),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${samples.length} samples · avg ${avg.toStringAsFixed(1)} dBm · '
              'range $minR…$maxR',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 22,
              child: Sparkline(
                samples: samples,
                color: qualityFromRssi(avg.round()).color,
                windowSeconds:
                    windowEnd.difference(windowStart).inSeconds.clamp(15, 36000),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
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
