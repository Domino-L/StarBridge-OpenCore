import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The line color of a ship's stage, taken once from its artwork: the hue that
/// carries the most color, brought to one strength so every ship reads alike.
abstract final class LocalHangarShipAccent {
  static final _known = <String, Color?>{};
  static final _isTestRun = Platform.environment.containsKey('FLUTTER_TEST');

  static Color? known(String asset) => _known[asset];

  static Future<Color?> read(String asset) async {
    if (_isTestRun) return null;
    if (_known.containsKey(asset)) return _known[asset];
    Color? accent;
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 96,
        targetHeight: 34,
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData();
      frame.image.dispose();
      codec.dispose();
      if (bytes != null) accent = fromRgba(bytes.buffer.asUint8List());
    } on Object {
      accent = null;
    }
    return _known[asset] = accent;
  }

  /// Null when the artwork has no real color; the caller keeps its own accent.
  @visibleForTesting
  static Color? fromRgba(Uint8List rgba) {
    final weight = <int, double>{};
    final hue = <int, double>{}, saturation = <int, double>{};
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final color = HSVColor.fromColor(
        Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]),
      );
      if (color.saturation < .22 || color.value < .22) continue;
      final bucket = (color.hue / 15).floor();
      final w = color.saturation * color.value;
      weight[bucket] = (weight[bucket] ?? 0) + w;
      hue[bucket] = (hue[bucket] ?? 0) + color.hue * w;
      saturation[bucket] = (saturation[bucket] ?? 0) + color.saturation * w;
    }
    if (weight.isEmpty) return null;
    final top = weight.keys.reduce((a, b) => weight[a]! >= weight[b]! ? a : b);
    return HSVColor.fromAHSV(
      1,
      hue[top]! / weight[top]!,
      (saturation[top]! / weight[top]!).clamp(.55, .78),
      .98,
    ).toColor();
  }
}
