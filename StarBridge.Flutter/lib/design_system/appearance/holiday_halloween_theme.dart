import 'package:flutter/material.dart';

import '../styles/holiday_halloween_palette.dart';
import '../tokens/color_tokens.dart';
import 'holiday_theme.dart';
import 'surface_print.dart';

/// 万圣节（"南瓜夜"定稿）。生效 10-24 到 11-01：夜紫底、南瓜橙按钮，
/// 印花是蛛网、蝙蝠、南瓜和月牙。
final HolidayTheme halloweenHolidayTheme = HolidayTheme(
  id: 'halloween',
  start: HolidayDate(10, 24),
  end: HolidayDate(11, 1),
  iconVariant: 'halloween',
  blessingKey: 'home.holiday.halloween',
  // 34 像素的星标在普通缩放下脸太小，绿色糊成一片，小图把绿色去掉（和任务栏图标同一个规则）。
  mark: const HolidayMarkArt(
    darkSurface: 'assets/brand/holiday/halloween_mark_dark_surface.png',
    lightSurface: 'assets/brand/holiday/halloween_mark_light_surface.png',
    smallDarkSurface:
        'assets/brand/holiday/halloween_mark_small_dark_surface.png',
    smallLightSurface:
        'assets/brand/holiday/halloween_mark_small_light_surface.png',
  ),
  dark: HolidayPalette(
    accent: HolidayHalloweenPalette.accentDark,
    accentSoft: HolidayHalloweenPalette.accentSoftDark,
    onAccent: HolidayHalloweenPalette.onAccentDark,
    focusRing: HolidayHalloweenPalette.focusRingDark,
    navigation: HolidayHalloweenPalette.navigationDark,
    chrome: HolidayHalloweenPalette.chromeDark,
    ground: HolidayHalloweenPalette.groundDark,
    line: HolidayHalloweenPalette.lineDark,
    selected: HolidayHalloweenPalette.selectedDark,
  ),
  light: HolidayPalette(
    accent: HolidayHalloweenPalette.accentLight,
    accentSoft: HolidayHalloweenPalette.accentSoftLight,
    onAccent: HolidayHalloweenPalette.onAccentLight,
    focusRing: HolidayHalloweenPalette.focusRingLight,
    navigation: HolidayHalloweenPalette.navigationLight,
    chrome: HolidayHalloweenPalette.chromeLight,
    ground: HolidayHalloweenPalette.groundLight,
    line: HolidayHalloweenPalette.lineLight,
    selected: HolidayHalloweenPalette.selectedLight,
  ),
  printDark: _halloweenPrintDark,
  printLight: _halloweenPrintLight,
);

// 浓淡和圣诞一样。
const _halloweenOpacityDark = {
  SurfaceRole.navigation: .16,
  SurfaceRole.chrome: .09,
  SurfaceRole.ground: .11,
};
const _halloweenOpacityLight = {
  SurfaceRole.navigation: .12,
  SurfaceRole.chrome: .07,
  SurfaceRole.ground: .08,
};

final _halloweenPrintDark = SurfacePrintSpec(
  tileWidth: 240,
  tileHeight: 210,
  opacity: _halloweenOpacityDark,
  stamps: _halloweenStamps(
    silver: HolidayHalloweenPalette.printSilverDark,
    lilac: HolidayHalloweenPalette.printLilacDark,
    pumpkin: HolidayHalloweenPalette.printPumpkinDark,
    moon: HolidayHalloweenPalette.printMoonDark,
  ),
);

final _halloweenPrintLight = SurfacePrintSpec(
  tileWidth: 240,
  tileHeight: 210,
  opacity: _halloweenOpacityLight,
  stamps: _halloweenStamps(
    silver: HolidayHalloweenPalette.printSilverLight,
    lilac: HolidayHalloweenPalette.printLilacLight,
    pumpkin: HolidayHalloweenPalette.printPumpkinLight,
    moon: HolidayHalloweenPalette.printMoonLight,
  ),
);

// 一块 240×210 的印花；顺序就是绘制顺序。月银的图案最多。
List<PrintStamp> _halloweenStamps({
  required Color silver,
  required Color lilac,
  required Color pumpkin,
  required Color moon,
}) => [
  PrintStamp(PrintMotif.cobweb, dx: 34, dy: 38, size: 17, color: silver),
  PrintStamp(PrintMotif.cobweb, dx: 182, dy: 158, size: 10, color: silver),
  PrintStamp(PrintMotif.dot, dx: 120, dy: 22, size: 1.3, color: silver),
  PrintStamp(PrintMotif.dot, dx: 62, dy: 192, size: 1.2, color: silver),
  PrintStamp(PrintMotif.dot, dx: 226, dy: 70, size: 1.4, color: silver),
  PrintStamp(PrintMotif.star, dx: 100, dy: 96, size: 4.5, color: silver),
  PrintStamp(PrintMotif.bat, dx: 150, dy: 62, size: .9, color: lilac),
  PrintStamp(PrintMotif.bat, dx: 70, dy: 128, size: .6, color: lilac),
  PrintStamp(PrintMotif.bat, dx: 218, dy: 118, size: .5, color: lilac),
  PrintStamp(PrintMotif.moon, dx: 206, dy: 28, size: 9, color: moon),
  PrintStamp(PrintMotif.pumpkin, dx: 122, dy: 182, size: .9, color: pumpkin),
];
