import 'package:flutter/material.dart';

/// Compact label chip used in scanner tiles, the device detail page, and
/// session summaries to show short tags ("Paired", "AirPods", "~2.1 m",
/// "offline 12s"). Optional leading icon and an accent colour for chips
/// that should pop (paired device, current session, etc.).
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.text,
    this.accent = false,
    this.icon,
  });

  final String text;
  final bool accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = accent ? theme.colorScheme.onPrimaryContainer : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg ?? theme.colorScheme.outline),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: accent ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}
