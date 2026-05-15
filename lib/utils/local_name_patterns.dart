import 'package:flutter/material.dart';

import 'device_guess.dart';

class _NamePattern {
  const _NamePattern(this.regex, this.label, this.icon, {this.confidence = Confidence.likely});
  final RegExp regex;
  final String label;
  final IconData icon;
  final Confidence confidence;
}

/// Regex catalog mapping advertised device names to specific consumer products.
/// Order matters — first match wins, so put more specific patterns first.
///
/// Note: All patterns are case-insensitive.
final List<_NamePattern> _kPatterns = [
  // Sony headphones — WH = over-ear, WF = earbuds, LinkBuds line.
  _NamePattern(RegExp(r'\bLE_WH-?1000XM\d\b', caseSensitive: false),
      'Sony WH-1000XM headphones', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bWH-?1000XM\d\b', caseSensitive: false),
      'Sony WH-1000XM headphones', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bWH-?(CH|H|XB)\d+', caseSensitive: false),
      'Sony WH-series headphones', Icons.headphones),
  _NamePattern(RegExp(r'\bWF-?1000XM\d\b', caseSensitive: false),
      'Sony WF-1000XM earbuds', Icons.hearing, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bWF-?(C|H|SP|LS)\d+', caseSensitive: false),
      'Sony WF-series earbuds', Icons.hearing),
  _NamePattern(RegExp(r'\bLinkBuds( S| Fit)?\b', caseSensitive: false),
      'Sony LinkBuds', Icons.hearing, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bSRS-?(XB|XE|XG)\d+', caseSensitive: false),
      'Sony SRS speaker', Icons.speaker),

  // Bose
  _NamePattern(RegExp(r'\bQC\s?(Ultra|45|35|30)\b', caseSensitive: false),
      'Bose QuietComfort headphones', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bQuietComfort\b', caseSensitive: false),
      'Bose QuietComfort', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bSoundLink\b', caseSensitive: false),
      'Bose SoundLink speaker', Icons.speaker),
  _NamePattern(RegExp(r'\bBose\b', caseSensitive: false),
      'Bose audio device', Icons.headphones),

  // JBL
  _NamePattern(RegExp(r'\bJBL\s?(Charge|Flip|Xtreme|Boombox|Clip|Go|Pulse)\b', caseSensitive: false),
      'JBL portable speaker', Icons.speaker, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bJBL\s?(Tune|Live|Reflect|Endurance|Quantum)\b', caseSensitive: false),
      'JBL headphones', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bJBL\b', caseSensitive: false),
      'JBL audio device', Icons.speaker),

  // Apple — Continuity normally catches these, but raw names slip through.
  _NamePattern(RegExp(r"\bAirPods( Pro| Max| 2| 3| 4)?\b", caseSensitive: false),
      'Apple AirPods', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bBeats\s?(Studio|Solo|Fit|Flex|Pill|X)\b', caseSensitive: false),
      'Beats audio device', Icons.headphones, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bMagic\s?(Mouse|Keyboard|Trackpad)\b', caseSensitive: false),
      'Apple Magic accessory', Icons.keyboard, confidence: Confidence.certain),
  _NamePattern(RegExp(r"\bMacBook\b", caseSensitive: false),
      'MacBook', Icons.laptop_mac, confidence: Confidence.certain),
  _NamePattern(RegExp(r"\biPhone\b", caseSensitive: false),
      'iPhone', Icons.phone_iphone, confidence: Confidence.certain),
  _NamePattern(RegExp(r"\biPad\b", caseSensitive: false),
      'iPad', Icons.tablet_mac, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bApple Watch\b', caseSensitive: false),
      'Apple Watch', Icons.watch, confidence: Confidence.certain),

  // Samsung Galaxy line
  _NamePattern(RegExp(r'\bGalaxy Buds( Live| Pro| 2| 3| FE)?\b', caseSensitive: false),
      'Samsung Galaxy Buds', Icons.hearing, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bGalaxy Watch\d?\b', caseSensitive: false),
      'Samsung Galaxy Watch', Icons.watch, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bGalaxy (S|Z|Note|A|M)\d+', caseSensitive: false),
      'Samsung Galaxy phone', Icons.phone_android, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bGalaxy Tab\b', caseSensitive: false),
      'Samsung Galaxy Tab', Icons.tablet_android, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bSM-[A-Z]\d{3,}', caseSensitive: false),
      'Samsung device (model code)', Icons.phone_android),

  // Google / Pixel
  _NamePattern(RegExp(r'\bPixel Buds( Pro| A|-A)?\b', caseSensitive: false),
      'Google Pixel Buds', Icons.hearing, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bPixel \d+', caseSensitive: false),
      'Google Pixel phone', Icons.phone_android, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bPixel Watch\b', caseSensitive: false),
      'Google Pixel Watch', Icons.watch, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bChromecast\b', caseSensitive: false),
      'Google Chromecast', Icons.cast, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bNest\s?(Hub|Mini|Audio|Cam|Wifi)\b', caseSensitive: false),
      'Google Nest device', Icons.home, confidence: Confidence.certain),

  // Microsoft
  _NamePattern(RegExp(r'\bSurface\s?(Pro|Book|Laptop|Studio|Headphones|Earbuds)\b', caseSensitive: false),
      'Microsoft Surface device', Icons.laptop_windows, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bXbox\s?(Wireless\s?)?Controller\b', caseSensitive: false),
      'Xbox controller', Icons.sports_esports, confidence: Confidence.certain),

  // Logitech
  _NamePattern(RegExp(r'\bMX\s?(Master|Anywhere|Vertical|Keys|Ergo|Mechanical|Mini|Brio)\b', caseSensitive: false),
      'Logitech MX peripheral', Icons.keyboard, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bG\d{2,3} (Pro|Lightspeed)?', caseSensitive: false),
      'Logitech G-series gaming gear', Icons.sports_esports),
  _NamePattern(RegExp(r'\bLogitech\b', caseSensitive: false),
      'Logitech device', Icons.devices_other),

  // Garmin / Polar / Wahoo / fitness
  _NamePattern(RegExp(r'\bFenix\b', caseSensitive: false),
      'Garmin Fenix watch', Icons.watch, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bForerunner\b', caseSensitive: false),
      'Garmin Forerunner', Icons.watch, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bEdge\s?\d{3,}', caseSensitive: false),
      'Garmin Edge bike computer', Icons.directions_bike, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bvívoactive|vivoactive\b', caseSensitive: false),
      'Garmin Vívoactive', Icons.watch),
  _NamePattern(RegExp(r'\bGarmin\b', caseSensitive: false),
      'Garmin device', Icons.watch),
  _NamePattern(RegExp(r'\bPolar\b', caseSensitive: false),
      'Polar fitness device', Icons.monitor_heart),
  _NamePattern(RegExp(r'\bWahoo\b', caseSensitive: false),
      'Wahoo fitness device', Icons.directions_bike),

  // Fitbit / Whoop / Oura
  _NamePattern(RegExp(r'\b(Fitbit|Versa|Charge|Inspire|Sense|Luxe)\s?', caseSensitive: false),
      'Fitbit', Icons.watch),
  _NamePattern(RegExp(r'\bWHOOP\b', caseSensitive: false),
      'Whoop strap', Icons.fitness_center, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bOura\b', caseSensitive: false),
      'Oura ring', Icons.fitness_center, confidence: Confidence.certain),

  // Tile / AirTag (AirTag normally caught by Continuity)
  _NamePattern(RegExp(r'\bTile_', caseSensitive: false),
      'Tile tracker', Icons.location_searching, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bAirTag\b', caseSensitive: false),
      'Apple AirTag', Icons.location_searching, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bChipolo\b', caseSensitive: false),
      'Chipolo tracker', Icons.location_searching, confidence: Confidence.certain),

  // Speakers / smart home
  _NamePattern(RegExp(r'\bSonos\b', caseSensitive: false),
      'Sonos speaker', Icons.speaker, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bEcho\s?(Dot|Show|Studio|Pop|Plus|Sub)\b', caseSensitive: false),
      'Amazon Echo', Icons.speaker, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bHomePod\b', caseSensitive: false),
      'Apple HomePod', Icons.speaker, confidence: Confidence.certain),

  // Headphones (other)
  _NamePattern(RegExp(r'\bAnker (Soundcore|Liberty|Life)', caseSensitive: false),
      'Anker Soundcore', Icons.hearing),
  _NamePattern(RegExp(r'\bSennheiser\b', caseSensitive: false),
      'Sennheiser headphones', Icons.headphones),
  _NamePattern(RegExp(r'\bJabra\s?(Elite|Talk|Speak)?\b', caseSensitive: false),
      'Jabra audio device', Icons.headphones),
  _NamePattern(RegExp(r'\bSkullcandy\b', caseSensitive: false),
      'Skullcandy headphones', Icons.headphones),

  // Cameras / cycling / smart home brands
  _NamePattern(RegExp(r'\bGoPro\b', caseSensitive: false),
      'GoPro camera', Icons.videocam, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bDJI\b', caseSensitive: false),
      'DJI device', Icons.flight),
  _NamePattern(RegExp(r'\bInsta360\b', caseSensitive: false),
      'Insta360 camera', Icons.videocam),

  // Smart home sensors / lighting
  _NamePattern(RegExp(r'\bHue\b', caseSensitive: false),
      'Philips Hue', Icons.lightbulb),
  _NamePattern(RegExp(r'\bGovee\b', caseSensitive: false),
      'Govee smart device', Icons.lightbulb),
  _NamePattern(RegExp(r'\bRuuvi\b', caseSensitive: false),
      'RuuviTag sensor', Icons.thermostat, confidence: Confidence.certain),
  _NamePattern(RegExp(r'\bSwitchBot\b', caseSensitive: false),
      'SwitchBot device', Icons.home),
  _NamePattern(RegExp(r'\bEve\s?(Energy|Door|Window|Motion|Room|Weather|Thermo)\b', caseSensitive: false),
      'Eve HomeKit accessory', Icons.home),
  _NamePattern(RegExp(r'\bAqara\b', caseSensitive: false),
      'Aqara smart device', Icons.home),

  // Locks / cars / printers
  _NamePattern(RegExp(r'\bAugust\b', caseSensitive: false),
      'August smart lock', Icons.lock),
  _NamePattern(RegExp(r'\bSchlage\b', caseSensitive: false),
      'Schlage smart lock', Icons.lock),
  _NamePattern(RegExp(r'\bYale\b', caseSensitive: false),
      'Yale smart lock', Icons.lock),
  _NamePattern(RegExp(r'\b(Tesla|Model [SX3Y])\b', caseSensitive: false),
      'Tesla vehicle / accessory', Icons.directions_car),
  _NamePattern(RegExp(r'\bHP\s?(LaserJet|DeskJet|OfficeJet|Envy)', caseSensitive: false),
      'HP printer', Icons.print),

  // Generic last-resort patterns
  _NamePattern(RegExp(r'\b(headphone|headset|earbud)s?\b', caseSensitive: false),
      'Headphones', Icons.headphones, confidence: Confidence.possible),
  _NamePattern(RegExp(r'\bspeaker\b', caseSensitive: false),
      'Speaker', Icons.speaker, confidence: Confidence.possible),
  _NamePattern(RegExp(r'\b(watch|band|tracker)\b', caseSensitive: false),
      'Wearable', Icons.watch, confidence: Confidence.possible),
  _NamePattern(RegExp(r'\bscale\b', caseSensitive: false),
      'Smart scale', Icons.monitor_weight, confidence: Confidence.possible),
];

/// Returns a guess derived from the device's advertised name, or null if none
/// of the patterns match. Caller can fall back to manufacturer/service-based
/// heuristics.
DeviceGuess? guessFromLocalName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  for (final p in _kPatterns) {
    if (p.regex.hasMatch(name)) {
      return DeviceGuess(p.label, confidence: p.confidence, icon: p.icon);
    }
  }
  return null;
}
