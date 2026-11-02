import 'package:flutter/material.dart';

// Keep the toolbar subtree mounted when a live preference interrupts its fade.
// A duration-only change does not finish an already running implicit animation.
class MenuHudPlacementToolbarOpacity extends ImplicitlyAnimatedWidget {
  const MenuHudPlacementToolbarOpacity({
    required this.opacity,
    required this.reduceMotion,
    required this.child,
    super.key,
  }) : super(
         duration: reduceMotion
             ? Duration.zero
             : const Duration(milliseconds: 150),
       );

  final double opacity;
  final bool reduceMotion;
  final Widget child;

  @override
  AnimatedWidgetBaseState<MenuHudPlacementToolbarOpacity> createState() =>
      _PlacementToolbarOpacityState();
}

class _PlacementToolbarOpacityState
    extends AnimatedWidgetBaseState<MenuHudPlacementToolbarOpacity> {
  Tween<double>? _opacity;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _opacity = visitor(
      _opacity,
      widget.opacity,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  void didUpdateWidget(MenuHudPlacementToolbarOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) controller.value = 1;
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity!.animate(animation),
    child: widget.child,
  );
}
