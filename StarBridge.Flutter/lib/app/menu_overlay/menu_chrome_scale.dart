import 'package:flutter/material.dart';

/// Scale menu chrome, not floating tools or their persisted window geometry.
/// The inverse layout constraint keeps all anchors inside the visible surface.
class MenuChromeScale extends StatelessWidget {
  const MenuChromeScale({
    super.key,
    required this.percent,
    required this.child,
  });
  final int percent;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scale = percent <= 0 ? 1.0 : percent / 100;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: constraints.maxWidth / scale,
            maxWidth: constraints.maxWidth / scale,
            minHeight: constraints.maxHeight / scale,
            maxHeight: constraints.maxHeight / scale,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
