import 'package:flutter/material.dart';

// Colors used by the existing Windows overlay editor, independent of app theme.
Color overlayPreviewAccent(String theme) => Color(switch (theme) {
  'Anvil' => 0xff4effab,
  'Drake' => 0xffffb230,
  'Argo' => 0xffff8449,
  'Musashi' => 0xffffe480,
  'Mirai' => 0xff86e1ff,
  'Crusader' => 0xff6ecdff,
  'Aegis' => 0xff54f5e8,
  'Rsi' => 0xffd6c9ff,
  'Origin' => 0xffb0dbff,
  'Aopoa' => 0xff7effed,
  'Esperia' => 0xffff5c70,
  'Gatac' => 0xffffcde6,
  'NightShadow' => 0xffd61f35,
  'LagrangeWeave' => 0xfff0a76b,
  _ => 0xff53beff,
});

Color overlayCrosshairColor(String theme, bool useTheme, String hex) {
  final custom = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return useTheme || custom == null
      ? overlayPreviewAccent(theme)
      : Color(0xff000000 | custom);
}

Color overlayAppearancePreviewColor(String hex, {required Color fallback}) {
  final normalized = hex.trim().replaceFirst('#', '');
  if (normalized.length != 6) return fallback;
  final rgb = int.tryParse(normalized, radix: 16);
  return rgb == null ? fallback : Color(0xff000000 | rgb);
}
