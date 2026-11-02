import 'package:flutter/material.dart';

/// 万圣节特别外观（"南瓜夜"，2026-10-29 定稿）用到的颜色。
///
/// 规则和圣诞一样：底色一种（夜紫）、按钮一种（南瓜橙）、通知小标不动；
/// 印花是淡淡的线稿，以月银为主，淡紫、橙、淡黄少量；不用红，也就没有红配金。
abstract final class HolidayHalloweenPalette {
  // 主色：按钮、侧栏选中项、链接、开关开启态。
  static const accentDark = Color(0xFFF2883A);
  static const accentSoftDark = Color(0xFF3A2410);
  static const onAccentDark = Color(0xFF1E0E02);
  static const focusRingDark = Color(0xFFFFB066);

  static const accentLight = Color(0xFFB8560F);
  static const accentSoftLight = Color(0xFFFBE6D3);
  static const onAccentLight = Color(0xFFFFFFFF);
  static const focusRingLight = Color(0xFFD9721F);

  // 底色：夜紫。布局和文字都不变。
  static const navigationDark = Color(0xFF120D1C);
  static const chromeDark = Color(0xFF171126);
  static const groundDark = Color(0xFF0B0812);
  static const lineDark = Color(0xFF2A2140);
  static const selectedDark = Color(0xFF3A2410);

  static const navigationLight = Color(0xFFF6F3FA);
  static const chromeLight = Color(0xFFFAF8FC);
  static const groundLight = Color(0xFFEEEAF4);
  static const lineLight = Color(0xFFD3CBE0);
  static const selectedLight = Color(0xFFFBE6D3);

  // 印花（深色底）：月银为主，淡紫蝙蝠、橙南瓜、淡黄月牙少量。
  static const printSilverDark = Color(0xFFD9D2F0);
  static const printLilacDark = Color(0xFFB9A3FF);
  static const printPumpkinDark = Color(0xFFF2883A);
  static const printMoonDark = Color(0xFFF3E3A8);

  // 印花（浅色底）：同样的图案，用更深的墨色才看得见。
  static const printSilverLight = Color(0xFF6B6386);
  static const printLilacLight = Color(0xFF7A5CC8);
  static const printPumpkinLight = Color(0xFFC2601A);
  static const printMoonLight = Color(0xFF9C8436);
}
