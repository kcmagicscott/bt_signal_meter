import 'package:flutter/material.dart';

import 'scanner_state.dart';
import 'screens/app_shell.dart';
import 'services/app_settings.dart';
import 'services/bonded_device_registry.dart';
import 'services/device_memory.dart';
import 'services/gatt_identifier.dart';
import 'services/new_device_monitor.dart';
import 'services/watch_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    DeviceMemory.instance.load(),
    AppSettings.instance.load(),
    NewDeviceMonitor.instance.load(),
    WatchMode.instance.load(),
    ScannerState.instance.load(),
    GattIdentifier.instance.load(),
  ]);
  BondedDeviceRegistry.instance.refresh();
  runApp(const BtSignalApp());
}

class BtSignalApp extends StatelessWidget {
  const BtSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Signal Meter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
      ),
      home: const AppShell(),
    );
  }
}
