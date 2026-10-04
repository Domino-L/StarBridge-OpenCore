import 'package:flutter/material.dart';

import 'avionics_icon.dart';

enum MenuGlyph {
  close,
  search,
  refresh,
  addFriend,
  next,
  down,
  add,
  group,
  person,
  microphone,
  headphones,
  room,
  ship,
  location,
  server,
  desktop,
  settings,
  overlay,
  friends,
  chat,
  camera,
  image,
  browser,
}

class MenuGlyphView extends StatelessWidget {
  const MenuGlyphView(this.glyph, {super.key, this.size = 20, this.color});
  final MenuGlyph glyph;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      AvionicsIcon('Menu.${glyph.name}', size: size, color: color);
}
