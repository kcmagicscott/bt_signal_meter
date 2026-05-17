import 'package:flutter/material.dart';

/// A label+value pair rendered inside a [StatGrid] cell.
class Stat {
  const Stat(this.label, this.value);
  final String label;
  final String value;
}

/// Wrap of fixed-width tiles showing label+value pairs. Used to surface
/// summary numbers (avg/min/max RSSI, sample counts, distance, etc.) on
/// the device detail and session detail screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.stats});

  final List<Stat> stats;

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
