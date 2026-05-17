import 'package:flutter/material.dart';

import '../models/device_record.dart';
import '../services/app_settings.dart';
import 'device_list_tile.dart';

/// Stack-based scrolling list where each device tile is in an
/// [AnimatedPositioned]. When the sort order changes (or a new device
/// pushes one above another), tiles physically slide between their old
/// and new Y positions instead of cross-fading in place. Each tile's
/// height is measured on first layout so variable-content rows still
/// stack correctly.
///
/// Falls back to a virtualized [ListView] when the device count crosses
/// [_virtualizeThreshold] — the stack approach keeps every tile in the
/// widget tree and gets too heavy past ~80 rows.
class AnimatedDeviceList extends StatefulWidget {
  const AnimatedDeviceList({
    super.key,
    required this.devices,
    required this.onTap,
    required this.onLongPress,
  });

  final List<DeviceRecord> devices;
  final void Function(DeviceRecord) onTap;
  final void Function(DeviceRecord) onLongPress;

  @override
  State<AnimatedDeviceList> createState() => _AnimatedDeviceListState();
}

class _AnimatedDeviceListState extends State<AnimatedDeviceList> {
  static const Duration _slideDuration = Duration(milliseconds: 380);
  static const Curve _slideCurve = Curves.easeOutCubic;
  static const int _virtualizeThreshold = 80;

  final Map<String, double> _heights = {};
  Set<String> _knownIds = const {};
  DensityMode _lastDensity = DensityMode.comfortable;

  double _estimatedHeightFor(DensityMode m) => switch (m) {
        DensityMode.comfortable => 124.0,
        DensityMode.compact => 64.0,
        DensityMode.dense => 36.0,
      };

  double _topFor(int index, double estimated) {
    var top = 0.0;
    for (var i = 0; i < index; i++) {
      top += _heights[widget.devices[i].id.str] ?? estimated;
    }
    return top;
  }

  double _totalHeight(double estimated) {
    var h = 0.0;
    for (final d in widget.devices) {
      h += _heights[d.id.str] ?? estimated;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _knownIds = widget.devices.map((d) => d.id.str).toSet();
    _lastDensity = AppSettings.instance.densityMode;
  }

  @override
  void didUpdateWidget(AnimatedDeviceList old) {
    super.didUpdateWidget(old);
    final newIds = widget.devices.map((d) => d.id.str).toSet();
    if (newIds.length != _knownIds.length ||
        !newIds.containsAll(_knownIds)) {
      _heights.removeWhere((id, _) => !newIds.contains(id));
      _knownIds = newIds;
    }
    final density = AppSettings.instance.densityMode;
    if (density != _lastDensity) {
      _heights.clear();
      _lastDensity = density;
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = AppSettings.instance.densityMode;
    final estimated = _estimatedHeightFor(density);

    if (widget.devices.length > _virtualizeThreshold) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.devices.length,
        itemBuilder: (_, i) {
          final d = widget.devices[i];
          return DeviceListTile(
            key: ValueKey(d.id),
            record: d,
            onTap: () => widget.onTap(d),
            onLongPress: () => widget.onLongPress(d),
          );
        },
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: _totalHeight(estimated) + 8,
        child: Stack(
          children: [
            for (var i = 0; i < widget.devices.length; i++)
              AnimatedPositioned(
                key: ValueKey(widget.devices[i].id),
                duration: _slideDuration,
                curve: _slideCurve,
                top: _topFor(i, estimated),
                left: 0,
                right: 0,
                child: _MeasuredTile(
                  onHeight: (h) {
                    final id = widget.devices[i].id.str;
                    if ((_heights[id] ?? -1) != h) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _heights[id] = h);
                      });
                    }
                  },
                  child: DeviceListTile(
                    record: widget.devices[i],
                    onTap: () => widget.onTap(widget.devices[i]),
                    onLongPress: () => widget.onLongPress(widget.devices[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reports its child's rendered height back to the parent via [onHeight]
/// after each layout pass. Lets the parent stack position the next tile
/// correctly without hard-coding row heights.
class _MeasuredTile extends StatefulWidget {
  const _MeasuredTile({required this.child, required this.onHeight});
  final Widget child;
  final ValueChanged<double> onHeight;

  @override
  State<_MeasuredTile> createState() => _MeasuredTileState();
}

class _MeasuredTileState extends State<_MeasuredTile> {
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      final h = box?.size.height;
      if (h != null && h > 0) widget.onHeight(h);
    });
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
