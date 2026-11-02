import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

/// Keeps the original outlined-icon message target and badge geometry.
/// The page still owns permission, routing, conversation identity and drafts.
class FriendMessageAction extends StatelessWidget {
  const FriendMessageAction({
    required this.controlKey,
    required this.label,
    required this.unread,
    this.onPressed,
    super.key,
  });
  final Key controlKey;
  final String label;
  final int unread;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const icon = StandardIcon(StandardIconSemantic.chatBubble, size: 16);
    final native = OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: const SizedBox.shrink(),
    );
    final style = (OutlinedButtonTheme.of(context).style ?? const ButtonStyle())
        .merge(native.defaultStyleOf(context));
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
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
        child: icon,
      ),
      Flexible(
        child: AttentionBadge(
          count: unread,
          child: Text(
            label,
            style: style.textStyle
                ?.resolve(states)
                ?.copyWith(inherit: false, color: foreground),
          ),
        ),
      ),
    ];
    return StarBridgeActionButton(
      controlKey: controlKey,
      semanticLabel: '$label${unread > 0 ? '\n$unread' : ''}',
      nativeStyle: style,
      minHeight: math.max(
        style.minimumSize!.resolve(states)!.height + adjustment.dy,
        target + adjustment.dy,
      ),
      onActivate: onPressed == null ? null : (_) => onPressed!(),
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
