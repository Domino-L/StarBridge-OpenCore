import 'package:flutter/material.dart';

import '../tokens/starbridge_tokens.dart';

ThemeData buildStarBridgeTheme(StarBridgeTokens tokens, Locale locale) {
  final colors = tokens.colors;
  final surfaces = tokens.surfaces;
  final typography = tokens.typography;
  final fallback = typography.fallbacksFor(locale);
  final brightness = tokens.isDark ? Brightness.dark : Brightness.light;

  TextStyle ui(
    double size, {
    FontWeight? weight,
    Color? color,
    double? height,
    double? tracking,
  }) {
    return TextStyle(
      fontFamily: typography.uiFamily,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: weight ?? typography.bodyWeight,
      color: color ?? colors.textPrimary,
      height: height,
      letterSpacing: tracking,
    );
  }

  final textTheme = TextTheme(
    displaySmall: ui(
      typography.display,
      weight: typography.displayWeight,
      tracking: typography.displayTracking,
      height: 1.18,
    ),
    headlineSmall: ui(
      typography.headline,
      weight: typography.displayWeight,
      height: 1.24,
    ),
    titleLarge: ui(
      typography.title,
      weight: typography.titleWeight,
      height: 1.3,
    ),
    titleMedium: ui(
      typography.titleSmall,
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
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}
