import 'package:flutter/material.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/tokens/color_tokens.dart';

/// Use the client's dark theme directly. Menu layout and window opacity are
/// separate concerns, not reasons to introduce another color system.
ThemeData buildMenuOverlayTheme(Locale locale, {bool reduceMotion = false}) =>
    buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark)
          .withReducedMotion(reduceMotion),
      locale,
    );

/// Stills application effects, not the tickers used by interaction/visible read
/// receipts. Freezing an entire surface would leave switches visually stale.
class MenuPresentation extends StatelessWidget {
  const MenuPresentation({
    super.key,
    required this.safeMode,
    this.textScalePercent = 100,
    this.reduceMotion = false,
    this.highContrast = false,
    this.tooltipDelayMilliseconds = 500,
    required this.child,
  });
  final bool safeMode;
  final int textScalePercent;
  final bool reduceMotion;
  final bool highContrast;
  final int tooltipDelayMilliseconds;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final reduced =
        safeMode || reduceMotion || MediaQuery.disableAnimationsOf(context);
    final theme = buildMenuOverlayTheme(
      Localizations.localeOf(context),
      reduceMotion: reduced,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        highContrast: highContrast || MediaQuery.highContrastOf(context),
        disableAnimations: reduced,
        textScaler: _MenuTextScaler(
          MediaQuery.textScalerOf(context),
          textScalePercent / 100,
        ),
      ),
      child: Theme(
        data: theme.copyWith(
          tooltipTheme: theme.tooltipTheme.copyWith(
            waitDuration: Duration(milliseconds: tooltipDelayMilliseconds),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Compose with the platform scaler, including nonlinear accessibility scaling.
/// This changes Flutter text only, not panel geometry or native web content.
class _MenuTextScaler extends TextScaler {
  const _MenuTextScaler(this.platform, this.factor);
  final TextScaler platform;
  final double factor;
  @override
  double scale(double fontSize) => platform.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is _MenuTextScaler &&
      other.platform == platform &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(platform, factor);
}
