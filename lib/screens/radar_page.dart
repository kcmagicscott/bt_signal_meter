import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/device_record.dart';
import '../scanner_state.dart';
import '../services/app_settings.dart';
import '../services/device_memory.dart';
import '../utils/bt_helpers.dart';
import 'device_detail_page.dart';

class RadarPage extends StatefulWidget {
  const RadarPage({super.key});

  @override
  State<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends State<RadarPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  late final Listenable _appState = Listenable.merge([
    ScannerState.instance,
    DeviceMemory.instance,
    AppSettings.instance,
  ]);
  List<_PlacedDevice> _placed = const [];

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _appState.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sweep.dispose();
    _appState.removeListener(_onChange);
    super.dispose();
  }

  /// Stable angle in radians derived from the device address.
  double _angleFor(String id) {
    var h = 2166136261;
    for (final c in id.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return (h % 360) * (math.pi / 180.0);
  }

  void _onTap(TapDownDetails details, Size canvasSize) {
    final touch = details.localPosition;
    for (final p in _placed) {
      if ((p.position - touch).distance <= p.hitRadius) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailPage(deviceId: p.id),
          ),
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ScannerState.instance;
    final mem = DeviceMemory.instance;
    final smoothing = AppSettings.instance.smoothingWindow;
    final devices = state.visibleDevices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar'),
        actions: [
          IconButton(
            tooltip: state.isScanning ? 'Stop scan' : 'Start scan',
            icon: Icon(state.isScanning ? Icons.stop : Icons.search),
            onPressed: () => state.isScanning
                ? state.stopScan()
                : state.startScan(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapDown: (d) => _onTap(d, size),
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (ctx, _) {
                final placed = <_PlacedDevice>[];
                final painter = _RadarPainter(
                  devices: devices,
                  smoothing: smoothing,
                  sweepAngle: _sweep.value * 2 * math.pi,
                  labelFor: (id) => mem.labelFor(id),
                  isFavorite: (id) => mem.isFavorite(id),
                  angleFor: _angleFor,
                  recordPlacement: placed.add,
                );
                _placed = placed;
                return CustomPaint(
                  size: size,
                  painter: painter,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: devices.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.list),
              label: Text('${devices.length} list view'),
            ),
    );
  }
}

class _PlacedDevice {
  _PlacedDevice(this.id, this.position, this.hitRadius);
  final DeviceIdentifier id;
  final Offset position;
  final double hitRadius;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.devices,
    required this.smoothing,
    required this.sweepAngle,
    required this.labelFor,
    required this.isFavorite,
    required this.angleFor,
    required this.recordPlacement,
  });

  final List<DeviceRecord> devices;
  final int smoothing;
  final double sweepAngle;
  final String? Function(String) labelFor;
  final bool Function(String) isFavorite;
  final double Function(String) angleFor;
  final void Function(_PlacedDevice) recordPlacement;

  // RSSI range mapped to radar radius. Stronger -> closer to center.
  static const int rssiMin = -100;
  static const int rssiMax = -30;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - 16;

    _paintBackground(canvas, size);
    _paintRings(canvas, center, maxR);
    _paintSpokes(canvas, center, maxR);
    _paintSweep(canvas, center, maxR);
    _paintCenter(canvas, center);
    _paintDevices(canvas, center, maxR);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [Color(0xFF0E1F2A), Color(0xFF050A10)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintRings(Canvas canvas, Offset center, double maxR) {
    final ring = Paint()
      ..color = const Color(0xFF1FA86A).withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const segments = 4;
    for (var i = 1; i <= segments; i++) {
      final r = maxR * (i / segments);
      canvas.drawCircle(center, r, ring);
      final rssiAtRing =
          (rssiMax - (rssiMax - rssiMin) * (i / segments)).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$rssiAtRing dBm',
          style: TextStyle(
            color: const Color(0xFF1FA86A).withValues(alpha: 0.55),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(center.dx + 4, center.dy - r - tp.height - 1),
      );
    }
  }

  void _paintSpokes(Canvas canvas, Offset center, double maxR) {
    final spoke = Paint()
      ..color = const Color(0xFF1FA86A).withValues(alpha: 0.15)
      ..strokeWidth = 0.6;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        center,
        center + Offset(math.cos(a), math.sin(a)) * maxR,
        spoke,
      );
    }
  }

  void _paintSweep(Canvas canvas, Offset center, double maxR) {
    final rect = Rect.fromCircle(center: center, radius: maxR);
    final shader = SweepGradient(
      colors: const [
        Color(0x00000000),
        Color(0x222BBA82),
        Color(0xAA2BBA82),
      ],
      stops: const [0.0, 0.85, 1.0],
      startAngle: sweepAngle - math.pi / 4,
      endAngle: sweepAngle,
      transform: GradientRotation(0),
    ).createShader(rect);
    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      rect,
      sweepAngle - math.pi / 4,
      math.pi / 4,
      true,
      paint,
    );
  }

  void _paintCenter(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      6,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = const Color(0xFF1FA86A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintDevices(Canvas canvas, Offset center, double maxR) {
    for (final d in devices) {
      final r = d.smoothedRssi(smoothing);
      final t = ((r - rssiMin) / (rssiMax - rssiMin)).clamp(0.0, 1.0);
      // strong (close to 0) -> small radius; weak -> outer edge.
      final radius = maxR * (1 - t);
      final angle = angleFor(d.id.str);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final quality = qualityFromRssi(r);

      final age =
          DateTime.now().difference(d.lastSeen).inMilliseconds.toDouble();
      final freshness = (1 - (age / 4000)).clamp(0.0, 1.0);
      final glowRadius = 8.0 + 6.0 * freshness;

      final glow = Paint()
        ..color = quality.color.withValues(alpha: 0.18 * freshness)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, glowRadius, glow);

      final dot = Paint()
        ..color = quality.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 4.5, dot);

      if (isFavorite(d.id.str)) {
        final star = Paint()
          ..color = Colors.amber.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(pos, 7, star);
      }

      final name =
          labelFor(d.id.str) ?? (d.localName?.isNotEmpty == true ? d.name : '');
      final shortName = name.isEmpty
          ? d.id.str.substring(d.id.str.length - 5)
          : (name.length > 14 ? '${name.substring(0, 13)}…' : name);
      final tp = TextPainter(
        text: TextSpan(
          text: shortName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pos.dx - tp.width / 2, pos.dy + 6),
      );

      recordPlacement(_PlacedDevice(d.id, pos, 14));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweepAngle != sweepAngle ||
      old.devices != devices ||
      old.smoothing != smoothing;
}
