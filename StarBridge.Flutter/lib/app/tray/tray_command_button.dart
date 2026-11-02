import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';

/// The tray's existing outlined-icon geometry with approved suite feedback.
/// The panel still owns command eligibility, pending guards and failures.
class TrayCommandButton extends StatelessWidget {
  const TrayCommandButton({
    required this.controlKey,
    required this.label,
    required this.icon,
    this.onPressed,
    this.style,
    super.key,
  });
  final Key controlKey;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final native = OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: icon,
      label: Text(label),
    );
    final effective = (style ?? const ButtonStyle())
        .merge(OutlinedButtonTheme.of(context).style)
        .merge(native.defaultStyleOf(context));
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final theme = Theme.of(context);
    final adjustment =
        (effective.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (effective.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final foreground = effective.foregroundColor?.resolve(states);
    final children = <Widget>[
      IconTheme.merge(
        data: IconThemeData(
          size: effective.iconSize?.resolve(states),
          color: effective.iconColor?.resolve(states) ?? foreground,
        ),
        child: icon,
      ),
      Flexible(
        child: Text(
          label,
          style: effective.textStyle
              ?.resolve(states)
              ?.copyWith(inherit: false, color: foreground),
        ),
      ),
    ];
    return StarBridgeActionButton(
      controlKey: controlKey,
      semanticLabel: label,
      nativeStyle: effective,
      minHeight: math.max(
        effective.minimumSize!.resolve(states)!.height + adjustment.dy,
        target + adjustment.dy,
      ),
      onActivate: onPressed == null ? null : (_) => onPressed!(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - (scale - 1) * 4,
        children: effective.iconAlignment == IconAlignment.end
            ? children.reversed.toList()
            : children,
      ),
    );
  }
}
