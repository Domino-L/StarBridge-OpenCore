import 'package:flutter/material.dart';

import '../tokens/starbridge_tokens.dart';

enum ActionTone { danger, warning, success, info }

enum ActionEmphasis { text, outlined, filled }

/// Override only semantic color states; retain shared sizing, shape and motion.
ButtonStyle semanticActionStyle(
  BuildContext context,
  ActionTone tone, {
  ActionEmphasis emphasis = ActionEmphasis.text,
}) {
  final tokens = context.tokens;
  final colors = tokens.colors;
  final color = switch (tone) {
    ActionTone.danger => colors.danger,
    ActionTone.warning => colors.warning,
    ActionTone.success => colors.success,
    ActionTone.info => colors.info,
  };
  final filled = emphasis == ActionEmphasis.filled;
  final foreground = filled ? colors.onAccent : color;
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.textDisabled
          : foreground,
    ),
    backgroundColor: filled
        ? WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.surfaces.raised.fill
                : color,
          )
        : null,
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      final alpha = states.contains(WidgetState.pressed)
          ? .20
          : states.contains(WidgetState.focused)
          ? .14
          : states.contains(WidgetState.hovered)
          ? .09
          : .0;
      return foreground.withValues(alpha: alpha);
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return emphasis == ActionEmphasis.outlined
            ? BorderSide(color: tokens.surfaces.panel.border)
            : BorderSide.none;
      }
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: filled ? colors.onAccent : color, width: 2);
      }
      return emphasis == ActionEmphasis.outlined
          ? BorderSide(color: color)
          : BorderSide.none;
    }),
  );
}
