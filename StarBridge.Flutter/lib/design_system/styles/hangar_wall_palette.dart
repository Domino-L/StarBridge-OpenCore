import 'package:flutter/material.dart';

/// Fixed colors of the personal hangar wall and its stage. Text on artwork and
/// scrims stay the same in both appearances because the artwork does.
class HangarWallPalette {
  const HangarWallPalette._({
    required this.imageDim,
    required this.stageGround,
    required this.lineStrength,
    required this.artEdgeFade,
    required this.isDark,
  });

  static const onArt = Color(0xFFF0F4F7);
  static const onArtFaint = Color(0xB3F0F4F7);
  static const onArtFavorite = Color(0xFFFFB84D);
  static const markBack = Color(0x66050810);
  static const artScrim = Color(0xD9050810);
  static const artScrimClear = Color(0x00050810);
  static const imageDimHover = Color(0x00050810);

  static const _dark = HangarWallPalette._(
    imageDim: Color(0x14050810),
    stageGround: Color(0xFF070B10),
    lineStrength: .26,
    artEdgeFade: .72,
    isDark: true,
  );
  static const _light = HangarWallPalette._(
    imageDim: Color(0x00050810),
    stageGround: Color(0xFFF1F4F7),
    lineStrength: .42,
    artEdgeFade: .96,
    isDark: false,
  );

  static HangarWallPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  final Color imageDim, stageGround;
  final double lineStrength;

  /// How far the artwork has faded into the ground at its lower edge. A light
  /// ground needs almost all of it, or the edge shows.
  final double artEdgeFade;
  final bool isDark;

  /// Catalog role colors are exact and made for dark surfaces; light surfaces
  /// need the same hue darker to stay readable as text.
  Color roleText(Color role) {
    if (isDark) return role;
    final hsl = HSLColor.fromColor(role);
    return hsl.withLightness((hsl.lightness * .62).clamp(0, .42)).toColor();
  }

  /// The ship's own line color, deepened on light surfaces.
  Color line(Color accent) {
    if (isDark) return accent;
    return HSVColor.fromColor(accent).withValue(.58).toColor();
  }
}
