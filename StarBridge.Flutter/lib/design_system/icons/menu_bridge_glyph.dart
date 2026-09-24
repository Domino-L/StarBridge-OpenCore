import 'package:flutter/material.dart';

import 'starbridge_icon.dart';
import 'icon_semantic.dart';

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
  Widget build(BuildContext context) {
    final semantic = switch (glyph) {
      MenuGlyph.close => StarBridgeIconSemantic.windowClose,
      MenuGlyph.refresh => StarBridgeIconSemantic.refresh,
      MenuGlyph.overlay => StarBridgeIconSemantic.overlay,
      MenuGlyph.group => StarBridgeIconSemantic.community,
      MenuGlyph.friends => StarBridgeIconSemantic.friends,
      MenuGlyph.room => StarBridgeIconSemantic.room,
      MenuGlyph.settings => StarBridgeIconSemantic.settings,
      MenuGlyph.ship => StarBridgeIconSemantic.hangar,
      MenuGlyph.location => StarBridgeIconSemantic.scene,
      MenuGlyph.server => StarBridgeIconSemantic.statusHost,
      _ => null,
    };
    if (semantic != null) {
      return StarBridgeIcon(semantic, size: size, color: color);
    }
    return Icon(
      switch (glyph) {
        MenuGlyph.close => Icons.close,
        MenuGlyph.search => Icons.search,
        MenuGlyph.refresh => Icons.refresh,
        MenuGlyph.addFriend => Icons.person_add_alt,
        MenuGlyph.next => Icons.chevron_right,
        MenuGlyph.down => Icons.expand_more,
        MenuGlyph.add => Icons.add,
        MenuGlyph.group => Icons.groups_outlined,
        MenuGlyph.person => Icons.person_outline,
        MenuGlyph.microphone => Icons.mic_none,
        MenuGlyph.headphones => Icons.headphones_outlined,
        MenuGlyph.room => Icons.meeting_room_outlined,
        MenuGlyph.ship => Icons.rocket_launch_outlined,
        MenuGlyph.location => Icons.location_on_outlined,
        MenuGlyph.server => Icons.dns_outlined,
        MenuGlyph.desktop => Icons.desktop_windows_outlined,
        MenuGlyph.settings => Icons.settings_outlined,
        MenuGlyph.overlay => Icons.view_sidebar_outlined,
        MenuGlyph.friends => Icons.people_outline,
        MenuGlyph.chat => Icons.chat_bubble_outline,
        MenuGlyph.camera => Icons.photo_camera_outlined,
        MenuGlyph.image => Icons.image_outlined,
        MenuGlyph.browser => Icons.language,
      },
      size: size,
      color: color,
    );
  }
}
