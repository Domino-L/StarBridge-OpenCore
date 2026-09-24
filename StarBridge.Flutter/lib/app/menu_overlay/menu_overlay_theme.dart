import 'package:flutter/material.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/tokens/color_tokens.dart';

/// Use the client's dark theme directly. Menu layout and window opacity are
/// separate concerns, not reasons to introduce another color system.
ThemeData buildMenuOverlayTheme(Locale locale) => buildStarBridgeTheme(
  FutureRestraintStyle.resolve(AppearanceMode.dark),
  locale,
);
