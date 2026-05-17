import 'package:flutter/material.dart';

/// The big toggle on the device detail page that engages find-it mode —
/// haptic + audio pulses that speed up as the smoothed RSSI strengthens.
/// State is owned by the parent; this widget is purely presentation.
class FindItButton extends StatelessWidget {
  const FindItButton({super.key, required this.active, required this.onPressed});
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
                            ? theme.colorScheme.onPrimary
                                .withValues(alpha: 0.85)
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
