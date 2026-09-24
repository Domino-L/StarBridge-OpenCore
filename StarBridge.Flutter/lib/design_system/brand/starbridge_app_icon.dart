import 'package:flutter/material.dart';

enum StarBridgeAppIconSurface { universalTile, darkSurface, lightSurface }

abstract final class StarBridgeAppIconAssets {
  static const universalTile = 'assets/brand/starbridge_app_icon.png';
  static const darkSurface = 'assets/brand/starbridge_mark_dark_surface.png';
  static const lightSurface = 'assets/brand/starbridge_mark_light_surface.png';
  static const smallFrameSizes = [
    16,
    20,
    24,
    30,
    32,
    36,
    40,
    48,
    64,
    72,
    96,
    128,
    256,
  ];

  static String resolve(StarBridgeAppIconSurface surface) => switch (surface) {
    StarBridgeAppIconSurface.universalTile => universalTile,
    StarBridgeAppIconSurface.darkSurface => darkSurface,
    StarBridgeAppIconSurface.lightSurface => lightSurface,
  };

  static String smallAsset({
    required double physicalSize,
    required Brightness backgroundBrightness,
  }) {
    final frame = smallFrameSizes.firstWhere(
      (size) => size >= physicalSize.round(),
      orElse: () => smallFrameSizes.last,
    );
    final surface = backgroundBrightness == Brightness.dark
        ? 'dark_surface'
        : 'light_surface';
    return 'assets/brand/small_icons/$surface/$frame.png';
  }
}

/// Approved transparent V9 artwork at <=64 logical pixels. Each physical-size
/// frame includes its own optical offset; never translate or dilate it again.
/// Larger brand artwork and explicitly selected large surfaces are unchanged.
class StarBridgeAppIcon extends StatelessWidget {
  const StarBridgeAppIcon({
    required this.size,
    this.surface = StarBridgeAppIconSurface.universalTile,
    super.key,
  });

  final double size;
  final StarBridgeAppIconSurface surface;

  @override
  Widget build(BuildContext context) {
    final backgroundBrightness = switch (surface) {
      StarBridgeAppIconSurface.darkSurface => Brightness.dark,
      StarBridgeAppIconSurface.lightSurface => Brightness.light,
      StarBridgeAppIconSurface.universalTile => Theme.of(context).brightness,
    };
    final asset = size <= 64
        ? StarBridgeAppIconAssets.smallAsset(
            physicalSize:
                size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0),
            backgroundBrightness: backgroundBrightness,
          )
        : StarBridgeAppIconAssets.resolve(surface);
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        isAntiAlias: true,
      ),
    );
  }
}
