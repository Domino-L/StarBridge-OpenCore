import 'package:flutter/material.dart';

enum AppearanceMode { dark, light }

enum DomainColorRole {
  command,
  ship,
  airCombat,
  groundCombat,
  recon,
  industry,
  medical,
  logistics,
}

@immutable
final class DomainColorPairTokens {
  const DomainColorPairTokens({required this.foreground, required this.soft});

  final Color foreground;
  final Color soft;

  DomainColorPairTokens lerp(DomainColorPairTokens other, double t) {
    return DomainColorPairTokens(
      foreground: Color.lerp(foreground, other.foreground, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
    );
  }
}

@immutable
final class DomainColorTokens {
  const DomainColorTokens({
    required this.command,
    required this.ship,
    required this.airCombat,
    required this.groundCombat,
    required this.recon,
    required this.industry,
    required this.medical,
    required this.logistics,
  });

  final DomainColorPairTokens command;
  final DomainColorPairTokens ship;
  final DomainColorPairTokens airCombat;
  final DomainColorPairTokens groundCombat;
  final DomainColorPairTokens recon;
  final DomainColorPairTokens industry;
  final DomainColorPairTokens medical;
  final DomainColorPairTokens logistics;

  DomainColorPairTokens resolve(DomainColorRole role) => switch (role) {
    DomainColorRole.command => command,
    DomainColorRole.ship => ship,
    DomainColorRole.airCombat => airCombat,
    DomainColorRole.groundCombat => groundCombat,
    DomainColorRole.recon => recon,
    DomainColorRole.industry => industry,
    DomainColorRole.medical => medical,
    DomainColorRole.logistics => logistics,
  };

  DomainColorTokens lerp(DomainColorTokens other, double t) {
    return DomainColorTokens(
      command: command.lerp(other.command, t),
      ship: ship.lerp(other.ship, t),
      airCombat: airCombat.lerp(other.airCombat, t),
      groundCombat: groundCombat.lerp(other.groundCombat, t),
      recon: recon.lerp(other.recon, t),
      industry: industry.lerp(other.industry, t),
      medical: medical.lerp(other.medical, t),
      logistics: logistics.lerp(other.logistics, t),
    );
  }
}

enum SurfaceRole {
  ground,
  navigation,
  chrome,
  status,
  panel,
  raised,
  floating,
  selected,
}

@immutable
final class ColorTokens {
  const ColorTokens({
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.focusRing,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.offline,
    required this.scrim,
  });

  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color focusRing;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color offline;
  final Color scrim;

  ColorTokens lerp(ColorTokens other, double t) {
    return ColorTokens(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

@immutable
final class SurfaceLevelTokens {
  const SurfaceLevelTokens({
    required this.fill,
    required this.border,
    this.shadows = const [],
  });

  final Color fill;
  final Color border;
  final List<BoxShadow> shadows;

  SurfaceLevelTokens lerp(SurfaceLevelTokens other, double t) {
    return SurfaceLevelTokens(
      fill: Color.lerp(fill, other.fill, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadows: BoxShadow.lerpList(shadows, other.shadows, t) ?? const [],
    );
  }
}

@immutable
final class SurfaceTokens {
  const SurfaceTokens({
    required this.windowFrame,
    required this.ground,
    required this.navigation,
    required this.chrome,
    required this.status,
    required this.panel,
    required this.raised,
    required this.floating,
    required this.selected,
  });

  final Color windowFrame;
  final SurfaceLevelTokens ground;
  final SurfaceLevelTokens navigation;
  final SurfaceLevelTokens chrome;
  final SurfaceLevelTokens status;
  final SurfaceLevelTokens panel;
  final SurfaceLevelTokens raised;
  final SurfaceLevelTokens floating;
  final SurfaceLevelTokens selected;

  SurfaceLevelTokens resolve(SurfaceRole role) => switch (role) {
    SurfaceRole.ground => ground,
    SurfaceRole.navigation => navigation,
    SurfaceRole.chrome => chrome,
    SurfaceRole.status => status,
    SurfaceRole.panel => panel,
    SurfaceRole.raised => raised,
    SurfaceRole.floating => floating,
    SurfaceRole.selected => selected,
  };

  SurfaceTokens lerp(SurfaceTokens other, double t) {
    return SurfaceTokens(
      windowFrame: Color.lerp(windowFrame, other.windowFrame, t)!,
      ground: ground.lerp(other.ground, t),
      navigation: navigation.lerp(other.navigation, t),
      chrome: chrome.lerp(other.chrome, t),
      status: status.lerp(other.status, t),
      panel: panel.lerp(other.panel, t),
      raised: raised.lerp(other.raised, t),
      floating: floating.lerp(other.floating, t),
      selected: selected.lerp(other.selected, t),
    );
  }
}
