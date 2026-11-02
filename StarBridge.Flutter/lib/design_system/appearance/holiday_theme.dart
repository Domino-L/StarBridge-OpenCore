import 'package:flutter/material.dart';

import '../styles/holiday_xmas_palette.dart';
import '../tokens/color_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import 'surface_print.dart';

/// 一年里的某一天（本地日期），不带年份。
@immutable
final class HolidayDate implements Comparable<HolidayDate> {
  const HolidayDate(this.month, this.day)
    : assert(month >= 1 && month <= 12),
      assert(day >= 1 && day <= 31);

  final int month;
  final int day;

  int get _ordinal => month * 100 + day;

  @override
  int compareTo(HolidayDate other) => _ordinal.compareTo(other._ordinal);

  bool operator <=(HolidayDate other) => _ordinal <= other._ordinal;
  bool operator >=(HolidayDate other) => _ordinal >= other._ordinal;

  /// 这个日期在 [year] 年的零点。
  DateTime at(int year) => DateTime(year, month, day);

  @override
  bool operator ==(Object other) =>
      other is HolidayDate && other.month == month && other.day == day;

  @override
  int get hashCode => _ordinal;

  @override
  String toString() => '$month-$day';
}

/// 一个节日主题换哪些颜色。没列的颜色一律不动，通知小标和状态色尤其不动。
@immutable
final class HolidayPalette {
  const HolidayPalette({
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.focusRing,
    required this.navigation,
    required this.chrome,
    required this.ground,
    required this.line,
    required this.selected,
  });

  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color focusRing;
  final Color navigation;
  final Color chrome;
  final Color ground;
  final Color line;
  final Color selected;
}

/// 左上角星标的节日版。图片和平时的星标画布一样，换上去位置和大小都不变。
@immutable
final class HolidayMarkArt {
  const HolidayMarkArt({
    required this.darkSurface,
    required this.lightSurface,
    this.smallDarkSurface,
    this.smallLightSurface,
  });

  /// 实际像素小于它时用小图：小图去掉了这么小看不清的细节。
  static const smallBelowPhysicalSize = 48.0;

  final String darkSurface;
  final String lightSurface;
  final String? smallDarkSurface;
  final String? smallLightSurface;

  String resolve({
    required Brightness surfaceBrightness,
    required double physicalSize,
  }) {
    final dark = surfaceBrightness == Brightness.dark;
    final small = physicalSize < smallBelowPhysicalSize
        ? (dark ? smallDarkSurface : smallLightSurface)
        : null;
    return small ?? (dark ? darkSurface : lightSurface);
  }
}

/// 一个节日主题：什么时候生效、换什么颜色、印什么图案、换哪套图标。
///
/// 日历给出"现在是不是这个节日"，这里只描述外观本身。
@immutable
final class HolidayTheme {
  const HolidayTheme({
    required this.id,
    required this.start,
    required this.end,
    required this.iconVariant,
    required this.blessingKey,
    required this.mark,
    required this.dark,
    required this.light,
    required this.printDark,
    required this.printLight,
  });

  /// 稳定的标识，用于设置、日志和以后服务器下发时对上号。
  final String id;

  /// 生效区间，两端都算在内，按本地日期。可以跨年（例如 12-18 到 01-02）。
  final HolidayDate start;
  final HolidayDate end;

  /// 运行时换给窗口、任务栏、托盘的图标名；`default` 表示平时的图标。
  final String iconVariant;

  /// 首页问候语末尾的祝福。
  final String blessingKey;

  /// 客户端左上角的星标。
  final HolidayMarkArt mark;

  final HolidayPalette dark;
  final HolidayPalette light;
  final SurfacePrintSpec printDark;
  final SurfacePrintSpec printLight;

  bool get crossesYearEnd => end.compareTo(start) < 0;

  /// [local] 这一天是否在生效区间里。
  bool containsDate(DateTime local) {
    final date = HolidayDate(local.month, local.day);
    if (!crossesYearEnd) return start <= date && date <= end;
    return date >= start || date <= end;
  }

  SurfacePrintSpec printFor(AppearanceMode mode) =>
      mode == AppearanceMode.dark ? printDark : printLight;

  HolidayPalette paletteFor(AppearanceMode mode) =>
      mode == AppearanceMode.dark ? dark : light;

  /// 把节日颜色套到一套设计令牌上。只换 [HolidayPalette] 里列出的颜色。
  StarBridgeTokens applyTo(StarBridgeTokens base) {
    final p = paletteFor(base.appearanceMode);
    final colors = base.colors;
    final surfaces = base.surfaces;
    return base.copyWith(
      colors: ColorTokens(
        textPrimary: colors.textPrimary,
        textSecondary: colors.textSecondary,
        textDisabled: colors.textDisabled,
        accent: p.accent,
        accentSoft: p.accentSoft,
        stateAccent: colors.stateAccent,
        stateAccentSoft: colors.stateAccentSoft,
        onAccent: p.onAccent,
        focusRing: p.focusRing,
        success: colors.success,
        successSoft: colors.successSoft,
        warning: colors.warning,
        warningSoft: colors.warningSoft,
        danger: colors.danger,
        dangerSoft: colors.dangerSoft,
        info: colors.info,
        infoSoft: colors.infoSoft,
        offline: colors.offline,
        scrim: colors.scrim,
      ),
      surfaces: SurfaceTokens(
        windowFrame: surfaces.windowFrame,
        ground: SurfaceLevelTokens(
          fill: p.ground,
          border: p.line,
          shadows: surfaces.ground.shadows,
        ),
        navigation: SurfaceLevelTokens(
          fill: p.navigation,
          border: p.line,
          shadows: surfaces.navigation.shadows,
        ),
        chrome: SurfaceLevelTokens(
          fill: p.chrome,
          border: p.line,
          shadows: surfaces.chrome.shadows,
        ),
        status: surfaces.status,
        panel: surfaces.panel,
        raised: surfaces.raised,
        floating: surfaces.floating,
        selected: SurfaceLevelTokens(
          fill: p.selected,
          border: p.accent,
          shadows: surfaces.selected.shadows,
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) => other is HolidayTheme && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 圣诞（H3 定稿）。生效 12-18 到 01-02。
final HolidayTheme xmasHolidayTheme = HolidayTheme(
  id: 'xmas',
  start: HolidayDate(12, 18),
  end: HolidayDate(1, 2),
  iconVariant: 'xmas',
  blessingKey: 'home.holiday.xmas',
  mark: const HolidayMarkArt(
    darkSurface: 'assets/brand/holiday/xmas_mark_dark_surface.png',
    lightSurface: 'assets/brand/holiday/xmas_mark_light_surface.png',
  ),
  dark: HolidayPalette(
    accent: HolidayXmasPalette.accentDark,
    accentSoft: HolidayXmasPalette.accentSoftDark,
    onAccent: HolidayXmasPalette.onAccentDark,
    focusRing: HolidayXmasPalette.focusRingDark,
    navigation: HolidayXmasPalette.navigationDark,
    chrome: HolidayXmasPalette.chromeDark,
    ground: HolidayXmasPalette.groundDark,
    line: HolidayXmasPalette.lineDark,
    selected: HolidayXmasPalette.selectedDark,
  ),
  light: HolidayPalette(
    accent: HolidayXmasPalette.accentLight,
    accentSoft: HolidayXmasPalette.accentSoftLight,
    onAccent: HolidayXmasPalette.onAccentLight,
    focusRing: HolidayXmasPalette.focusRingLight,
    navigation: HolidayXmasPalette.navigationLight,
    chrome: HolidayXmasPalette.chromeLight,
    ground: HolidayXmasPalette.groundLight,
    line: HolidayXmasPalette.lineLight,
    selected: HolidayXmasPalette.selectedLight,
  ),
  printDark: _xmasPrintDark,
  printLight: _xmasPrintLight,
);

// 一块 240×210 的印花：雪花和礼物是雪银，铃铛和星是金，彩球和浆果是红，冬青叶是绿。
// 红的旁边只有绿，没有金。
const _xmasOpacityDark = {
  SurfaceRole.navigation: .16,
  SurfaceRole.chrome: .09,
  SurfaceRole.ground: .11,
};
const _xmasOpacityLight = {
  SurfaceRole.navigation: .12,
  SurfaceRole.chrome: .07,
  SurfaceRole.ground: .08,
};

final _xmasPrintDark = SurfacePrintSpec(
  tileWidth: 240,
  tileHeight: 210,
  opacity: _xmasOpacityDark,
  stamps: _xmasStamps(
    silver: HolidayXmasPalette.printSilverDark,
    gold: HolidayXmasPalette.printGoldDark,
    green: HolidayXmasPalette.printGreenDark,
  ),
);

final _xmasPrintLight = SurfacePrintSpec(
  tileWidth: 240,
  tileHeight: 210,
  opacity: _xmasOpacityLight,
  stamps: _xmasStamps(
    silver: HolidayXmasPalette.printSilverLight,
    gold: HolidayXmasPalette.printGoldLight,
    green: HolidayXmasPalette.printGreenLight,
  ),
);

// 顺序就是绘制顺序。位置和预览 xmas-print.html#H3 里的一致。
List<PrintStamp> _xmasStamps({
  required Color silver,
  required Color gold,
  required Color green,
}) => [
  PrintStamp(PrintMotif.snowflake, dx: 34, dy: 36, size: 14, color: silver),
  PrintStamp(PrintMotif.snowflake, dx: 170, dy: 150, size: 9, color: silver),
  PrintStamp(PrintMotif.snowflake, dx: 110, dy: 100, size: 6, color: silver),
  PrintStamp(PrintMotif.dot, dx: 120, dy: 20, size: 1.3, color: silver),
  PrintStamp(PrintMotif.dot, dx: 60, dy: 190, size: 1.2, color: silver),
  PrintStamp(PrintMotif.dot, dx: 220, dy: 60, size: 1.4, color: silver),
  PrintStamp(PrintMotif.gift, dx: 140, dy: 200, size: .8, color: silver),
  PrintStamp(PrintMotif.bell, dx: 200, dy: 40, size: .9, color: gold),
  PrintStamp(PrintMotif.star, dx: 150, dy: 70, size: 6, color: gold),
  PrintStamp(PrintMotif.star, dx: 20, dy: 110, size: 4.5, color: gold),
  PrintStamp(PrintMotif.star, dx: 225, dy: 190, size: 7, color: gold),
  PrintStamp(
    PrintMotif.bauble,
    dx: 70,
    dy: 130,
    size: 8,
    color: HolidayXmasPalette.printRed,
  ),
  PrintStamp(PrintMotif.holly, dx: 90, dy: 150, size: .95, color: green),
];
