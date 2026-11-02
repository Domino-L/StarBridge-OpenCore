import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

/// Preserves the original FilledButton.icon public defaults and icon geometry.
class ApplicationSupportCheckAction extends StatelessWidget {
  const ApplicationSupportCheckAction({
    required this.controlKey,
    required this.label,
    required this.icon,
    this.onActivate,
    super.key,
  });
  final Key controlKey;
  final String label;
  final StarBridgeIconSemantic icon;
  final ValueChanged<InteractionSource>? onActivate;
  @override
  Widget build(BuildContext context) {
    final native = FilledButton.icon(
      onPressed: onActivate == null ? null : () {},
      icon: StarBridgeIcon(icon),
      label: const SizedBox.shrink(),
    );
    final style = (FilledButtonTheme.of(context).style ?? const ButtonStyle())
        .merge(native.defaultStyleOf(context));
    final states = <WidgetState>{if (onActivate == null) WidgetState.disabled};
    final theme = Theme.of(context);
    final adjustment =
        (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (style.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final foreground = style.foregroundColor?.resolve(states);
    final children = <Widget>[
      IconTheme.merge(
        data: IconThemeData(
          size: style.iconSize?.resolve(states),
          color: style.iconColor?.resolve(states) ?? foreground,
        ),
        child: StarBridgeIcon(icon),
      ),
      Flexible(
        child: Text(
          label,
          style: style.textStyle
              ?.resolve(states)
              ?.copyWith(inherit: false, color: foreground),
        ),
      ),
    ];
    return StarBridgeActionButton(
      kind: StarBridgeActionKind.primary,
      controlKey: controlKey,
      semanticLabel: label,
      nativeStyle: style,
      minHeight: math.max(
        style.minimumSize!.resolve(states)!.height + adjustment.dy,
        target + adjustment.dy,
      ),
      onActivate: onActivate,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - (scale - 1) * 4,
        children: style.iconAlignment == IconAlignment.end
            ? children.reversed.toList()
            : children,
      ),
    );
  }
}
