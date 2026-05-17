# bt_signal_meter

A Bluetooth Low Energy scanner and signal meter for Android. Built with
Flutter on top of `flutter_blue_plus`.

## What it does

- **Live scan** of nearby BLE advertisers with per-device RSSI, manufacturer,
  beacon parsing (iBeacon / Eddystone), and an inline sparkline tinted by
  signal quality.
- **Three density modes** (comfortable / compact / dense) cycled from the
  AppBar — comfortable shows full tiles with chips and a sparkline; dense
  packs ~12 devices per screen for crowded environments.
- **Search, filter, and sort**: by name/address/label, by manufacturer
  chip, by favorite, by signal strength or last-seen, with an option to
  hide unnamed devices.
- **Device detail page** with a smoothed signal gauge, full-history RSSI
  chart, distance estimate (with per-device 1 m calibration), Find-It
  haptic+audio mode, and a list of advertised services.
- **Sweep-to-find / pointer mode**: rotate-the-phone direction estimation
  using body shadowing of the BLE signal. The continuous live pointer
  shows where the device is relative to your phone; the screen lights up
  green when you're aimed at it. Sub-bucket parabolic interpolation +
  per-bucket median + velocity gating + lost-signal rejection layered in
  for accuracy. Not as precise as Apple's UWB arrow — see *limits* below.
- **GATT explorer** — connect, list services / characteristics, read
  values, decode standard characteristics.
- **Identify** a single unknown device by reading its GATT Device
  Information service.
- **Session recording** — start/stop a scan session, browse devices seen
  during it, export CSV.
- **New-device monitoring** with adjustable sensitivity; freshly-seen
  devices get a pulsing "NEW" badge.
- **Custom labels and favorites** persisted across launches.

## Build and run

Requires Flutter 3.x with Dart 3.11+ and the Android toolchain (SDK,
gradle).

```bash
flutter pub get
flutter run -d <android-device-id>
```

Release APK:

```bash
flutter build apk --release
# APK ends up at build/app/outputs/flutter-apk/app-release.apk
```

## Permissions

Android needs the Bluetooth scan / connect runtime permissions; on
Android 12+ also `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`. The app
requests these at launch via `permission_handler`. Location permission
is required for BLE scanning on Android (a system-level constraint, not
an app choice).

## Architecture

- `lib/scanner_state.dart` — the central `ChangeNotifier` that owns the
  scan stream, the per-device records, filtering and sort state.
- `lib/services/` — singleton `ChangeNotifier`s for app settings, device
  notes/favorites, bonded-device registry, new-device monitor, session
  recorder, and the direction finder.
- `lib/models/` — `DeviceRecord` (one device's accumulated state),
  `RssiSample`, `DirectionFix`.
- `lib/widgets/` — reusable UI pieces (signal gauge, sparkline, info
  chip, stat grid, compass dial, sweep sheet, hot/cold indicator, etc.).
- `lib/screens/` — one file per top-level page.
- `lib/utils/` — Bluetooth helpers, beacon parsers, device guessing,
  formatting.

## Direction finding — limits

The "Find the direction" feature uses Bluetooth-only direction inference
by sampling RSSI while you rotate your body. This works because the
user's torso partially blocks the radio at 2.4 GHz, producing a 5–20 dB
swing across a full rotation. The peak heading correlates with the
device's bearing, but:

- It is an **estimate**, not a true angle-of-arrival fix.
- Multipath reflections off walls / metal can produce false peaks.
- Compass accuracy on the phone matters; recalibrate (figure-8 motion)
  if results drift.
- Apple's UWB arrow uses dedicated angle-of-arrival hardware (U1 chip)
  and is fundamentally more precise than this can ever be.

The implementation layers: 16 × 22.5° heading buckets, per-bucket median
RSSI (robust to multipath spikes), circular Gaussian smoothing across
neighbours, parabolic peak interpolation for sub-bucket precision, and
velocity gating to skip samples taken while rotating faster than the
compass can track.

## Project status

Active development. Not yet on the Play Store.
