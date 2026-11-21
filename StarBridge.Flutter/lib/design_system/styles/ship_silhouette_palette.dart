import 'dart:ui';

/// Holographic ship silhouette: one blue body with a lighter raised area.
/// Blue means a friendly ship on the command table; only appearance mode varies.
abstract final class ShipSilhouettePalette {
  static const dark = [Color(0xFF7CC3EA), Color(0xFF2C82CA)];
  static const light = [Color(0xFF2F7FBE), Color(0xFF175C97)];
  static const raised = Color(0x1FFFFFFF);
  static const halo = Color(0x4D8ED8FF);
  static const scan = Color(0xB3FFFFFF);
}
