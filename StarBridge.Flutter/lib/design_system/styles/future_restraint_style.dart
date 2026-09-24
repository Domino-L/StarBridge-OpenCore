import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/geometry_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import '../tokens/typography_tokens.dart';

abstract final class FutureRestraintStyle {
  static const id = 'future-restraint-a';
  static const name = 'Future Restraint';

  static const typography = TypographyTokens(
    uiFamily: 'Source Sans 3',
    simplifiedChineseFamily: 'Source Han Sans CN',
    traditionalChineseFamily: 'Microsoft JhengHei UI',
    systemFallbacks: ['Segoe UI', 'Microsoft YaHei UI', 'Segoe UI Symbol'],
    monoFamily: 'Source Code Pro',
    monoFallbacks: ['Cascadia Mono', 'Consolas'],
    display: 30,
    headline: 22,
    title: 18,
    titleSmall: 15,
    body: 14,
    bodySmall: 13,
    label: 12,
    mono: 12,
    monoLarge: 15,
    displayWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
    emphasisWeight: FontWeight.w600,
    displayTracking: -0.3,
    bodyHeight: 1.42,
  );

  static const space = SpaceTokens(
    xxs: 3,
    xs: 6,
    sm: 10,
    md: 14,
    lg: 20,
    xl: 28,
    xxl: 40,
  );

  static const shape = ShapeTokens(
    radiusSmall: 6,
    radiusMedium: 9,
    radiusLarge: 12,
    radiusPill: 999,
  );

  static const stroke = StrokeTokens(
    hairline: 1,
    regular: 1,
    strong: 1.5,
    focusWidth: 2,
    focusOffset: 2,
  );

  static const motion = MotionTokens(
    pointerPageSwap: Duration(milliseconds: 180),
    pointerMicro: Duration(milliseconds: 120),
    surfaceEnter: Duration(milliseconds: 220),
    surfaceExit: Duration(milliseconds: 140),
    tooltipDelay: Duration(milliseconds: 450),
    enterCurve: Cubic(0.2, 0, 0, 1),
    exitCurve: Cubic(0.4, 0, 1, 1),
    pageOffset: 8,
    splashEnabled: true,
  );

  static const density = DensityTokens(
    controlHeight: 40,
    compactControlHeight: 28,
    rowHeight: 56,
    navigationItemHeight: 44,
    topBarHeight: 64,
    statusBarHeight: 28,
    pagePadding: 24,
    panelPadding: 18,
    contentMaxWidth: 1120,
    navigationWide: 224,
    navigationCompact: 168,
    navigationIconOnly: 76,
  );

  static const icons = IconTokens(
    setId: 'starbridge-outline-v1',
    small: 16,
    medium: 20,
    large: 24,
    statusDot: 9,
  );

  static const _darkColors = ColorTokens(
    textPrimary: Color(0xFFE7EEF2),
    textSecondary: Color(0xFF93A4AE),
    textDisabled: Color(0xFF5A6A74),
    accent: Color(0xFF4CB2F5),
    accentSoft: Color(0xFF173348),
    onAccent: Color(0xFF071925),
    focusRing: Color(0xFF87CEFF),
    success: Color(0xFF3ED59A),
    successSoft: Color(0xFF15302A),
    warning: Color(0xFFF5B544),
    warningSoft: Color(0xFF33280F),
    danger: Color(0xFFF26D75),
    dangerSoft: Color(0xFF351A1C),
    info: Color(0xFF53B7FF),
    infoSoft: Color(0xFF162836),
    offline: Color(0xFF7A8790),
    scrim: Color(0xB3000000),
  );

  static const _lightColors = ColorTokens(
    textPrimary: Color(0xFF17242C),
    textSecondary: Color(0xFF4A5B64),
    textDisabled: Color(0xFF8B9AA2),
    accent: Color(0xFF1768A3),
    accentSoft: Color(0xFFE1EDF7),
    onAccent: Color(0xFFFFFFFF),
    focusRing: Color(0xFF105889),
    success: Color(0xFF13734F),
    successSoft: Color(0xFFDCEDE5),
    warning: Color(0xFF8A5700),
    warningSoft: Color(0xFFF6E9D2),
    danger: Color(0xFFB62F43),
    dangerSoft: Color(0xFFF6E0E0),
    info: Color(0xFF176AA3),
    infoSoft: Color(0xFFDDEAF2),
    offline: Color(0xFF66757D),
    scrim: Color(0x99000000),
  );

  static const _darkDomainColors = DomainColorTokens(
    command: DomainColorPairTokens(
      foreground: Color(0xFFF1AE38),
      soft: Color(0xFF33280F),
    ),
    ship: DomainColorPairTokens(
      foreground: Color(0xFF4DB9FA),
      soft: Color(0xFF132C3B),
    ),
    airCombat: DomainColorPairTokens(
      foreground: Color(0xFFF1788A),
      soft: Color(0xFF351C24),
    ),
    groundCombat: DomainColorPairTokens(
      foreground: Color(0xFFF15B65),
      soft: Color(0xFF351A1C),
    ),
    recon: DomainColorPairTokens(
      foreground: Color(0xFF49D2DE),
      soft: Color(0xFF183A42),
    ),
    industry: DomainColorPairTokens(
      foreground: Color(0xFFEFC15A),
      soft: Color(0xFF332A14),
    ),
    medical: DomainColorPairTokens(
      foreground: Color(0xFF45DB95),
      soft: Color(0xFF15302A),
    ),
    logistics: DomainColorPairTokens(
      foreground: Color(0xFFAF91F3),
      soft: Color(0xFF261F3B),
    ),
  );

  static const _lightDomainColors = DomainColorTokens(
    command: DomainColorPairTokens(
      foreground: Color(0xFF7D5615),
      soft: Color(0xFFF6E9D2),
    ),
    ship: DomainColorPairTokens(
      foreground: Color(0xFF1E6FA6),
      soft: Color(0xFFDDEAF2),
    ),
    airCombat: DomainColorPairTokens(
      foreground: Color(0xFF963F58),
      soft: Color(0xFFF5E2E7),
    ),
    groundCombat: DomainColorPairTokens(
      foreground: Color(0xFF9A3535),
      soft: Color(0xFFF6E0E0),
    ),
    recon: DomainColorPairTokens(
      foreground: Color(0xFF2F7480),
      soft: Color(0xFFD7E9EC),
    ),
    industry: DomainColorPairTokens(
      foreground: Color(0xFF70591D),
      soft: Color(0xFFF4EBCD),
    ),
    medical: DomainColorPairTokens(
      foreground: Color(0xFF246B50),
      soft: Color(0xFFDCEDE5),
    ),
    logistics: DomainColorPairTokens(
      foreground: Color(0xFF5E5297),
      soft: Color(0xFFE8E4F4),
    ),
  );

  static const _darkSurfaces = SurfaceTokens(
    windowFrame: Color(0xFF405461),
    ground: SurfaceLevelTokens(
      fill: Color(0xFF080C10),
      border: Color(0xFF26333C),
    ),
    navigation: SurfaceLevelTokens(
      fill: Color(0xFF0D151B),
      border: Color(0xFF26333C),
    ),
    chrome: SurfaceLevelTokens(
      fill: Color(0xFF101920),
      border: Color(0xFF26333C),
    ),
    status: SurfaceLevelTokens(
      fill: Color(0xFF0B1217),
      border: Color(0xFF26333C),
    ),
    panel: SurfaceLevelTokens(
      fill: Color(0xFF111920),
      border: Color(0xFF4C616E),
    ),
    raised: SurfaceLevelTokens(
      fill: Color(0xFF18242C),
      border: Color(0xFF4C616E),
    ),
    floating: SurfaceLevelTokens(
      fill: Color(0xFF1B2831),
      border: Color(0xFF4C616E),
      shadows: [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    selected: SurfaceLevelTokens(
      fill: Color(0xFF173348),
      border: Color(0xFF4CB2F5),
    ),
  );

  static const _lightPanelShadows = [
    BoxShadow(color: Color(0x0F1B2A33), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A1B2A33), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static const _lightSurfaces = SurfaceTokens(
    windowFrame: Color(0xFF718690),
    ground: SurfaceLevelTokens(
      fill: Color(0xFFEDF2F4),
      border: Color(0xFFCBD6DB),
    ),
    navigation: SurfaceLevelTokens(
      fill: Color(0xFFF7FAFB),
      border: Color(0xFFCBD6DB),
    ),
    chrome: SurfaceLevelTokens(
      fill: Color(0xFFFAFCFD),
      border: Color(0xFFCBD6DB),
    ),
    status: SurfaceLevelTokens(
      fill: Color(0xFFE8EFF2),
      border: Color(0xFFCBD6DB),
    ),
    panel: SurfaceLevelTokens(
      fill: Color(0xFFFAFCFD),
      border: Color(0xFF7A8C96),
      shadows: _lightPanelShadows,
    ),
    raised: SurfaceLevelTokens(
      fill: Color(0xFFFFFFFF),
      border: Color(0xFF7A8C96),
      shadows: _lightPanelShadows,
    ),
    floating: SurfaceLevelTokens(
      fill: Color(0xFFFFFFFF),
      border: Color(0xFF7A8C96),
      shadows: [
        BoxShadow(
          color: Color(0x241B2A33),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    selected: SurfaceLevelTokens(
      fill: Color(0xFFE1EDF7),
      border: Color(0xFF1768A3),
    ),
  );

  static StarBridgeTokens resolve(AppearanceMode mode) {
    final dark = mode == AppearanceMode.dark;
    return StarBridgeTokens(
      styleId: id,
      styleName: name,
      appearanceMode: mode,
      colors: dark ? _darkColors : _lightColors,
      domainColors: dark ? _darkDomainColors : _lightDomainColors,
      surfaces: dark ? _darkSurfaces : _lightSurfaces,
      typography: typography,
      space: space,
      shape: shape,
      stroke: stroke,
      motion: motion,
      density: density,
      icons: icons,
    );
  }
}
