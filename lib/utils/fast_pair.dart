import 'package:flutter/material.dart';

import 'device_guess.dart';
import 'uuids.dart';

/// Google Fast Pair advertises a 3-byte product model ID in service data
/// under UUID 0xFE2C. Google maintains a global registry; this is a curated
/// subset of popular products.
///
/// Format of the service data (discoverable):
///   [byte 0..2]: model ID, big-endian.
/// Non-discoverable adverts include 16+ bytes of additional account-key data.
///
/// Reference: https://developers.google.com/nearby/fast-pair/specifications/service
const Map<int, _FastPairProduct> _kFastPair = {
  // Google
  0x000007: _FastPairProduct('Pixel Buds (1st gen)', Icons.hearing),
  0x00000C: _FastPairProduct('Pixel Buds A-Series', Icons.hearing),
  0x40A88B: _FastPairProduct('Pixel Buds Pro', Icons.hearing),
  0xB68BB6: _FastPairProduct('Pixel Buds Pro 2', Icons.hearing),

  // Sony
  0x0E45BD: _FastPairProduct('Sony WH-1000XM4', Icons.headphones),
  0xF2D9C6: _FastPairProduct('Sony WH-1000XM5', Icons.headphones),
  0x9ADB11: _FastPairProduct('Sony WF-1000XM4', Icons.hearing),
  0x05A963: _FastPairProduct('Sony WF-1000XM5', Icons.hearing),
  0xB106B1: _FastPairProduct('Sony LinkBuds S', Icons.hearing),

  // JBL
  0x0E0E6B: _FastPairProduct('JBL Flip 5', Icons.speaker),
  0x718FA4: _FastPairProduct('JBL Flip 6', Icons.speaker),
  0x71C5C7: _FastPairProduct('JBL Charge 5', Icons.speaker),
  0xCD8256: _FastPairProduct('JBL Tune 510BT', Icons.headphones),
  0xCD82C6: _FastPairProduct('JBL Tune 720BT', Icons.headphones),
  0x39EA9A: _FastPairProduct('JBL Live Pro 2', Icons.hearing),

  // Bose
  0x008036: _FastPairProduct('Bose QC Ultra Headphones', Icons.headphones),
  0xCF02CB: _FastPairProduct('Bose QuietComfort 45', Icons.headphones),

  // Anker / Soundcore
  0x06D2A4: _FastPairProduct('Soundcore Liberty 4 NC', Icons.hearing),
  0x4F1FBC: _FastPairProduct('Soundcore Liberty 4', Icons.hearing),

  // Sennheiser / EPOS
  0x2D7B26: _FastPairProduct('Sennheiser Momentum 4', Icons.headphones),

  // Beats (yes — Fast Pair works for Beats too on Android)
  0xD3923A: _FastPairProduct('Beats Studio Buds', Icons.hearing),

  // Microsoft Surface
  0x1BF1F0: _FastPairProduct('Microsoft Surface Earbuds', Icons.hearing),
  0x4F1F50: _FastPairProduct('Microsoft Surface Headphones 2', Icons.headphones),
};

class _FastPairProduct {
  const _FastPairProduct(this.name, this.icon);
  final String name;
  final IconData icon;
}

/// Fast Pair service UUID (16-bit form, expanded). Re-exported as
/// [kFastPairServiceUuid] from `uuids.dart`; the public name here is kept
/// as a stable alias for callers and tests that already reference it.
const String fastPairServiceUuid = kFastPairServiceUuid;

/// Extracts the model ID and returns a guess if it's a known product.
/// Returns null if the data isn't Fast Pair, the ID is unknown, or the
/// payload is too short.
DeviceGuess? guessFromFastPair(Map<String, List<int>> serviceData) {
  final data = serviceData[fastPairServiceUuid];
  if (data == null || data.length < 3) return null;
  final modelId = (data[0] << 16) | (data[1] << 8) | data[2];
  final product = _kFastPair[modelId];
  if (product == null) {
    return DeviceGuess(
      'Fast Pair device (0x${modelId.toRadixString(16).padLeft(6, '0').toUpperCase()})',
      confidence: Confidence.possible,
      icon: Icons.devices,
    );
  }
  return DeviceGuess(
    product.name,
    confidence: Confidence.certain,
    icon: product.icon,
  );
}
