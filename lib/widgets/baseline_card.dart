import 'package:flutter/material.dart';

/// Card showing the user's "baseline" RSSI for a device and how far the
/// current signal has drifted from it. Two visual states:
///
///   - **no baseline** → a tonal CTA prompting the user to capture one.
///   - **baseline set** → an indicator showing current drift vs baseline,
///     coloured green/amber/red based on whether the drift exceeds the
///     configured threshold.
class BaselineCard extends StatelessWidget {
  const BaselineCard({
    super.key,
    required this.baselineRssi,
    required this.baselineSetAt,
    required this.currentRssi,
    required this.thresholdDb,
    required this.isOffline,
    required this.onSet,
    required this.onClear,
  });

  final int? baselineRssi;
  final DateTime? baselineSetAt;
  final int currentRssi;
  final int thresholdDb;
  final bool isOffline;
  final VoidCallback onSet;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bl = baselineRssi;
    if (bl == null) {
      return Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onSet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.flag_outlined,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Set baseline',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          )),
                      Text(
                        'Capture current signal as a reference — drift alerts will compare against it.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add,
                    color: theme.colorScheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      );
    }

    final drift = isOffline ? null : currentRssi - bl;
    final exceeds = drift != null && drift.abs() >= thresholdDb;
    final bg = exceeds
        ? Colors.red.shade50
        : theme.colorScheme.surfaceContainerHigh;
    final fg = exceeds ? Colors.red.shade900 : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: exceeds
              ? Colors.red.shade400
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: exceeds ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            exceeds
                ? Icons.warning_amber_outlined
                : Icons.flag,
            color: exceeds ? Colors.red.shade700 : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _headline(drift, exceeds),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subhead(bl, baselineSetAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg?.withValues(alpha: 0.85) ??
                        theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Clear baseline',
            icon: Icon(Icons.close, color: fg ?? theme.colorScheme.outline),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  static String _headline(int? drift, bool exceeds) {
    if (drift == null) return 'Baseline · offline';
    final sign = drift >= 0 ? '+' : '−';
    final mag = drift.abs();
    if (drift == 0) return 'On baseline · 0 dB';
    if (!exceeds) {
      return 'Within range · $sign$mag dB';
    }
    return drift > 0
        ? 'Stronger than baseline · +$mag dB'
        : 'Weaker than baseline · −$mag dB';
  }

  static String _subhead(int bl, DateTime? setAt) {
    final age = setAt == null
        ? ''
        : ' · set ${_ageLabel(DateTime.now().difference(setAt))} ago';
    return 'Baseline $bl dBm$age';
  }

  static String _ageLabel(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 48) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
