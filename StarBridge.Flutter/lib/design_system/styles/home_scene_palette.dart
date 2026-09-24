import 'dart:ui';

/// Accepted cinematic backdrop and text contrast, not theme surface colors.
abstract final class HomeScenePalette {
  static const scrimStrong = Color(0xB8071118);
  static const scrimSoft = Color(0x28071118);
  static const scrimClear = Color(0x00071118);
  static const textShadow = Color(0xCC000000);
  static const base = Color(0xFF071118);
  static const fallbackStart = Color(0xFF102C39);
  static const fallbackEnd = Color(0xFF08131A);
}
