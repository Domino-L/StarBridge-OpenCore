import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

/// Feature-local adapter: native public button geometry, approved suite paint.
/// Business callbacks and availability remain at the original call sites.
class HelpSupportAction extends StatelessWidget {
  const HelpSupportAction({
    required this.controlKey,
    required this.child,
    this.kind = StarBridgeActionKind.quiet,
    this.icon,
    this.onActivate,
    super.key,
  }) : assert(
         kind == StarBridgeActionKind.quiet ||
             kind == StarBridgeActionKind.secondary ||
             kind == StarBridgeActionKind.primary,
       );
  final Key controlKey;
  final Widget child;
  final StarBridgeActionKind kind;
  final StarBridgeIconSemantic? icon;
  final ValueChanged<InteractionSource>? onActivate;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? enabled = onActivate == null ? null : () {};
    final ButtonStyleButton native = switch ((kind, icon)) {
      (StarBridgeActionKind.primary, null) => FilledButton(
        onPressed: enabled,
        child: child,
      ),
      (StarBridgeActionKind.primary, final glyph?) => FilledButton.icon(
        onPressed: enabled,
        icon: StarBridgeIcon(glyph),
        label: child,
      ),
      (StarBridgeActionKind.secondary, null) => OutlinedButton(
        onPressed: enabled,
        child: child,
      ),
      (StarBridgeActionKind.secondary, final glyph?) => OutlinedButton.icon(
        onPressed: enabled,
        icon: StarBridgeIcon(glyph),
        label: child,
      ),
      (_, null) => TextButton(onPressed: enabled, child: child),
      (_, final glyph?) => TextButton.icon(
        onPressed: enabled,
        icon: StarBridgeIcon(glyph),
        label: child,
      ),
    };
    final defaults = switch (native) {
      FilledButton button => button.defaultStyleOf(context),
      OutlinedButton button => button.defaultStyleOf(context),
      TextButton button => button.defaultStyleOf(context),
      _ => throw StateError('Unsupported help action'),
    };
    final style =
        ((switch (kind) {
                  StarBridgeActionKind.primary => FilledButtonTheme.of(
                    context,
                  ).style,
                  StarBridgeActionKind.secondary => OutlinedButtonTheme.of(
                    context,
                  ).style,
                  _ => TextButtonTheme.of(context).style,
                }) ??
                const ButtonStyle())
            .merge(defaults);
    final states = <WidgetState>{if (enabled == null) WidgetState.disabled};
    final theme = Theme.of(context);
    final adjustment =
        (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (style.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final foreground = style.foregroundColor?.resolve(states);
    final label = DefaultTextStyle.merge(
      style: style.textStyle
          ?.resolve(states)
          ?.copyWith(inherit: false, color: foreground),
      child: child,
    );
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final children = <Widget>[
      if (icon case final glyph?)
        IconTheme.merge(
          data: IconThemeData(
            size: style.iconSize?.resolve(states),
            color: style.iconColor?.resolve(states) ?? foreground,
          ),
          child: StarBridgeIcon(glyph),
        ),
      Flexible(child: label),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: math.max(
          style.minimumSize!.resolve(states)!.width + adjustment.dx,
          target + adjustment.dx,
        ),
      ),
      child: StarBridgeActionButton(
        kind: kind,
        controlKey: controlKey,
        nativeStyle: style,
        minHeight: math.max(
          style.minimumSize!.resolve(states)!.height + adjustment.dy,
          target + adjustment.dy,
        ),
        onActivate: onActivate,
        child: icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8 - (scale - 1) * 4,
                children: style.iconAlignment == IconAlignment.end
                    ? children.reversed.toList()
                    : children,
              ),
      ),
    );
  }
}
