import 'dart:ui';

/// Accepted paired achievement artwork keeps its dark backing in both themes.
/// The neutral fallback belongs to the artwork, rather than app status colors.
abstract final class AchievementArtPalette {
  static const background = Color(0xFF101214);
  static const fallbackIcon = Color(0xFFB9BEC2);
}
