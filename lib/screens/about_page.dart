import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final versionString = _info == null
        ? 'Version …'
        : 'Version ${_info!.version} (build ${_info!.buildNumber})';
    return Scaffold(
      appBar: AppBar(title: const Text('About & Help')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('BT Signal Meter',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(versionString, style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          const _Section(
            title: 'What it does',
            body:
                'This app scans for Bluetooth Low Energy (BLE) devices around you '
                'and tracks how strong each one\'s signal is — both right now and '
                'over time. Tap any device to see a live chart of its signal '
                'strength and use "Find it" mode to locate it by feel.',
          ),
          const _Section(
            title: 'Finding lost things',
            body:
                'Tap a device, then tap "Find it mode". The phone will vibrate '
                'faster as you get closer to it and slower as you walk away. '
                'Works for AirTags, Tiles, headphones, smart speakers — anything '
                'that broadcasts Bluetooth. The signal can pass through walls, '
                'so it\'s a guide, not a metal detector.',
          ),
          const _Section(
            title: 'What is RSSI?',
            body:
                'RSSI (Received Signal Strength Indicator) is measured in dBm and '
                'is always a negative number. The closer to zero, the stronger the '
                'signal:\n\n'
                '  •  −30 to −55 dBm  →  Excellent (very close)\n'
                '  •  −55 to −70 dBm  →  Good\n'
                '  •  −70 to −85 dBm  →  Fair\n'
                '  •  −85 to −100 dBm →  Poor\n'
                '  •  Below −100 dBm  →  Very poor / out of range',
          ),
          const _Section(
            title: 'Distance estimates',
            body:
                'The distance shown for each device is a rough guess based on '
                'signal strength and a free-space path-loss formula. Real-world '
                'distance varies a lot with walls, bodies, interference, and the '
                'broadcasting device\'s antenna. Treat it as ±50% accurate at '
                'best — useful for "warmer/colder" finding, not GPS precision.',
          ),
          const _Section(
            title: 'Labels and favorites',
            body:
                'Tap the pencil icon on a device to give it your own label '
                '(e.g. "Office speakers"). Tap the star to favorite it — '
                'favorites always sort to the top of the list. Labels and '
                'favorites are saved locally on this phone.',
          ),
          const _Section(
            title: 'Why some devices have no name',
            body:
                'Many BLE devices either don\'t broadcast a friendly name or '
                'change their address regularly for privacy (Apple, Google, '
                'Microsoft all do this). The Bluetooth address you see may '
                'change every 15 minutes for the same device, which also means '
                'a saved label may not follow it.',
          ),
          const _Section(
            title: 'Permissions',
            body:
                'The app needs Bluetooth scan and connect permissions. On older '
                'Android (11 and below), it also needs location permission '
                'because Google historically tied BLE scanning to location — even '
                'though this app doesn\'t use your location.',
          ),
          const _Section(
            title: 'Privacy',
            body:
                'Nothing leaves your device. All scanning, history, labels, and '
                'CSV exports stay local. There is no analytics, no cloud sync, no '
                'account, no ads.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
