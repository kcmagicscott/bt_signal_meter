import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/direction_finder.dart';

/// Modal flow for finding a device's direction. Two stages:
///   1. brief instructions card (how to hold the phone, body rotation)
///   2. live pointer mode — arrow rotates relative to the phone so the
///      user can physically aim at the device; background sweep keeps
///      refining the estimate; tap "Found it" to save.
Future<void> showSweepSheet(BuildContext context, DeviceIdentifier id) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: true,
    builder: (_) => _SweepFlow(deviceId: id),
  );
  if (DirectionFinder.instance.isSweeping) {
    await DirectionFinder.instance.cancel();
  }
}

class _SweepFlow extends StatefulWidget {
  const _SweepFlow({required this.deviceId});
  final DeviceIdentifier deviceId;

  @override
  State<_SweepFlow> createState() => _SweepFlowState();
}

class _SweepFlowState extends State<_SweepFlow> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return _InstructionsCard(
        onStart: () async {
          await DirectionFinder.instance.start(widget.deviceId);
          if (!mounted) return;
          if (!context.mounted) return;
          if (DirectionFinder.instance.sensorUnavailable) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No compass sensor on this device — direction finding unavailable.',
                ),
              ),
            );
            Navigator.of(context).maybePop();
            return;
          }
          setState(() => _started = true);
        },
      );
    }
    return const _PointerStage();
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                'Find the direction',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            const Center(child: _SpinningCompassPreview(size: 100)),
            const SizedBox(height: 16),
            _BulletRow(
              icon: Icons.phone_android,
              text: 'Hold the phone flat against the front of your body.',
            ),
            _BulletRow(
              icon: Icons.rotate_right,
              text:
                  'Turn your whole body slowly — the arrow will swing toward the device as data comes in.',
            ),
            _BulletRow(
              icon: Icons.center_focus_strong,
              text:
                  'Stop turning when the screen lights up green. Tap "Found it" to save.',
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.explore),
              label: const Text('Start'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                onStart();
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PointerStage extends StatefulWidget {
  const _PointerStage();

  @override
  State<_PointerStage> createState() => _PointerStageState();
}

class _PointerStageState extends State<_PointerStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  bool _wasAligned = false;
  final DateTime _startedAt = DateTime.now();
  Timer? _stuckCheckTimer;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WakelockPlus.enable().catchError((_) => false);
    DirectionFinder.instance.addListener(_onChange);
    // Re-trigger a rebuild every second so the "stuck" warnings have a chance
    // to appear when no compass / no samples ever arrive.
    _stuckCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    if (!mounted) return;
    final aligned = _isAligned();
    if (aligned && !_wasAligned) {
      HapticFeedback.heavyImpact();
    }
    _wasAligned = aligned;
    setState(() {});
  }

  bool _isAligned() {
    final f = DirectionFinder.instance;
    final h = f.currentHeading;
    final est = f.currentEstimate;
    if (h == null || est == null) return false;
    var diff = (est.bearingDeg - h + 360) % 360;
    if (diff > 180) diff = 360 - diff;
    return diff < 15 && est.confidence >= 0.25;
  }

  @override
  void dispose() {
    _glow.dispose();
    _stuckCheckTimer?.cancel();
    DirectionFinder.instance.removeListener(_onChange);
    WakelockPlus.disable().catchError((_) => false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finder = DirectionFinder.instance;
    final heading = finder.currentHeading;
    final estimate = finder.currentEstimate;

    final relativeAngle = (heading != null && estimate != null)
        ? (estimate.bearingDeg - heading + 360) % 360
        : null;
    final absDiff = relativeAngle == null
        ? null
        : math.min(relativeAngle, 360 - relativeAngle);
    final isAligned =
        absDiff != null && absDiff < 15 && (estimate?.confidence ?? 0) >= 0.25;
    final isWarm = absDiff != null && absDiff < 50;

    final elapsedSec = DateTime.now().difference(_startedAt).inSeconds;
    final waitingForCompass = heading == null && elapsedSec >= 3;
    final waitingForSamples =
        heading != null && finder.totalSamples == 0 && elapsedSec >= 5;
    final stuck = waitingForCompass || waitingForSamples;
    final stuckMsg = waitingForCompass
        ? 'Compass not responding — check device permissions or magnetic interference'
        : waitingForSamples
            ? 'No signal samples yet — the device may have stopped advertising'
            : null;

    final headlineText = estimate == null
        ? (heading == null
            ? 'Waiting for compass…'
            : 'Rotate to find the signal')
        : isAligned
            ? 'Pointing at it'
            : isWarm
                ? 'Getting close'
                : 'Keep turning';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              headlineText,
              style: theme.textTheme.titleLarge?.copyWith(
                color: isAligned
                    ? Colors.green.shade700
                    : stuck
                        ? Colors.orange.shade800
                        : null,
                fontWeight: isAligned ? FontWeight.w600 : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              estimate == null
                  ? 'Hold phone flat, turn your whole body'
                  : '${estimate.bearingDeg.round()}° · ${(estimate.confidence * 100).round()}% confidence',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (stuckMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.orange.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stuckMsg,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _glow,
              builder: (_, child) {
                return SizedBox(
                  width: 280,
                  height: 280,
                  child: CustomPaint(
                    painter: _PointerDialPainter(
                      relativeBearingDeg: relativeAngle,
                      confidence: estimate?.confidence ?? 0,
                      isAligned: isAligned,
                      isWarm: isWarm,
                      glowT: _glow.value,
                      primary: theme.colorScheme.primary,
                      outline: theme.colorScheme.outlineVariant,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              estimate == null
                  ? '${finder.totalSamples} samples · ${finder.totalRotationDeg.round()}° rotated'
                  : '${finder.totalSamples} samples · ${estimate.rangeDb} dB swing',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Found it'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          isAligned ? Colors.green.shade700 : null,
                      foregroundColor: isAligned ? Colors.white : null,
                    ),
                    onPressed: estimate == null
                        ? null
                        : () async {
                            HapticFeedback.lightImpact();
                            await DirectionFinder.instance.finalize();
                            if (!mounted) return;
                            if (context.mounted) {
                              Navigator.of(context).maybePop();
                            }
                          },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  icon: const Icon(Icons.restart_alt),
                  tooltip: 'Reset and start fresh',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    DirectionFinder.instance.resetSamples();
                  },
                ),
              ],
            ),
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

class _PointerDialPainter extends CustomPainter {
  _PointerDialPainter({
    required this.relativeBearingDeg,
    required this.confidence,
    required this.isAligned,
    required this.isWarm,
    required this.glowT,
    required this.primary,
    required this.outline,
  });

  /// 0 = device is forward of phone, 90 = right, 180 = behind, 270 = left.
  final double? relativeBearingDeg;
  final double confidence;
  final bool isAligned;
  final bool isWarm;
  final double glowT;
  final Color primary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 16;

    // Aligned glow — pulsing soft halo.
    if (isAligned) {
      canvas.drawCircle(
        center,
        r * 1.18,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.10 + 0.18 * glowT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
      canvas.drawCircle(
        center,
        r * 1.05,
        Paint()
          ..color = Colors.green.withValues(alpha: 0.18 + 0.12 * glowT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }

    // Outer ring.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = isAligned
            ? Colors.green.shade500
            : outline.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isAligned ? 3.2 : 1.6,
    );

    // 'Forward of phone' marker (12 o'clock).
    final fwdPaint = Paint()..color = outline;
    canvas.drawCircle(Offset(center.dx, center.dy - r), 4, fwdPaint);
    final fwdLabelStyle = TextStyle(
      color: outline,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'TOP', style: fwdLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - r - tp.height - 6),
    );

    // Tick marks at 90° intervals.
    final tickPaint = Paint()
      ..color = outline.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    for (var i = 1; i < 4; i++) {
      final a = i * (math.pi / 2) - math.pi / 2;
      canvas.drawLine(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        center + Offset(math.cos(a) * (r - 8), math.sin(a) * (r - 8)),
        tickPaint,
      );
    }

    if (relativeBearingDeg == null) {
      // No data yet — idle prompt.
      canvas.drawCircle(
        center,
        6,
        Paint()..color = outline.withValues(alpha: 0.5),
      );
      return;
    }

    final rad = relativeBearingDeg! * math.pi / 180 - math.pi / 2;
    final arrowColor = isAligned
        ? Colors.green.shade600
        : isWarm
            ? Colors.orange.shade600
            : Colors.red.shade400;

    // Confidence cone behind the arrow — wider when less confident.
    final coneHalfWidth =
        math.pi / 8 + (1 - confidence.clamp(0.0, 1.0)) * (math.pi / 4);
    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: r * 0.82),
        rad - coneHalfWidth,
        coneHalfWidth * 2,
        false,
      )
      ..close();
    canvas.drawPath(
      conePath,
      Paint()
        ..color = arrowColor.withValues(alpha: 0.12 + 0.12 * confidence)
        ..style = PaintingStyle.fill,
    );

    // Big chunky arrow.
    final tip = center +
        Offset(math.cos(rad) * r * 0.80, math.sin(rad) * r * 0.80);
    final back = math.pi - 0.42;
    final left = center +
        Offset(math.cos(rad + back) * r * 0.30,
            math.sin(rad + back) * r * 0.30);
    final right = center +
        Offset(math.cos(rad - back) * r * 0.30,
            math.sin(rad - back) * r * 0.30);
    final tail = center +
        Offset(math.cos(rad + math.pi) * r * 0.16,
            math.sin(rad + math.pi) * r * 0.16);
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = arrowColor);
    canvas.drawCircle(center, 6, Paint()..color = arrowColor);
  }

  @override
  bool shouldRepaint(_PointerDialPainter old) =>
      old.relativeBearingDeg != relativeBearingDeg ||
      old.confidence != confidence ||
      old.isAligned != isAligned ||
      old.isWarm != isWarm ||
      old.glowT != glowT ||
      old.primary != primary ||
      old.outline != outline;
}

class _SpinningCompassPreview extends StatefulWidget {
  const _SpinningCompassPreview({required this.size});
  final double size;

  @override
  State<_SpinningCompassPreview> createState() =>
      _SpinningCompassPreviewState();
}

class _SpinningCompassPreviewState extends State<_SpinningCompassPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _PreviewCompassPainter(
              angleRad: _ctrl.value * 2 * math.pi,
              primary: theme.colorScheme.primary,
              outline: theme.colorScheme.outlineVariant,
            ),
          ),
        );
      },
    );
  }
}

class _PreviewCompassPainter extends CustomPainter {
  _PreviewCompassPainter({
    required this.angleRad,
    required this.primary,
    required this.outline,
  });
  final double angleRad;
  final Color primary;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 2;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = outline.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var i = 0; i < 8; i++) {
      final a = i * (math.pi / 4) - math.pi / 2;
      canvas.drawLine(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        center + Offset(math.cos(a) * (r - 6), math.sin(a) * (r - 6)),
        Paint()
          ..color = outline.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
    }
    final tip = center +
        Offset(math.cos(angleRad - math.pi / 2) * r * 0.75,
            math.sin(angleRad - math.pi / 2) * r * 0.75);
    final back = math.pi - 0.45;
    final left = center +
        Offset(math.cos(angleRad - math.pi / 2 + back) * r * 0.25,
            math.sin(angleRad - math.pi / 2 + back) * r * 0.25);
    final right = center +
        Offset(math.cos(angleRad - math.pi / 2 - back) * r * 0.25,
            math.sin(angleRad - math.pi / 2 - back) * r * 0.25);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = primary);
    canvas.drawCircle(center, 3, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(_PreviewCompassPainter old) =>
      old.angleRad != angleRad ||
      old.primary != primary ||
      old.outline != outline;
}
