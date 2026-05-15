import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/direction_fix.dart';

/// Static result display: a small compass dial with an arrow pointing toward
/// the inferred device bearing, plus age + confidence below.
class CompassDial extends StatelessWidget {
  const CompassDial({
    super.key,
    required this.fix,
    this.deviceHeadingDeg,
    this.size = 120,
  });

  final DirectionFix fix;

  /// If provided, the dial rotates so North stays up regardless of how the
  /// phone is held. Pass the phone's current compass heading.
  final double? deviceHeadingDeg;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relativeBearing =
        deviceHeadingDeg == null ? fix.bearingDeg : fix.bearingDeg - deviceHeadingDeg!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DialPainter(
              bearingDeg: relativeBearing,
              confidence: fix.confidence,
              color: theme.colorScheme.primary,
              outlineColor: theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _bearingLabel(fix.bearingDeg),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          _detailLabel(fix),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  static String _bearingLabel(double deg) {
    const points = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW',
    ];
    final idx = ((deg / 22.5).round()) % 16;
    return '${points[idx]} · ${deg.round()}°';
  }

  static String _detailLabel(DirectionFix fix) {
    final age = DateTime.now().difference(fix.time);
    final ageStr = age.inSeconds < 60
        ? 'just now'
        : age.inMinutes < 60
            ? '${age.inMinutes} min ago'
            : age.inHours < 24
                ? '${age.inHours} h ago'
                : '${age.inDays} d ago';
    final conf = (fix.confidence * 100).round();
    return 'Estimate · $conf% confidence · ${fix.rangeDb} dB swing · $ageStr';
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.bearingDeg,
    required this.confidence,
    required this.color,
    required this.outlineColor,
  });

  final double bearingDeg;
  final double confidence;
  final Color color;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 4;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = outlineColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final tickPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 12; i++) {
      final angle = i * (math.pi / 6) - math.pi / 2;
      final long = i % 3 == 0;
      final inner = r - (long ? 8 : 4);
      canvas.drawLine(
        center + Offset(math.cos(angle) * r, math.sin(angle) * r),
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        tickPaint,
      );
    }

    final letterStyle = TextStyle(
      color: outlineColor,
      fontSize: r * 0.18,
      fontWeight: FontWeight.w600,
    );
    _paintLetter(canvas, 'N', center, r, -math.pi / 2, letterStyle);

    // Confidence cone behind the arrow — wider when we're less sure.
    final coneHalfWidth = math.pi / 6 + (1 - confidence) * (math.pi / 3);
    final bearingRad = (bearingDeg * math.pi / 180) - math.pi / 2;
    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: r * 0.85),
        bearingRad - coneHalfWidth,
        coneHalfWidth * 2,
        false,
      )
      ..close();
    canvas.drawPath(
      conePath,
      Paint()
        ..color = color.withValues(alpha: 0.10 + 0.18 * confidence)
        ..style = PaintingStyle.fill,
    );

    final tip = center + Offset(math.cos(bearingRad) * r * 0.82,
        math.sin(bearingRad) * r * 0.82);
    final back = math.pi - 0.45;
    final left = center +
        Offset(math.cos(bearingRad + back) * r * 0.35,
            math.sin(bearingRad + back) * r * 0.35);
    final right = center +
        Offset(math.cos(bearingRad - back) * r * 0.35,
            math.sin(bearingRad - back) * r * 0.35);
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
    canvas.drawCircle(center, 3, Paint()..color = color);
  }

  void _paintLetter(Canvas canvas, String letter, Offset center, double r,
      double angle, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: letter, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = center + Offset(math.cos(angle) * (r - 14), math.sin(angle) * (r - 14));
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.bearingDeg != bearingDeg ||
      old.confidence != confidence ||
      old.color != color ||
      old.outlineColor != outlineColor;
}
