import 'package:flutter/material.dart';

import 'avionics_icon.dart';

enum WindowGlyph { minimize, maximize, restore, close, chat }

class WindowControlIcon extends StatelessWidget {
  const WindowControlIcon(this.glyph, {this.size = 15, super.key});
  final WindowGlyph glyph;
  final double size;
  @override
  Widget build(BuildContext context) =>
      AvionicsIcon('Window.${glyph.name}', size: size);
}
