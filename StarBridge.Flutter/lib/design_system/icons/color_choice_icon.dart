import 'package:flutter/material.dart';

/// Standard color and selection glyphs, kept behind the design-system boundary.
class ColorChoiceIcon extends StatelessWidget {
  const ColorChoiceIcon.palette({super.key, this.size = 18}) : selected = null;
  const ColorChoiceIcon.selection({
    required bool this.selected,
    super.key,
    this.size = 16,
  });

  final bool? selected;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(switch (selected) {
    null => Icons.palette_outlined,
    true => Icons.check,
    false => Icons.remove,
  }, size: size);
}
