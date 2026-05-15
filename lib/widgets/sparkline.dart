import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/device_record.dart';
import '../utils/bt_helpers.dart';

/// A compact inline chart of the most recent RSSI samples.
/// The Y axis auto-scales to the actual min/max in the visible window so
/// small changes stay visible. Each segment of the line is colored from the
/// RSSI at that point, so the trace fades red→yellow→green along its length
/// instead of the whole line snapping between quality bands.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.samples,
    required this.color,
    this.windowSeconds = 30,
    this.maxWindowSeconds,
    this.height = 22,
    this.offlineAfter,
  });

  final List<RssiSample> samples;

  /// Color used for the endpoint dot and area fill tint. The line itself
  /// is colored per-segment from each sample's RSSI.
  final Color color;

  /// Minimum visible window. When [maxWindowSeconds] is null this is the
  /// fixed window.
  final int windowSeconds;

  /// If set, the visible window grows logarithmically with elapsed scan
  /// history, from [windowSeconds] up to this cap. The chart fills in
  /// quickly at first, then settles — so a long scan session shows more
  /// context without compressing the early seconds.
  final int? maxWindowSeconds;

  final double height;

  /// If set and the most recent sample is older than this, the painter draws
  /// a drop to the floor at the moment the signal was lost.
  final Duration? offlineAfter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          samples: samples,
          windowSeconds: windowSeconds,
          maxWindowSeconds: maxWindowSeconds,
          color: color,
          offlineAfter: offlineAfter,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.windowSeconds,
    required this.maxWindowSeconds,
    required this.color,
    this.offlineAfter,
  });

  final List<RssiSample> samples;
  final int windowSeconds;
  final int? maxWindowSeconds;
  final Color color;
  final Duration? offlineAfter;

  static const _minSpan = 20.0;
  static const _rangeHistoryFloor = 180;

  int _effectiveWindow(DateTime now) {
    final max = maxWindowSeconds;
    if (max == null || max <= windowSeconds || samples.isEmpty) {
      return windowSeconds;
    }
    final elapsed = now.difference(samples.first.time).inSeconds;
    if (elapsed <= windowSeconds) return windowSeconds;
    final t = (math.log(1 + elapsed) / math.log(1 + max)).clamp(0.0, 1.0);
    final grown = windowSeconds + (max - windowSeconds) * t;
    return grown.round().clamp(windowSeconds, max);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final now = DateTime.now();
    final windowSec = _effectiveWindow(now);
    final cutoff = now.subtract(Duration(seconds: windowSec));
    final recent =
        samples.where((s) => !s.time.isBefore(cutoff)).toList(growable: false);
    if (recent.length < 2) {
      final p = Paint()..color = color.withValues(alpha: 0.6);
      canvas.drawCircle(
        Offset(size.width - 2, size.height / 2),
        1.5,
        p,
      );
      return;
    }

    // Compute Y bounds over a longer history than the drawn window so a
    // single outlier doesn't reshape the chart. Floor at 3 minutes; grow
    // with the visible window when it has expanded.
    final rangeSeconds = math.max(_rangeHistoryFloor, windowSec * 2);
    final rangeCutoff = now.subtract(Duration(seconds: rangeSeconds));
    final rangeSet = samples
        .where((s) => !s.time.isBefore(rangeCutoff))
        .map((s) => s.rssi)
        .toList(growable: false);
    var minV = rangeSet.reduce((a, b) => a < b ? a : b).toDouble();
    var maxV = rangeSet.reduce((a, b) => a > b ? a : b).toDouble();
    minV = (minV / 5).floor() * 5.0;
    maxV = (maxV / 5).ceil() * 5.0;
    if (maxV - minV < _minSpan) {
      final mid = (maxV + minV) / 2;
      minV = (mid - _minSpan / 2);
      maxV = (mid + _minSpan / 2);
      minV = (minV / 5).floor() * 5.0;
      maxV = (maxV / 5).ceil() * 5.0;
    }
    final range = maxV - minV;
    final windowMs = windowSec * 1000.0;

    final pts = <Offset>[];
    for (final s in recent) {
      final msAgo = now.difference(s.time).inMilliseconds.toDouble();
      final x = size.width * (1 - (msAgo / windowMs).clamp(0.0, 1.0));
      final y = size.height * (1 - (s.rssi - minV) / range);
      pts.add(Offset(x, y));
    }

    final fill = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(pts.last.dx, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );

    final segPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < recent.length; i++) {
      final midRssi = ((recent[i - 1].rssi + recent[i].rssi) / 2).round();
      segPaint.color = colorForRssi(midRssi);
      canvas.drawLine(pts[i - 1], pts[i], segPaint);
    }

    final lastX = pts.last.dx;
    final lastY = pts.last.dy;
    final timeSinceLast = now.difference(recent.last.time);
    final isOffline = offlineAfter != null && timeSinceLast >= offlineAfter!;

    if (isOffline) {
      final dropPaint = Paint()
        ..color = Colors.grey.shade500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(lastX, lastY),
        Offset(lastX, size.height - 1),
        dropPaint,
      );
      canvas.drawLine(
        Offset(lastX, size.height - 1),
        Offset(size.width, size.height - 1),
        dropPaint,
      );
      canvas.drawCircle(
        Offset(lastX, lastY),
        2.0,
        Paint()..color = Colors.grey.shade500,
      );
    } else {
      canvas.drawCircle(Offset(lastX, lastY), 2.0, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.samples != samples ||
      old.color != color ||
      old.windowSeconds != windowSeconds ||
      old.maxWindowSeconds != maxWindowSeconds ||
      old.offlineAfter != offlineAfter;
}
