import 'package:flutter/material.dart';

import '../../platform/window/native_viewport_visibility.dart';

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
    required this.menuChildren,
    required this.builder,
  });

  final MenuStyle? style;
  final List<Widget> menuChildren;
  final Widget Function(BuildContext, MenuController, Widget?) builder;

  @override
  Widget build(BuildContext context) => NativeViewportMenu(
    builder: (onOpen, onClose) => MenuAnchor(
      onOpen: onOpen,
      onClose: onClose,
      style: style,
      menuChildren: menuChildren,
      builder: builder,
    ),
  );
}
