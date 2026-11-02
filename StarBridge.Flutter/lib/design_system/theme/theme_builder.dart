import 'package:flutter/material.dart';

import '../tokens/starbridge_tokens.dart';
import '../interaction/starbridge_interaction_theme.dart';

ThemeData buildStarBridgeTheme(
  StarBridgeTokens tokens,
  Locale locale, {
  InteractionSuite interactionSuite = InteractionSuite.standard,
}) {
  final theme = _buildTheme(tokens, locale, interactionSuite);
  // Material fills the styles this theme does not declare, such as the
  // bodyLarge of a checkbox title. They take the same digits and width.
  final declared = theme.textTheme.bodyMedium;
  TextStyle? same(TextStyle? style) => style?.copyWith(
    fontFeatures: declared?.fontFeatures,
    fontVariations: declared?.fontVariations,
  );
  final text = theme.textTheme;
  return theme.copyWith(
    textTheme: text.copyWith(
      displayLarge: same(text.displayLarge),
      displayMedium: same(text.displayMedium),
      headlineLarge: same(text.headlineLarge),
      headlineMedium: same(text.headlineMedium),
      titleSmall: same(text.titleSmall),
      bodyLarge: same(text.bodyLarge),
      labelSmall: same(text.labelSmall),
    ),
  );
}

ThemeData _buildTheme(
  StarBridgeTokens tokens,
  Locale locale,
  InteractionSuite interactionSuite,
) {
  final colors = tokens.colors;
  final surfaces = tokens.surfaces;
  final typography = tokens.typography;
  final fallback = typography.fallbacksFor(locale);
  final brightness = tokens.isDark ? Brightness.dark : Brightness.light;

  // QualityPass ④ (user 2026-10-29): light text on a dark ground reads
  // heavier, so dark mode drops one step on the variable wght axis — body
  // 400 → 380, titles 600 → 560. Light mode keeps the token weights.
  FontWeight tuned(FontWeight weight) {
    if (!tokens.isDark) return weight;
    final value = weight.value;
    return FontWeight(value >= 550 ? value - 40 : value - 20);
  }

  // Saira at full width runs about 9% wider than Source Sans 3 in English.
  // 88 on its width axis runs about 2% under the old width, so wrapped text still fits.
  final latinWidth = locale.languageCode.toLowerCase() == 'zh'
      ? null
      : typography.latinUiWidthAxis;

  TextStyle ui(
    double size, {
    FontWeight? weight,
    Color? color,
    double? height,
    double? tracking,
    String? family,
  }) {
    return TextStyle(
      fontFamily: family ?? typography.uiFamily,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: tuned(weight ?? typography.bodyWeight),
      color: color ?? colors.textPrimary,
      height: height,
      letterSpacing: tracking,
      // QualityPass ①: digits are equal width everywhere, so prices, counts
      // and timers do not shift sideways when they change.
      fontFeatures: const [FontFeature.tabularFigures()],
      fontVariations: latinWidth == null
          ? null
          : [FontVariation('wdth', latinWidth)],
    );
  }

  final textTheme = TextTheme(
    displaySmall: ui(
      typography.display,
      family: typography.headingFamily,
      weight: typography.displayWeight,
      tracking: typography.displayTracking,
      height: 1.18,
    ),
    headlineSmall: ui(
      typography.headline,
      family: typography.headingFamily,
      weight: typography.displayWeight,
      height: 1.24,
    ),
    titleLarge: ui(
      typography.title,
      family: typography.headingFamily,
      weight: typography.titleWeight,
      height: 1.3,
    ),
    titleMedium: ui(
      typography.titleSmall,
      family: typography.headingFamily,
      weight: typography.emphasisWeight,
      height: 1.34,
    ),
    bodyMedium: ui(typography.body, height: typography.bodyHeight),
    bodySmall: ui(
      typography.bodySmall,
      color: colors.textSecondary,
      height: typography.bodyHeight,
    ),
    labelLarge: ui(typography.label, weight: typography.emphasisWeight),
    labelMedium: ui(typography.label, color: colors.textSecondary),
  );

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        surface: surfaces.panel.fill,
        onSurface: colors.textPrimary,
        surfaceContainerHighest: surfaces.raised.fill,
        error: colors.danger,
        onError: colors.onAccent,
        outline: surfaces.panel.border,
        outlineVariant: surfaces.ground.border,
      );

  final focusSide = BorderSide(
    color: colors.focusRing,
    width: tokens.stroke.focusWidth,
  );

  WidgetStateProperty<BorderSide?> statefulSide(BorderSide rest) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return focusSide;
      }
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: surfaces.ground.border,
          width: tokens.stroke.regular,
        );
      }
      return rest;
    });
  }

  WidgetStateProperty<Color?> overlay(Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: 0.20);
      }
      if (states.contains(WidgetState.focused)) {
        return base.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered)) {
        return base.withValues(alpha: 0.09);
      }
      return null;
    });
  }

  final controlShape = RoundedRectangleBorder(borderRadius: tokens.shape.small);

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: typography.uiFamily,
    fontFamilyFallback: fallback,
    scaffoldBackgroundColor: surfaces.ground.fill,
    canvasColor: surfaces.panel.fill,
    dividerColor: surfaces.ground.border,
    textTheme: textTheme,
    splashFactory: tokens.motion.splashEnabled
        ? InkRipple.splashFactory
        : NoSplash.splashFactory,
    focusColor: colors.focusRing.withValues(alpha: 0.14),
    hoverColor: colors.accent.withValues(alpha: 0.07),
    dividerTheme: DividerThemeData(
      color: surfaces.ground.border,
      thickness: tokens.stroke.hairline,
      space: tokens.stroke.hairline,
    ),
    iconTheme: IconThemeData(
      color: colors.textSecondary,
      size: tokens.icons.medium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaces.raised.fill,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textDisabled),
      labelStyle: textTheme.bodySmall,
      border: OutlineInputBorder(
        borderRadius: tokens.shape.small,
        borderSide: BorderSide(
          color: surfaces.panel.border,
          width: tokens.stroke.regular,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: tokens.shape.small,
        borderSide: BorderSide(
          color: surfaces.panel.border,
          width: tokens.stroke.regular,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: tokens.shape.small,
        borderSide: focusSide,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: tokens.shape.small,
        borderSide: BorderSide(
          color: colors.danger,
          width: tokens.stroke.strong,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(0, tokens.density.controlHeight),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: tokens.space.md),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? surfaces.raised.fill
              : colors.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? colors.textDisabled
              : colors.onAccent;
        }),
        overlayColor: overlay(colors.onAccent),
        side: statefulSide(BorderSide.none),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(0, tokens.density.controlHeight),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: tokens.space.md),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? colors.textDisabled
              : colors.textPrimary;
        }),
        overlayColor: overlay(colors.accent),
        side: statefulSide(
          BorderSide(
            color: surfaces.panel.border,
            width: tokens.stroke.regular,
          ),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(0, tokens.density.controlHeight),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: tokens.space.sm),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? colors.textDisabled
              : colors.accent;
        }),
        overlayColor: overlay(colors.accent),
        side: statefulSide(BorderSide.none),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size.square(tokens.density.controlHeight),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? colors.textDisabled
              : colors.textSecondary;
        }),
        overlayColor: overlay(colors.accent),
        side: statefulSide(
          BorderSide(
            color: surfaces.ground.border,
            width: tokens.stroke.regular,
          ),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: tokens.motion.tooltipDelay,
      decoration: BoxDecoration(
        color: surfaces.floating.fill,
        border: Border.all(
          color: surfaces.floating.border,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.small,
        boxShadow: surfaces.floating.shadows,
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: colors.textPrimary),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.floating.fill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.shape.large,
        side: BorderSide(
          color: surfaces.floating.border,
          width: tokens.stroke.regular,
        ),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.floating.fill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.shape.small,
        side: BorderSide(
          color: surfaces.floating.border,
          width: tokens.stroke.regular,
        ),
      ),
      textStyle: textTheme.bodyMedium,
      shadowColor: colors.scrim,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thickness: WidgetStatePropertyAll(tokens.space.xs),
      radius: Radius.circular(tokens.shape.radiusSmall),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered)
            ? surfaces.panel.border
            : surfaces.ground.border;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: surfaces.raised.fill,
      circularTrackColor: surfaces.raised.fill,
    ),
    extensions: <ThemeExtension<dynamic>>[
      tokens,
      StarBridgeInteractionTheme(
        suite: interactionSuite,
        reduceMotion:
            !tokens.motion.splashEnabled &&
            tokens.motion.surfaceEnter == Duration.zero,
      ),
    ],
  );
}
