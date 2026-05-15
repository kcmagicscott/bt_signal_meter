import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/bt_helpers.dart';

/// A circular RSSI gauge: shows the dBm number large in the middle,
/// arc colored by signal quality, and quality label below.
class SignalGauge extends StatelessWidget {
  const SignalGauge({
    super.key,
    required this.rssi,
    this.size = 220,
    this.isOffline = false,
  });

  final int rssi;
  final double size;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final quality = qualityFromRssi(rssi);
    final t = isOffline ? 0.0 : ((rssi + 100) / 60).clamp(0.0, 1.0);
    final color = isOffline ? Colors.grey.shade500 : quality.color;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(progress: t, color: color),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isOffline ? '—' : '$rssi',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                isOffline ? 'no signal' : 'dBm',
                style: TextStyle(
                  fontSize: size * 0.08,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isOffline ? 'OFFLINE' : quality.label,
                style: TextStyle(
                  fontSize: size * 0.09,
                  fontWeight: FontWeight.w500,
                  color: color,
                  letterSpacing: isOffline ? 1.5 : 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 12;
    final stroke = 14.0;

    final bgPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // 270° arc with the gap at the bottom, so the gauge reads like a speedometer.
    const startAngle = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      bgPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.color != color;
}

/// A small 4-bar signal-strength widget (like cell signal).
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.rssi,
    this.height = 18,
    this.isOffline = false,
  });

  final int rssi;
  final double height;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final quality = qualityFromRssi(rssi);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = !isOffline && i < quality.bars;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: height * 0.22,
          height: height * (0.3 + i * 0.23),
          decoration: BoxDecoration(
            color: filled ? quality.color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
