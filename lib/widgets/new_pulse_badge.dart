import 'package:flutter/material.dart';

/// "NEW" badge that gently pulses while the device is freshly discovered,
/// then settles into a static badge with an age suffix ("NEW · 4m") after
/// 90 seconds. Used inside scanner row tiles.
class NewPulseBadge extends StatefulWidget {
  const NewPulseBadge({super.key, this.age});

  final Duration? age;

  @override
  State<NewPulseBadge> createState() => _NewPulseBadgeState();
}

class _NewPulseBadgeState extends State<NewPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _ageLabel(Duration? d) {
    if (d == null) return 'NEW';
    if (d.inMinutes < 1) return 'NEW';
    return 'NEW · ${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final showPulse = widget.age == null || widget.age!.inSeconds < 90;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.redAccent.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _ageLabel(widget.age),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
    if (!showPulse) return badge;
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.08).animate(_ctrl),
      child: badge,
    );
  }
}
