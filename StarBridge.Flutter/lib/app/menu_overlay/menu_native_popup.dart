import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../platform/window/native_viewport_visibility.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
export '../../design_system/interaction/starbridge_menu_anchor.dart'
    show StarBridgeMenuEntry;

/// Popup routes remain above native content through their exit animation, not
/// merely until Navigator.pop makes the underlying route current again.
class MenuNativePopupObserver extends NavigatorObserver {
  final _routes = <TransitionRoute<dynamic>>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && _routes.add(route)) {
      nativeViewportMenus.value++;
      route.completed.whenComplete(() => _release(route));
    }
  }

  void _release(TransitionRoute<dynamic> route) {
    if (_routes.remove(route)) nativeViewportMenus.value--;
  }

  void dispose() {
    for (final route in _routes.toList()) {
      _release(route);
    }
  }
}

/// Flutter popup layers may extend beyond their panel's clipped rectangle.
/// Use the existing native-viewport lease until the popup closes or disposes.
class MenuNativePopup extends StatelessWidget {
  const MenuNativePopup({
    super.key,
    this.style,
    this.identity,
    this.header,
    this.enabled = true,
    this.contextMenu = false,
    required this.label,
    required this.entries,
    required this.builder,
  });

  final MenuStyle? style;
  final Object? identity;
  final Widget? header;
  final bool enabled;
  final bool contextMenu;
  final String label;
  final List<StarBridgeMenuEntry> entries;
  final Widget Function(
    BuildContext,
    MenuController,
    FocusNode,
    ValueChanged<InteractionSource>,
  )
  builder;

  @override
  Widget build(BuildContext context) => NativeViewportMenu(
    key: identity == null ? null : ValueKey(identity),
    builder: (onOpen, onClose) => StarBridgeMenuAnchor(
      contextMenu: contextMenu,
      onOpen: onOpen,
      onClose: onClose,
      surfaceStyle: style,
      maximumSize: style?.maximumSize?.resolve({}),
      semanticLabel: label,
      header: header,
      enabled:
          enabled &&
          NativeViewportScope.isActive(context) &&
          (!contextMenu || TooltipVisibility.of(context)),
      retainExitContent:
          NativeViewportScope.isActive(context) &&
          (!contextMenu || TooltipVisibility.of(context)),
      entries: [
        for (final entry in entries)
          StarBridgeMenuEntry(
            id: entry.id,
            label: entry.label,
            child: entry.child,
            selected: entry.selected,
            controlKey: entry.controlKey,
            onActivate: entry.onActivate == null
                ? null
                : (source) => runStarBridgeSynchronousActivation(
                    source,
                    () => entry.onActivate!(source),
                  ),
          ),
      ],
      builder: (context, controller, focus, toggle) =>
          builder(context, controller, focus, toggle),
    ),
  );
}
