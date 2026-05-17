import 'package:flutter/material.dart';

import '../utils/bt_helpers.dart';

/// Horizontal strip of manufacturer filter chips above the device list.
/// Hidden when fewer than two distinct manufacturers are visible (chip
/// strip with one option isn't useful).
class ManufacturerFilterStrip extends StatelessWidget {
  const ManufacturerFilterStrip({
    super.key,
    required this.present,
    required this.selected,
    required this.onSelect,
    required this.countFor,
  });

  final Set<int> present;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final int Function(int) countFor;

  @override
  Widget build(BuildContext context) {
    if (present.length < 2) return const SizedBox.shrink();

    // Sort: known manufacturers first (by descending count), unknown bucket last.
    final ids = present.toList()
      ..sort((a, b) {
        if (a == -1) return 1;
        if (b == -1) return -1;
        return countFor(b).compareTo(countFor(a));
      });

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: ids.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return FilterChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            );
          }
          final id = ids[i - 1];
          final name = id == -1
              ? 'Unknown'
              : (manufacturerNameFor(id) ??
                  '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}');
          final count = countFor(id);
          return FilterChip(
            label: Text('$name · $count'),
            selected: selected == id,
            onSelected: (_) => onSelect(selected == id ? null : id),
          );
        },
      ),
    );
  }
}

/// Search box plus the two list-filter toggles (favorites-only, hide-unnamed).
class ScannerSearchBar extends StatelessWidget {
  const ScannerSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hideUnnamed,
    required this.onToggleUnnamed,
    required this.favoritesOnly,
    required this.onToggleFavorites,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hideUnnamed;
  final VoidCallback onToggleUnnamed;
  final bool favoritesOnly;
  final VoidCallback onToggleFavorites;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or address',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip:
                favoritesOnly ? 'Show all devices' : 'Show favorites only',
            onPressed: onToggleFavorites,
            icon: Icon(favoritesOnly ? Icons.star : Icons.star_border),
            color: favoritesOnly ? Colors.amber.shade700 : null,
          ),
          IconButton(
            tooltip:
                hideUnnamed ? 'Show unnamed devices' : 'Hide unnamed devices',
            onPressed: onToggleUnnamed,
            icon: Icon(hideUnnamed ? Icons.label : Icons.label_off_outlined),
            color: hideUnnamed ? Theme.of(context).colorScheme.primary : null,
          ),
        ],
      ),
    );
  }
}

/// Single-line status strip between the search bar and the device list:
/// shows scan state, active-device count, and shown-of-total.
class SummaryBar extends StatelessWidget {
  const SummaryBar({
    super.key,
    required this.total,
    required this.shown,
    required this.active,
    required this.scanning,
  });

  final int total;
  final int shown;
  final int active;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          if (scanning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.bluetooth_disabled,
                size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            scanning ? 'Scanning…' : 'Idle',
            style: theme.textTheme.bodySmall,
          ),
          if (scanning) ...[
            const SizedBox(width: 12),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    active > 0 ? Colors.green : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 4),
            Text('$active active', style: theme.textTheme.bodySmall),
          ],
          const Spacer(),
          Text(
            shown == total ? '$total devices' : '$shown of $total devices',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown when the device list is empty. Distinguishes three
/// cases: actively scanning (waiting for adverts), idle (haven't pressed
/// Scan yet), and favorites-filter on with no favorites in range.
class ScannerEmptyState extends StatelessWidget {
  const ScannerEmptyState({
    super.key,
    required this.scanning,
    this.favoritesOnly = false,
  });

  final bool scanning;
  final bool favoritesOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData icon;
    final String title;
    final String body;
    if (favoritesOnly) {
      icon = Icons.star_border;
      title = 'No favorites in range';
      body = 'Tap the star icon again to show all devices, '
          'or open a device and star it to add it here.';
    } else if (scanning) {
      icon = Icons.bluetooth_searching;
      title = 'Listening…';
      body = 'Nearby Bluetooth devices will appear here as they advertise.';
    } else {
      icon = Icons.bluetooth_outlined;
      title = 'Tap Scan to start';
      body = 'This app finds Bluetooth Low Energy devices around you '
          'and tracks their signal strength.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
