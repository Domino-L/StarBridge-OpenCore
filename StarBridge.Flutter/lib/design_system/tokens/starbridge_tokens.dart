import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'geometry_tokens.dart';
import 'motion_tokens.dart';
import 'typography_tokens.dart';

@immutable
final class StarBridgeTokens extends ThemeExtension<StarBridgeTokens> {
  const StarBridgeTokens({
    required this.styleId,
    required this.styleName,
    required this.appearanceMode,
    required this.colors,
    required this.domainColors,
    required this.surfaces,
    required this.typography,
    required this.space,
    required this.shape,
    required this.stroke,
    required this.motion,
    required this.density,
    required this.icons,
  });

  final String styleId;
  final String styleName;
  final AppearanceMode appearanceMode;
  final ColorTokens colors;
  final DomainColorTokens domainColors;
  final SurfaceTokens surfaces;
  final TypographyTokens typography;
  final SpaceTokens space;
  final ShapeTokens shape;
  final StrokeTokens stroke;
  final MotionTokens motion;
  final DensityTokens density;
  final IconTokens icons;

  bool get isDark => appearanceMode == AppearanceMode.dark;

  @override
  StarBridgeTokens copyWith({
    String? styleId,
    String? styleName,
    AppearanceMode? appearanceMode,
    ColorTokens? colors,
    DomainColorTokens? domainColors,
    SurfaceTokens? surfaces,
    TypographyTokens? typography,
    SpaceTokens? space,
    ShapeTokens? shape,
    StrokeTokens? stroke,
    MotionTokens? motion,
    DensityTokens? density,
    IconTokens? icons,
  }) {
    return StarBridgeTokens(
      styleId: styleId ?? this.styleId,
      styleName: styleName ?? this.styleName,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      colors: colors ?? this.colors,
      domainColors: domainColors ?? this.domainColors,
      surfaces: surfaces ?? this.surfaces,
      typography: typography ?? this.typography,
      space: space ?? this.space,
      shape: shape ?? this.shape,
      stroke: stroke ?? this.stroke,
      motion: motion ?? this.motion,
      density: density ?? this.density,
      icons: icons ?? this.icons,
    );
  }

  StarBridgeTokens withReducedMotion(bool reduceMotion) {
    return reduceMotion ? copyWith(motion: motion.stilled) : this;
  }

  @override
  StarBridgeTokens lerp(ThemeExtension<StarBridgeTokens>? other, double t) {
    if (other is! StarBridgeTokens || other.styleId != styleId) {
      return t < 0.5 ? this : (other as StarBridgeTokens? ?? this);
    }
    return other.copyWith(
      colors: colors.lerp(other.colors, t),
      domainColors: domainColors.lerp(other.domainColors, t),
      surfaces: surfaces.lerp(other.surfaces, t),
    );
  }
}

extension StarBridgeTokenContext on BuildContext {
  StarBridgeTokens get tokens => Theme.of(this).extension<StarBridgeTokens>()!;
}
