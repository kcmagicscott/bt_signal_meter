import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Live "you are here / device is there" arrow rendered during a sweep.
/// The user holds the phone flat — TOP of the dial = forward of phone — and
/// the arrow rotates to point at the inferred device bearing relative to
/// the phone's current heading. When alignment passes the
/// confidence/aim thresholds, the painter draws a pulsing green halo.
class PointerDialPainter extends CustomPainter {
  PointerDialPainter({
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
  bool shouldRepaint(PointerDialPainter old) =>
      old.relativeBearingDeg != relativeBearingDeg ||
      old.confidence != confidence ||
      old.isAligned != isAligned ||
      old.isWarm != isWarm ||
      old.glowT != glowT ||
      old.primary != primary ||
      old.outline != outline;
}

/// Decorative slowly-rotating compass — shown on the sweep flow's
/// instructions card as a "this is what's about to happen" preview.
class SpinningCompassPreview extends StatefulWidget {
  const SpinningCompassPreview({super.key, required this.size});
  final double size;

  @override
  State<SpinningCompassPreview> createState() =>
      _SpinningCompassPreviewState();
}

class _SpinningCompassPreviewState extends State<SpinningCompassPreview>
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
