import 'dart:ui';

/// Main fleet "mirrored holo deck" header (direction 4, accepted 2026-10-21).
/// Fixed glass, deck and light colors of the approved render; values unchanged.
abstract final class OfficialFleetHoloPalette {
  static const clearWhite = Color(0x00FFFFFF);
  static const sweepWhite = Color(0xBFFFFFFF);
  static const glassLight = Color(0xFFF8FBFD);
  static const glassDark = Color(0xFF060C12);
  static const highlight = Color(0xFFFFFFFF);

  static const deckLight = [Color(0xFFE3E9EE), Color(0xFFCFD8DF)];
  static const deckDark = [Color(0xFF13212C), Color(0xFF0B141C)];
  static const deckEdge = Color(0x66C8E6FA);
  static const deckGlow = [Color(0x2996C8EB), Color(0x0596C8EB)];

  static const fadeOpaque = Color(0xFF000000);
  static const fadeHalf = Color(0x80000000);
  static const fadeClear = Color(0x00000000);

  static const outlineLight = Color(0x66142838);
  static const outlineDark = Color(0x6BFFFFFF);
}
