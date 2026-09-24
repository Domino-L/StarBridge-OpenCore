import 'package:flutter/material.dart';

@immutable
final class SpaceTokens {
  const SpaceTokens({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  SpaceTokens scaled(double factor) => SpaceTokens(
    xxs: xxs * factor,
    xs: xs * factor,
    sm: sm * factor,
    md: md * factor,
    lg: lg * factor,
    xl: xl * factor,
    xxl: xxl * factor,
  );
}

@immutable
final class ShapeTokens {
  const ShapeTokens({
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusPill,
  });

  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusPill;

  BorderRadius get small => BorderRadius.circular(radiusSmall);
  BorderRadius get medium => BorderRadius.circular(radiusMedium);
  BorderRadius get large => BorderRadius.circular(radiusLarge);
  BorderRadius get pill => BorderRadius.circular(radiusPill);
}

@immutable
final class StrokeTokens {
  const StrokeTokens({
    required this.hairline,
    required this.regular,
    required this.strong,
    required this.focusWidth,
    required this.focusOffset,
  });

  final double hairline;
  final double regular;
  final double strong;
  final double focusWidth;
  final double focusOffset;
}

@immutable
final class DensityTokens {
  const DensityTokens({
    required this.controlHeight,
    required this.compactControlHeight,
    required this.rowHeight,
    required this.navigationItemHeight,
    required this.topBarHeight,
    required this.statusBarHeight,
    required this.pagePadding,
    required this.panelPadding,
    required this.contentMaxWidth,
    required this.navigationWide,
    required this.navigationCompact,
    required this.navigationIconOnly,
  });

  final double controlHeight;
  final double compactControlHeight;
  final double rowHeight;
  final double navigationItemHeight;
  final double topBarHeight;
  final double statusBarHeight;
  final double pagePadding;
  final double panelPadding;
  final double contentMaxWidth;
  final double navigationWide;
  final double navigationCompact;
  final double navigationIconOnly;

  DensityTokens scaled(double factor) => DensityTokens(
    controlHeight: controlHeight * factor,
    compactControlHeight: compactControlHeight * factor,
    rowHeight: rowHeight * factor,
    navigationItemHeight: navigationItemHeight * factor,
    topBarHeight: topBarHeight * factor,
    statusBarHeight: statusBarHeight * factor,
    pagePadding: pagePadding * factor,
    panelPadding: panelPadding * factor,
    contentMaxWidth: contentMaxWidth * factor,
    navigationWide: navigationWide,
    navigationCompact: navigationCompact,
    navigationIconOnly: navigationIconOnly,
  );
}

@immutable
final class IconTokens {
  const IconTokens({
    required this.setId,
    required this.small,
    required this.medium,
    required this.large,
    required this.statusDot,
  });

  final String setId;
  final double small;
  final double medium;
  final double large;
  final double statusDot;

  IconTokens scaled(double factor) => IconTokens(
    setId: setId,
    small: small * factor,
    medium: medium * factor,
    large: large * factor,
    statusDot: statusDot * factor,
  );
}
