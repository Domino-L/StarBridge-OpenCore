import 'package:flutter/material.dart';

/// 圣诞特别外观（H3 定稿，2026-10-29）用到的颜色。
///
/// 规则：底色一种（略偏冷的星桥深色）、按钮一种（暖金）、通知小标不动；
/// 印花是细线稿，以雪银为主，金、红、绿只占少量，并且红不和金挨在一起。
abstract final class HolidayXmasPalette {
  // 主色：按钮、侧栏选中项、链接、开关开启态。
  static const accentDark = Color(0xFFE8B65A);
  static const accentSoftDark = Color(0xFF3A2E14);
  static const onAccentDark = Color(0xFF1F1604);
  static const focusRingDark = Color(0xFFF3D27A);

  static const accentLight = Color(0xFF9A6A10);
  static const accentSoftLight = Color(0xFFF6EBD0);
  static const onAccentLight = Color(0xFFFFFFFF);
  static const focusRingLight = Color(0xFFC48A1A);

  // 底色：只比平时略冷一点，布局和文字都不变。
  static const navigationDark = Color(0xFF0B131B);
  static const chromeDark = Color(0xFF0F1A24);
  static const groundDark = Color(0xFF070C12);
  static const lineDark = Color(0xFF22313D);
  static const selectedDark = Color(0xFF3A2E14);

  static const navigationLight = Color(0xFFF3F7FA);
  static const chromeLight = Color(0xFFF8FBFC);
  static const groundLight = Color(0xFFEAF0F4);
  static const lineLight = Color(0xFFC6D2D9);
  static const selectedLight = Color(0xFFF6EBD0);

  // 印花（深色底）：雪银为主，金、红、绿少量。
  static const printSilverDark = Color(0xFFDDE9F2);
  static const printGoldDark = Color(0xFFE8C66A);
  static const printRed = Color(0xFFE0453C);
  static const printGreenDark = Color(0xFF56C287);

  // 印花（浅色底）：同样的图案，用更深的墨色才看得见。
  static const printSilverLight = Color(0xFF5B7388);
  static const printGoldLight = Color(0xFFB08A2E);
  static const printGreenLight = Color(0xFF2E8E5F);
}
