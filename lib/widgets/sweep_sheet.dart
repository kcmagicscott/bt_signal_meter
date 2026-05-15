import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/direction_finder.dart';

/// Bottom-sheet UI for the rotate-to-find sweep. Starts the sweep on open,
/// shows live coverage + heading + RSSI, auto-closes on completion.
Future<void> showSweepSheet(BuildContext context, DeviceIdentifier id) async {
  await DirectionFinder.instance.start(id);
  if (!context.mounted) return;
  if (DirectionFinder.instance.sensorUnavailable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No compass sensor on this device — direction sweep unavailable.',
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SweepSheet(),
  );
  if (DirectionFinder.instance.isSweeping) {
    await DirectionFinder.instance.cancel();
  }
}

class _SweepSheet extends StatefulWidget {
  const _SweepSheet();

  @override
  State<_SweepSheet> createState() => _SweepSheetState();
}

class _SweepSheetState extends State<_SweepSheet> {
  @override
  void initState() {
    super.initState();
    DirectionFinder.instance.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (!DirectionFinder.instance.isSweeping) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    DirectionFinder.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finder = DirectionFinder.instance;
    final heading = finder.currentHeading;
    final rssi = finder.currentRssi;
    final coverage = finder.coverage;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sweep for direction', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Hold the phone flat. Slowly turn in place a full circle '
              '— we\'ll find the heading where the signal peaks.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              height: 220,
              child: CustomPaint(
                painter: _SweepPainter(
                  heading: heading,
                  coveredBuckets: finder.coveredBuckets,
                  bucketCount: finder.bucketCount,
                  primary: theme.colorScheme.primary,
                  outline: theme.colorScheme.outlineVariant,
                  surface: theme.colorScheme.surface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              heading == null
                  ? 'Waiting for compass…'
                  : '${heading.round()}°  ·  ${rssi ?? "—"} dBm',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${(coverage * 100).round()}% covered',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: coverage.clamp(0.0, 1.0)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () async {
                await DirectionFinder.instance.cancel();
                if (!mounted) return;
                if (context.mounted) Navigator.of(context).maybePop();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.heading,
    required this.coveredBuckets,
    required this.bucketCount,
    required this.primary,
    required this.outline,
    required this.surface,
  });

  final double? heading;
  final Set<int> coveredBuckets;
  final int bucketCount;
  final Color primary;
  final Color outline;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;
    final bucketRad = 2 * math.pi / bucketCount;

    final filled = Paint()..color = primary.withValues(alpha: 0.28);
    final empty = Paint()..color = outline.withValues(alpha: 0.18);
    for (var i = 0; i < bucketCount; i++) {
      final start = i * bucketRad - math.pi / 2;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: r),
          start,
          bucketRad * 0.92,
          false,
        )
        ..close();
      canvas.drawPath(path, coveredBuckets.contains(i) ? filled : empty);
    }

    canvas.drawCircle(center, r * 0.55, Paint()..color = surface);
    canvas.drawCircle(
      center,
      r * 0.55,
      Paint()
        ..color = outline.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    if (heading != null) {
      final angle = (heading! * math.pi / 180) - math.pi / 2;
      final tip = center +
          Offset(math.cos(angle) * r * 0.5, math.sin(angle) * r * 0.5);
      final back = math.pi - 0.4;
      final left = center +
          Offset(math.cos(angle + back) * r * 0.18,
              math.sin(angle + back) * r * 0.18);
      final right = center +
          Offset(math.cos(angle - back) * r * 0.18,
              math.sin(angle - back) * r * 0.18);
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(arrow, Paint()..color = primary);
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.heading != heading ||
      old.coveredBuckets.length != coveredBuckets.length ||
      old.primary != primary ||
      old.outline != outline ||
      old.surface != surface;
}
