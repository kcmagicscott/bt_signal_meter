import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/bt_helpers.dart';

class GattExplorerPage extends StatefulWidget {
  const GattExplorerPage({
    super.key,
    required this.deviceId,
    required this.displayName,
  });

  final DeviceIdentifier deviceId;
  final String displayName;

  @override
  State<GattExplorerPage> createState() => _GattExplorerPageState();
}

class _GattExplorerPageState extends State<GattExplorerPage> {
  late final BluetoothDevice _device =
      BluetoothDevice.fromId(widget.deviceId.str);
  BluetoothConnectionState _state = BluetoothConnectionState.disconnected;
  StreamSubscription<BluetoothConnectionState>? _stateSub;

  List<BluetoothService> _services = const [];
  bool _discovering = false;
  String? _errorMessage;

  // Per-characteristic latest values and notify state.
  final Map<String, List<int>> _values = {};
  final Map<String, StreamSubscription<List<int>>> _notifySubs = {};
  final Set<String> _notifying = {};

  @override
  void initState() {
    super.initState();
    _stateSub = _device.connectionState.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s == BluetoothConnectionState.connected) {
        _discoverAndPrime();
      } else if (s == BluetoothConnectionState.disconnected) {
        _services = const [];
        _values.clear();
        _notifying.clear();
      }
    });
    _connect();
  }

  @override
  void dispose() {
    for (final sub in _notifySubs.values) {
      sub.cancel();
    }
    _stateSub?.cancel();
    _device.disconnect().catchError((_) {});
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _errorMessage = null);
    try {
      await _device.connect(
        timeout: const Duration(seconds: 12),
        license: License.free,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Connect failed: $e');
    }
  }

  Future<void> _discoverAndPrime() async {
    setState(() => _discovering = true);
    try {
      final services = await _device.discoverServices();
      if (!mounted) return;
      setState(() {
        _services = services;
        _discovering = false;
      });
      // Auto-read interesting readable characteristics so the user gets
      // immediate signal (battery %, model, firmware, etc.).
      for (final svc in services) {
        for (final c in svc.characteristics) {
          final knownName = characteristicNameFor(c.uuid.str);
          if (knownName != null && c.properties.read) {
            _readCharacteristic(c, silent: true);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _errorMessage = 'Service discovery failed: $e';
      });
    }
  }

  Future<void> _readCharacteristic(
    BluetoothCharacteristic c, {
    bool silent = false,
  }) async {
    try {
      final value = await c.read();
      if (!mounted) return;
      setState(() {
        _values[c.uuid.str] = value;
      });
    } catch (e) {
      if (silent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Read failed: $e')),
      );
    }
  }

  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    final key = c.uuid.str;
    final isOn = _notifying.contains(key);
    try {
      await c.setNotifyValue(!isOn);
      if (!mounted) return;
      if (isOn) {
        await _notifySubs.remove(key)?.cancel();
        setState(() => _notifying.remove(key));
      } else {
        _notifySubs[key] = c.lastValueStream.listen((v) {
          if (mounted) setState(() => _values[key] = v);
        });
        setState(() => _notifying.add(key));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Subscribe failed: $e')),
      );
    }
  }

  Future<void> _writeCharacteristic(BluetoothCharacteristic c) async {
    final controller = TextEditingController();
    final hex = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Hex bytes, e.g. 01 02 0A',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Space-separated hex pairs. Be careful: a wrong value can confuse '
              'the device.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Write'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (hex == null || hex.isEmpty || !mounted) return;
    try {
      final bytes = hex
          .replaceAll(RegExp(r'[\s,;]'), '')
          .split('')
          .fold<List<String>>([], (acc, ch) {
            if (acc.isEmpty || acc.last.length == 2) {
              acc.add(ch);
            } else {
              acc[acc.length - 1] = acc.last + ch;
            }
            return acc;
          })
          .map((s) => int.parse(s, radix: 16))
          .toList();
      await c.write(bytes, withoutResponse: !c.properties.write);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wrote ${bytes.length} bytes')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Write failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          if (_state == BluetoothConnectionState.connected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: () => _device.disconnect(),
            )
          else
            IconButton(
              tooltip: 'Connect',
              icon: const Icon(Icons.bluetooth),
              onPressed: _connect,
            ),
        ],
      ),
      body: Column(
        children: [
          _StatusStrip(state: _state, errorMessage: _errorMessage),
          if (_discovering)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (_state == BluetoothConnectionState.connected &&
              _services.isNotEmpty)
            _QuickInfoSection(values: _values, services: _services),
          Expanded(
            child: _services.isEmpty
                ? _EmptyMessage(state: _state, errorMessage: _errorMessage)
                : ListView(
                    children: _services
                        .map((s) => _ServiceTile(
                              service: s,
                              values: _values,
                              notifying: _notifying,
                              onRead: _readCharacteristic,
                              onToggleNotify: _toggleNotify,
                              onWrite: _writeCharacteristic,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.state, this.errorMessage});
  final BluetoothConnectionState state;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    String text;
    IconData icon;
    switch (state) {
      case BluetoothConnectionState.connected:
        color = const Color(0xFF2E7D32);
        text = 'Connected';
        icon = Icons.bluetooth_connected;
        break;
      case BluetoothConnectionState.disconnected:
        color = Colors.grey.shade600;
        text = 'Disconnected';
        icon = Icons.bluetooth_disabled;
        break;
      default:
        color = const Color(0xFFFFA726);
        text = 'Connecting…';
        icon = Icons.bluetooth_searching;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (errorMessage != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.state, this.errorMessage});
  final BluetoothConnectionState state;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              state == BluetoothConnectionState.connected
                  ? 'No services discovered yet'
                  : 'Not connected',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ??
                  'Many BLE devices (beacons, AirTags, anonymous '
                      'advertisers) can\'t be connected to — they only broadcast.',
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

class _QuickInfoSection extends StatelessWidget {
  const _QuickInfoSection(
      {required this.values, required this.services});
  final Map<String, List<int>> values;
  final List<BluetoothService> services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final svc in services) {
      for (final c in svc.characteristics) {
        final name = characteristicNameFor(c.uuid.str);
        if (name == null) continue;
        final raw = values[c.uuid.str];
        if (raw == null) continue;
        final decoded = decodeCharacteristicValue(c.uuid.str, raw) ?? '—';
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Text(
                  decoded,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick info',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.values,
    required this.notifying,
    required this.onRead,
    required this.onToggleNotify,
    required this.onWrite,
  });
  final BluetoothService service;
  final Map<String, List<int>> values;
  final Set<String> notifying;
  final void Function(BluetoothCharacteristic) onRead;
  final void Function(BluetoothCharacteristic) onToggleNotify;
  final void Function(BluetoothCharacteristic) onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final knownName = serviceNameFor(service.uuid.str) ?? 'Service';
    return ExpansionTile(
      title: Text(knownName, style: theme.textTheme.titleSmall),
      subtitle: Text(
        service.uuid.str,
        style: theme.textTheme.bodySmall,
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: service.characteristics
          .map((c) => _CharacteristicRow(
                characteristic: c,
                value: values[c.uuid.str],
                isNotifying: notifying.contains(c.uuid.str),
                onRead: () => onRead(c),
                onToggleNotify: () => onToggleNotify(c),
                onWrite: () => onWrite(c),
              ))
          .toList(),
    );
  }
}

class _CharacteristicRow extends StatelessWidget {
  const _CharacteristicRow({
    required this.characteristic,
    required this.value,
    required this.isNotifying,
    required this.onRead,
    required this.onToggleNotify,
    required this.onWrite,
  });
  final BluetoothCharacteristic characteristic;
  final List<int>? value;
  final bool isNotifying;
  final VoidCallback onRead;
  final VoidCallback onToggleNotify;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final knownName = characteristicNameFor(characteristic.uuid.str);
    final props = characteristic.properties;
    final propChips = <String>[
      if (props.read) 'R',
      if (props.write) 'W',
      if (props.writeWithoutResponse) 'WnR',
      if (props.notify) 'N',
      if (props.indicate) 'I',
    ];
    final decoded = value != null
        ? decodeCharacteristicValue(characteristic.uuid.str, value!)
        : null;
    final hex = value
        ?.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  knownName ?? 'Characteristic',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ...propChips.map((p) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )),
            ],
          ),
          Text(
            characteristic.uuid.str,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          if (value != null) ...[
            const SizedBox(height: 4),
            if (decoded != null)
              Text(
                decoded,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            Text(
              hex!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace', color: Colors.grey),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (props.read)
                TextButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Read'),
                  onPressed: onRead,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (props.write || props.writeWithoutResponse)
                TextButton.icon(
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Write'),
                  onPressed: onWrite,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (props.notify || props.indicate)
                TextButton.icon(
                  icon: Icon(
                    isNotifying
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    size: 16,
                  ),
                  label: Text(isNotifying ? 'Subscribed' : 'Subscribe'),
                  onPressed: onToggleNotify,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
