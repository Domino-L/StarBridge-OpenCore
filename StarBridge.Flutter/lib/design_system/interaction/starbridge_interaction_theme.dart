import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';
import '../../shared/release/official_client_profile.dart';

export 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource, InteractionSuite;

InteractionSuite interactionSuiteFromName(String? name) =>
    !OfficialClientProfile.advancedInteractions
    ? InteractionSuite.standard
    : switch (name) {
        'rail' => InteractionSuite.rail,
        'scan' => InteractionSuite.scan,
        'glow' => InteractionSuite.glow,
        _ => InteractionSuite.standard,
      };

/// Presentation only. The preferences owner supplies this extension; no
/// interaction widget writes settings or chooses a different default.
@immutable
class StarBridgeInteractionTheme
    extends ThemeExtension<StarBridgeInteractionTheme> {
  const StarBridgeInteractionTheme({
    this.suite = InteractionSuite.standard,
    this.reduceMotion = false,
  });

  final InteractionSuite suite;
  final bool reduceMotion;

  @override
  StarBridgeInteractionTheme copyWith({
    InteractionSuite? suite,
    bool? reduceMotion,
  }) => StarBridgeInteractionTheme(
    suite: suite ?? this.suite,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  @override
  StarBridgeInteractionTheme lerp(
    covariant StarBridgeInteractionTheme? other,
    double t,
  ) => other ?? this; // Settings are discrete: do not delay them in a theme fade.
}

InteractionData resolveStarBridgeInteraction(BuildContext context) {
  final theme = Theme.of(context);
  final style = theme.extension<StarBridgeInteractionTheme>();
  final tokens = theme.extension<StarBridgeTokens>();
  final inherited = InteractionScope.maybeOf(context);
  final scheme = theme.colorScheme;
  final colors = tokens?.colors;
  final surfaces = tokens?.surfaces;
  return InteractionData(
    suite: style?.suite ?? inherited?.suite ?? InteractionSuite.standard,
    reduceMotion:
        (style?.reduceMotion ?? false) ||
        (inherited?.reduceMotion ?? false) ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        (tokens != null &&
            !tokens.motion.splashEnabled &&
            tokens.motion.surfaceEnter == Duration.zero),
    palette: InteractionPalette(
      brightness: tokens == null
          ? theme.brightness
          : tokens.isDark
          ? Brightness.dark
          : Brightness.light,
      accent: colors?.accent ?? scheme.primary,
      accentBright: colors?.accent ?? scheme.primary,
      onAccent: colors?.onAccent ?? scheme.onPrimary,
      selectedFill: surfaces?.selected.fill ?? scheme.secondaryContainer,
      surface: surfaces?.panel.fill ?? scheme.surface,
      raised: surfaces?.raised.fill ?? scheme.surfaceContainerHighest,
      border: surfaces?.panel.border ?? scheme.outline,
      textPrimary: colors?.textPrimary ?? scheme.onSurface,
      textSecondary: colors?.textSecondary ?? scheme.onSurfaceVariant,
      textDisabled: colors?.textDisabled ?? theme.disabledColor,
      focusRing: colors?.focusRing ?? scheme.primary,
      success: colors?.success ?? scheme.tertiary,
      onSuccess: colors?.onAccent ?? scheme.onTertiary,
      danger: colors?.danger ?? scheme.error,
      onDanger: colors?.onAccent ?? scheme.onError,
      warning: colors?.warning ?? scheme.secondary,
    ),
  );
}

/// Works below a navigator as well as at the eventual application boundary.
/// Routes follow this effective scope rather than taking a settings snapshot.
class StarBridgeInteractionConfiguration extends StatelessWidget {
  const StarBridgeInteractionConfiguration({
    required this.suite,
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final InteractionSuite suite;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Palette transitions may continue, but a user setting is discrete. An
    // AnimatedTheme can return its old ThemeData at t=0 before extension.lerp
    // runs; publish the current setting separately above the Navigator.
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (extension) => extension is! StarBridgeInteractionTheme,
          ),
          StarBridgeInteractionTheme(suite: suite, reduceMotion: reduceMotion),
        ],
      ),
      child: StarBridgeInteractionRegion(child: child),
    );
  }
}

class StarBridgeInteractionRegion extends StatelessWidget {
  const StarBridgeInteractionRegion({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => InteractionScope(
    data: resolveStarBridgeInteraction(context),
    child: child,
  );
}
