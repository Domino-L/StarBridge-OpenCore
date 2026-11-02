import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../platform/window/native_viewport_visibility.dart';

/// Text-only menu hints hold their own native viewport lease while painted.
/// No window, workspace, focus or command ownership is moved into this module.
class MenuChromeHint extends StatelessWidget {
  const MenuChromeHint({
    required this.message,
    required this.child,
    this.visible = true,
    this.excludeFromSemantics = false,
    super.key,
  });
  final String message;
  final Widget child;
  final bool visible;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) => TooltipVisibility(
    visible:
        visible &&
        TooltipVisibility.of(context) &&
        NativeViewportScope.isActive(context),
    child: NativeViewportMenu(
      builder: (open, close) => StarBridgeTooltip(
        message: message,
        excludeFromSemantics: excludeFromSemantics,
        waitDuration:
            TooltipTheme.of(context).waitDuration ??
            const Duration(milliseconds: 450),
        onVisibilityChanged: (shown) => shown ? open() : close(),
        child: child,
      ),
    ),
  );
}

class MenuChromeIconAction extends StatelessWidget {
  const MenuChromeIconAction({
    required this.label,
    required this.icon,
    required this.controlKey,
    required this.onActivate,
    this.visible = true,
    super.key,
  });
  final String label;
  final Widget icon;
  final Key controlKey;
  final ValueChanged<InteractionSource>? onActivate;
  final bool visible;

  @override
  Widget build(BuildContext context) => TooltipVisibility(
    visible:
        visible &&
        TooltipVisibility.of(context) &&
        NativeViewportScope.isActive(context),
    child: NativeViewportMenu(
      builder: (open, close) => StarBridgeNativeIconAction(
        label: label,
        icon: icon,
        controlKey: controlKey,
        onActivate: onActivate,
        onHintVisibilityChanged: (shown) => shown ? open() : close(),
      ),
    ),
  );
}
