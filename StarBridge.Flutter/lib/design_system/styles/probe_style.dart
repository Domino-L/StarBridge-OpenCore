import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/geometry_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import 'future_restraint_style.dart';

abstract final class ProbeStyle {
  static const id = 'probe-extreme';
  static const name = 'Internal probe';

  static const _darkColors = ColorTokens(
    textPrimary: Color(0xFFF7ECFA),
    textSecondary: Color(0xFFC0A8C9),
    textDisabled: Color(0xFF7A6482),
    accent: Color(0xFFE8B33C),
    accentSoft: Color(0xFF4A3A12),
    onAccent: Color(0xFF1A0F1E),
    focusRing: Color(0xFFFFD866),
    success: Color(0xFF7FD6A8),
    successSoft: Color(0xFF14331F),
    warning: Color(0xFFFFB661),
    warningSoft: Color(0xFF3D2A10),
    danger: Color(0xFFFF8A8A),
    dangerSoft: Color(0xFF3D1A1A),
    info: Color(0xFF9EC5FF),
    infoSoft: Color(0xFF1A2540),
    offline: Color(0xFF8E7C96),
    scrim: Color(0xCC1A0F1E),
  );

  static const _lightColors = ColorTokens(
    textPrimary: Color(0xFF23122A),
    textSecondary: Color(0xFF57405F),
    textDisabled: Color(0xFF918298),
    accent: Color(0xFF8A5A00),
    accentSoft: Color(0xFFF7E6C4),
    onAccent: Color(0xFFFFFFFF),
    focusRing: Color(0xFF6B4400),
    success: Color(0xFF1F6B48),
    successSoft: Color(0xFFDCF0E5),
    warning: Color(0xFF7A4E00),
    warningSoft: Color(0xFFF9E9CC),
    danger: Color(0xFF98272C),
    dangerSoft: Color(0xFFF8DFE0),
    info: Color(0xFF244C7A),
    infoSoft: Color(0xFFDDE7F4),
    offline: Color(0xFF6F5F76),
    scrim: Color(0x9923122A),
  );

  static const _darkDomainColors = DomainColorTokens(
    command: DomainColorPairTokens(
      foreground: Color(0xFFFFD866),
      soft: Color(0xFF4A3A12),
    ),
    ship: DomainColorPairTokens(
      foreground: Color(0xFF72D8FF),
      soft: Color(0xFF17384A),
    ),
    airCombat: DomainColorPairTokens(
      foreground: Color(0xFFFF91CF),
      soft: Color(0xFF4A1D38),
    ),
    groundCombat: DomainColorPairTokens(
      foreground: Color(0xFFFF8A8A),
      soft: Color(0xFF3D1A1A),
    ),
    recon: DomainColorPairTokens(
      foreground: Color(0xFF65F0DD),
      soft: Color(0xFF113D38),
    ),
    industry: DomainColorPairTokens(
      foreground: Color(0xFFFFB661),
      soft: Color(0xFF3D2A10),
    ),
    medical: DomainColorPairTokens(
      foreground: Color(0xFF7FD6A8),
      soft: Color(0xFF14331F),
    ),
    logistics: DomainColorPairTokens(
      foreground: Color(0xFFC6A3FF),
      soft: Color(0xFF34234A),
    ),
  );

  static const _lightDomainColors = DomainColorTokens(
    command: DomainColorPairTokens(
      foreground: Color(0xFF6B4400),
      soft: Color(0xFFF7E6C4),
    ),
    ship: DomainColorPairTokens(
      foreground: Color(0xFF125887),
      soft: Color(0xFFD9EDF8),
    ),
    airCombat: DomainColorPairTokens(
      foreground: Color(0xFF8F2861),
      soft: Color(0xFFF6DCEA),
    ),
    groundCombat: DomainColorPairTokens(
      foreground: Color(0xFF98272C),
      soft: Color(0xFFF8DFE0),
    ),
    recon: DomainColorPairTokens(
      foreground: Color(0xFF176B62),
      soft: Color(0xFFD8F0ED),
    ),
    industry: DomainColorPairTokens(
      foreground: Color(0xFF7A4E00),
      soft: Color(0xFFF9E9CC),
    ),
    medical: DomainColorPairTokens(
      foreground: Color(0xFF1F6B48),
      soft: Color(0xFFDCF0E5),
    ),
    logistics: DomainColorPairTokens(
      foreground: Color(0xFF62419A),
      soft: Color(0xFFE9DEF6),
    ),
  );

  static const _darkSurfaces = SurfaceTokens(
    windowFrame: Color(0xFFFFD866),
    ground: SurfaceLevelTokens(
      fill: Color(0xFF1A0F1E),
      border: Color(0xFF9B7BA8),
    ),
    navigation: SurfaceLevelTokens(
      fill: Color(0xFF25152B),
      border: Color(0xFF9B7BA8),
    ),
    chrome: SurfaceLevelTokens(
      fill: Color(0xFF2A1B30),
      border: Color(0xFF9B7BA8),
    ),
    status: SurfaceLevelTokens(
      fill: Color(0xFF201326),
      border: Color(0xFF9B7BA8),
    ),
    panel: SurfaceLevelTokens(
      fill: Color(0xFF2A1B30),
      border: Color(0xFF9B7BA8),
    ),
    raised: SurfaceLevelTokens(
      fill: Color(0xFF3A2742),
      border: Color(0xFFE8B33C),
    ),
    floating: SurfaceLevelTokens(
      fill: Color(0xFF4A3153),
      border: Color(0xFFE8B33C),
    ),
    selected: SurfaceLevelTokens(
      fill: Color(0xFF4A3A12),
      border: Color(0xFFE8B33C),
    ),
  );

  static const _lightSurfaces = SurfaceTokens(
    windowFrame: Color(0xFF6B4400),
    ground: SurfaceLevelTokens(
      fill: Color(0xFFF3EDF6),
      border: Color(0xFF8A6E96),
    ),
    navigation: SurfaceLevelTokens(
      fill: Color(0xFFF9F3FB),
      border: Color(0xFF8A6E96),
    ),
    chrome: SurfaceLevelTokens(
      fill: Color(0xFFFFFFFF),
      border: Color(0xFF8A6E96),
    ),
    status: SurfaceLevelTokens(
      fill: Color(0xFFECE2F0),
      border: Color(0xFF8A6E96),
    ),
    panel: SurfaceLevelTokens(
      fill: Color(0xFFFFFFFF),
      border: Color(0xFF8A6E96),
    ),
    raised: SurfaceLevelTokens(
      fill: Color(0xFFE6DAEC),
      border: Color(0xFF6B4400),
    ),
    floating: SurfaceLevelTokens(
      fill: Color(0xFFFFFFFF),
      border: Color(0xFF6B4400),
    ),
    selected: SurfaceLevelTokens(
      fill: Color(0xFFF7E6C4),
      border: Color(0xFF8A5A00),
    ),
  );

  static StarBridgeTokens resolve(AppearanceMode mode) {
    final dark = mode == AppearanceMode.dark;
    final base = FutureRestraintStyle.resolve(mode);
    return base.copyWith(
      styleId: id,
      styleName: name,
      colors: dark ? _darkColors : _lightColors,
      domainColors: dark ? _darkDomainColors : _lightDomainColors,
      surfaces: dark ? _darkSurfaces : _lightSurfaces,
      typography: base.typography
          .scaled(1.45)
          .withFamilies(
            ui: 'Georgia',
            simplifiedChinese: 'Microsoft YaHei UI',
            traditionalChinese: 'Microsoft JhengHei UI',
            system: const ['Segoe UI'],
            mono: 'Consolas',
            monoFallback: const ['Cascadia Mono'],
          ),
      space: FutureRestraintStyle.space.scaled(0.55),
      shape: const ShapeTokens(
        radiusSmall: 0,
        radiusMedium: 0,
        radiusLarge: 0,
        radiusPill: 0,
      ),
      stroke: const StrokeTokens(
        hairline: 1,
        regular: 3,
        strong: 3,
        focusWidth: 4,
        focusOffset: 0,
      ),
      motion: const MotionTokens(
        pointerPageSwap: Duration.zero,
        pointerMicro: Duration.zero,
        surfaceEnter: Duration.zero,
        surfaceExit: Duration.zero,
        tooltipDelay: Duration.zero,
        enterCurve: Curves.linear,
        exitCurve: Curves.linear,
        pageOffset: 0,
        splashEnabled: false,
      ),
      density: FutureRestraintStyle.density.scaled(1.25),
      icons: FutureRestraintStyle.icons.scaled(1.3),
    );
  }
}
