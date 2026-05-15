import 'package:flutter/material.dart';

import '../models/device_record.dart';

/// Live "warmer/colder" indicator. Reads the device's recent RSSI delta and
/// shows where you're heading on a cold→warm bar. Useful when walking
/// around hunting for a device — easier to read at a glance than the
/// numeric gauge.
class HotColdIndicator extends StatelessWidget {
  const HotColdIndicator({
    super.key,
    required this.deviceRecord,
    this.window = const Duration(seconds: 8),
  });

  final DeviceRecord deviceRecord;
  final Duration window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = deviceRecord.trendDeltaDb(window: window);
    // 8 dB swing across the window saturates the indicator.
    final t = (delta / 8.0).clamp(-1.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: CustomPaint(
              painter: _HotColdPainter(
                t: t,
                outline: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _label(delta),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _label(double delta) {
    if (delta.abs() < 0.6) {
      return 'Steady · ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} dB';
    }
    final qual = delta.abs() >= 4
        ? 'much '
        : delta.abs() >= 2
            ? ''
            : 'slightly ';
    return delta > 0
        ? 'Getting ${qual}warmer · +${delta.toStringAsFixed(1)} dB'
        : 'Getting ${qual}colder · ${delta.toStringAsFixed(1)} dB';
  }
}

class _HotColdPainter extends CustomPainter {
  _HotColdPainter({required this.t, required this.outline});

  /// Indicator position: -1 (cold) .. 0 (steady) .. +1 (hot).
  final double t;
  final Color outline;

  static const _coldEnd = Color(0xFF1E88E5);
  static const _coolMid = Color(0xFF66BB6A);
  static const _warmMid = Color(0xFFFFA726);
  static const _hotEnd = Color(0xFFE53935);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final rect = Rect.fromLTWH(0, h * 0.25, w, h * 0.5);
    final r = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.25));
    final shader = const LinearGradient(
      colors: [_coldEnd, _coolMid, _warmMid, _hotEnd],
    ).createShader(rect);
    canvas.drawRRect(r, Paint()..shader = shader);
    canvas.drawRRect(
      r,
      Paint()
        ..color = outline.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final cx = (t + 1) / 2 * w;
    final cy = h * 0.5;
    canvas.drawCircle(Offset(cx, cy), h * 0.45, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      h * 0.45,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HotColdPainter old) =>
      old.t != t || old.outline != outline;
}
