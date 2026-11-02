import 'package:flutter/material.dart';

/// Placement grip retaining its native Material glyph and IconTheme behavior.
class MenuHudDragHandleIcon extends StatelessWidget {
  const MenuHudDragHandleIcon({
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.drag_indicator,
    size: size,
    color: color,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
  );
}
