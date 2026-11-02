import 'package:flutter/material.dart';

/// Keeps the existing heart affordance and glyph selection in the icon layer.
class FavoriteIcon extends StatelessWidget {
  const FavoriteIcon({required this.selected, this.size, this.color, super.key});

  final bool selected;
  final double? size;

  /// The trading hall paints a followed item's heart red (user, 2026-10-20).
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    selected ? Icons.favorite : Icons.favorite_border,
    size: size,
    color: color,
  );
}
