import 'dart:ui';

/// Accepted Trading Hall state/line colors; preserves the existing dark/light artwork.
abstract final class MarketplacePalette {
  static const success = Color(0xff239c79);

  /// A followed item's heart (watch tab, user 2026-10-20: "心形应该是红色的").
  static const heart = Color(0xffe5484d);
  // Text on [heart] (unread counts in 交易消息).
  static const onHeart = Color(0xffffffff);
  static const warning = Color(0xffb47c17);
  static const warningSoft = Color(0x20b47c17);
  static const warningBorder = Color(0x60b47c17);
  static const lineDark = Color(0xff1d2933);
  static const lineLight = Color(0xffc6d1d9);
  static const attention = Color(0xffffb73d);
  static const buyer = Color(0xff9870cc);

  // Diagonal reskin (2026-10-18/20), the accepted hall look.
  /// Money, quality and barter accents.
  static const gold = Color(0xFFF5B544);

  /// Ink on gold fills (badges, solid tags).
  static const onGold = Color(0xFF1A1204);
  static const onGoldTag = Color(0xFF14100A);

  /// Ink on accent fills (slanted drawer buttons).
  static const onAccent = Color(0xFF06121B);

  /// SCM plate in the banner: its orange stripe, light ground and ink.
  static const scmOrange = Color(0xFFFF9000);
  static const plateTop = Color(0xFFE6EDF2);
  static const plateBottom = Color(0xFFCFDBE3);
  static const plateInk = Color(0xFF26343E);
  static const plateSubtle = Color(0xFF4D5E69);

  /// Dark banner glass and the tabs bar under it.
  static const bannerTop = Color(0x6B42607A);
  static const bannerBottom = Color(0xCC16232F);
  static const tabsBar = Color(0xB80A1118);

  /// Glass slabs between the plate and the stats.
  static const glass = Color(0xFF96C8EB);
  static const glassEdge = Color(0xFFC8E6FA);

  /// Hover drawer ground (dark) and the plain backdrop behind item photos.
  static const drawerDark = Color(0xFF14202B);
  static const artBackdrop = Color(0xFF070D13);

  // 极品 quality foil (user 2026-10-23): a holographic band, a warm glow and
  // a white sheen; [foilInk] is the text on it.
  static const foil = [
    Color(0xFFFFE08A),
    Color(0xFFF7B955),
    Color(0xFFFF8FB1),
    Color(0xFFB69CFF),
    Color(0xFF7EE7F2),
    Color(0xFFFFE08A),
  ];
  static const foilInk = Color(0xFF1A1206);
  static const foilGlow = Color(0x73FFBE6E);
  static const foilSheen = [
    Color(0x00FFFFFF),
    Color(0xA6FFFFFF),
    Color(0x00FFFFFF),
  ];

  // 走势页 (10-28): the dashed buy-average line and the hover tooltip shadow.
  static const trendBuy = Color(0xFFB497FF);
  static const trendShadow = Color(0x73000000);
}
