import 'dart:ui';

/// The visor's fixed colours (OverlayVisorStyle): the status cyan and text are
/// the default palette's and never follow the colour setting (11-12 "颜色应该
/// 影响背景，不应该影响状态色"); only [OverlayVisorSimPainter] decoration does.
abstract final class OverlayVisorSimColors {
  static const ink = Color(0xFFEBF7FF);
  static const accent = Color(0xFF53BEFF);
  static const ok = Color(0xFF7DFFB0);
  static const warn = Color(0xFFFFC46B);

  /// The rally body's warm white (OverlayVisorStyle.Warm).
  static const warm = Color(0xFFFFF2E0);
  static const bad = Color(0xFFFF8C78);
  static const place = Color(0xFFC8F1FF);
  static const server = Color(0xFFB9A2FF);
  static const healthHigh = Color(0xFFCCF2FF);
  static final dim = Color.fromRGBO(
    (0xEB * 0.88).round(),
    (0xF7 * 0.9).round(),
    (0xFF * 0.94).round(),
    0.86,
  );
  static final quiet = ink.withValues(alpha: 0.78);

  static Color tone(String tone) => switch (tone) {
    'Place' => place,
    'Server' => server,
    'SameServer' || 'Good' => ok,
    'Bad' => bad,
    'Reminder' => warn,
    _ => accent,
  };
}

/// The other colours the editor's simplified visor panels use: the visor's
/// default decoration (before the Host answers), the "示例数据" mark and the
/// thin dark edge under the text.
abstract final class OverlayVisorSimPalette {
  static const defaultDecoration = Color(0xFF53BEFF);
  static const sampleMark = Color(0xFFFFD479);
  static const textEdge = Color(0xCC000000);

  /// The solid plate behind a block at a high background opacity: the
  /// decoration colour's own dark, as the visor's
  /// OverlayVisorRenderer.PlateColor (m102b, 11-18 user: "保持主题色不脏").
  static Color plate(Color decoration) => Color.from(
    alpha: 1,
    red: decoration.r * plateShade,
    green: decoration.g * plateShade,
    blue: decoration.b * plateShade,
  );

  /// How dark the plate is against its decoration colour (the visor's
  /// OverlayVisorRenderer.PlateShade).
  static const plateShade = 0.09;

  /// The dark text on the sample rally's yellow mark.
  static const markText = Color(0xFF05090D);

  /// The editors' overlap warning (m102): its dark red-black plate and its
  /// warm body text, under the visor's red title and outline.
  static const warningPlate = Color(0xE6140808);
  static const warningText = Color(0xFFF0E4DC);

  /// An opaque colour from a 24-bit RGB value (the Host's "#RRGGBB").
  static Color opaque(int rgb) => Color(0xFF000000 | (rgb & 0xFFFFFF));
}
