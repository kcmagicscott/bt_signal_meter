import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/device_record.dart';

/// Time-series chart of recent RSSI samples (most recent N seconds).
class RssiChart extends StatelessWidget {
  const RssiChart({
    super.key,
    required this.samples,
    this.windowSeconds = 60,
  });

  final List<RssiSample> samples;
  final int windowSeconds;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Center(
        child: Text(
          'Waiting for signal data…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final now = DateTime.now();
    final windowStart = now.subtract(Duration(seconds: windowSeconds));
    final filtered = samples.where((s) => s.time.isAfter(windowStart)).toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No samples in the last ${windowSeconds}s',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final spots = filtered.map((s) {
      final secondsAgo =
          now.difference(s.time).inMilliseconds / 1000.0;
      return FlSpot(-secondsAgo, s.rssi.toDouble());
    }).toList();

    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.primary;

    return LineChart(
      LineChartData(
        minX: -windowSeconds.toDouble(),
        maxX: 0,
        minY: -100,
        maxY: -30,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 10,
          verticalInterval: 15,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 0.5,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: Colors.grey.shade300,
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade400),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 10,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${v.toInt()}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 15,
              reservedSize: 24,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  v == 0 ? 'now' : '${v.toInt()}s',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: lineColor,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
