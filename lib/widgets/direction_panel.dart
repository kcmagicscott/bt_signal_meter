import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/direction_fix.dart';
import 'compass_dial.dart';

/// The "direction" section of the device detail page. Shows one of two
/// states:
///   - no fix yet → an inviting animated "Find the direction" button
///   - have a fix → the saved compass dial that rotates with the phone,
///     plus a "Sweep again" action to re-run the finder
class DirectionPanel extends StatelessWidget {
  const DirectionPanel({super.key, required this.fix, required this.onSweep});

  final DirectionFix? fix;
  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fix;
    if (f == null) {
      return _SweepStartButton(onPressed: onSweep);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Text('Estimated direction', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          _LiveCompassDial(fix: f, size: 150),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Sweep again'),
            onPressed: onSweep,
          ),
        ],
      ),
    );
  }
}

/// CompassDial that subscribes to the device's magnetometer and rotates
/// dynamically so the bearing arrow always points at the target device,
/// not just at the absolute compass bearing. Lets the saved-fix view
/// behave like a "follow me" pointer even after the sweep finalized.
class _LiveCompassDial extends StatefulWidget {
  const _LiveCompassDial({required this.fix, this.size = 140});
  final DirectionFix fix;
  final double size;

  @override
  State<_LiveCompassDial> createState() => _LiveCompassDialState();
}

class _LiveCompassDialState extends State<_LiveCompassDial> {
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;

  @override
  void initState() {
    super.initState();
    final stream = FlutterCompass.events;
    if (stream != null) {
      _sub = stream.listen((e) {
        if (!mounted) return;
        final h = e.heading;
        if (h == null) return;
        setState(() => _heading = h < 0 ? h + 360 : h);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompassDial(
      fix: widget.fix,
      deviceHeadingDeg: _heading,
      size: widget.size,
    );
  }
}

class _SweepStartButton extends StatefulWidget {
  const _SweepStartButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_SweepStartButton> createState() => _SweepStartButtonState();
}

class _SweepStartButtonState extends State<_SweepStartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    return CustomPaint(
                      painter: _StartCompassPainter(
                        angleRad: _ctrl.value * 2 * math.pi,
                        primary: theme.colorScheme.onTertiaryContainer,
                        outline: theme.colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.5),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Find the direction',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Spin in a circle — we\'ll point you at it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCompassPainter extends CustomPainter {
  _StartCompassPainter({
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
    final r = math.min(size.width, size.height) / 2 - 1;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    for (var i = 0; i < 4; i++) {
      final a = i * (math.pi / 2) - math.pi / 2;
      canvas.drawLine(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        center + Offset(math.cos(a) * (r - 3), math.sin(a) * (r - 3)),
        Paint()
          ..color = outline
          ..strokeWidth = 1.4,
      );
    }
    final tipA = angleRad - math.pi / 2;
    final tip = center +
        Offset(math.cos(tipA) * r * 0.75, math.sin(tipA) * r * 0.75);
    final back = math.pi - 0.45;
    final left = center +
        Offset(math.cos(tipA + back) * r * 0.28,
            math.sin(tipA + back) * r * 0.28);
    final right = center +
        Offset(math.cos(tipA - back) * r * 0.28,
            math.sin(tipA - back) * r * 0.28);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = primary,
    );
    canvas.drawCircle(center, 2.4, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(_StartCompassPainter old) =>
      old.angleRad != angleRad ||
      old.primary != primary ||
      old.outline != outline;
}
