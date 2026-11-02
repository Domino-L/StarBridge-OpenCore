import 'package:flutter/foundation.dart';

import '../tokens/color_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import 'holiday_theme.dart';
import 'surface_print.dart';
import 'user_background.dart';

/// 平时的图标。
const defaultIconVariant = 'default';

/// 外观层：背景层、图标层、印花层各管各的，这里把它们合成一份结果。
///
/// 优先级：用户自己的图片背景 ＞ 节日 ＞ 默认。
/// - 用户设了背景图：图上不印花，节日只换侧栏/顶栏的印花、图标和主色。
/// - 用户关掉了节日外观：节日完全不生效，就算在节日期间也一样。
@immutable
final class AppearanceLayers {
  const AppearanceLayers({
    this.holiday,
    this.holidayEnabled = true,
    this.previewing = false,
    this.userBackground,
  });

  /// 日历说现在生效的节日；null 表示不在任何节日里。
  final HolidayTheme? holiday;

  /// 设置里的"节日外观"开关。
  final bool holidayEnabled;

  /// 调试预览（STARBRIDGE_HOLIDAY_PREVIEW）：不看日期也不看开关，只在本次运行有效。
  final bool previewing;

  final UserBackgroundImage? userBackground;

  static const standard = AppearanceLayers();

  bool get holidayActive => holiday != null && (holidayEnabled || previewing);

  String get iconVariant =>
      holidayActive ? holiday!.iconVariant : defaultIconVariant;

  /// 节日版的左上角星标；不在节日里就是 null，用平时的星标。
  HolidayMarkArt? get mark => holidayActive ? holiday!.mark : null;

  /// 节日生效时换颜色；否则原样返回。
  StarBridgeTokens tokensFor(StarBridgeTokens base) =>
      holidayActive ? holiday!.applyTo(base) : base;

  /// [role] 这个面上要印的印花；不印就返回 null。
  SurfacePrintSpec? printFor(SurfaceRole role, AppearanceMode mode) {
    if (!holidayActive) return null;
    // 用户的图片上不印图案。
    if (userBackground != null && role == SurfaceRole.ground) return null;
    final spec = holiday!.printFor(mode);
    return spec.opacityFor(role) == null ? null : spec;
  }

  AppearanceLayers copyWith({
    HolidayTheme? holiday,
    bool clearHoliday = false,
    bool? holidayEnabled,
    bool? previewing,
    UserBackgroundImage? userBackground,
    bool clearUserBackground = false,
  }) => AppearanceLayers(
    holiday: clearHoliday ? null : (holiday ?? this.holiday),
    holidayEnabled: holidayEnabled ?? this.holidayEnabled,
    previewing: previewing ?? this.previewing,
    userBackground: clearUserBackground
        ? null
        : (userBackground ?? this.userBackground),
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceLayers &&
      other.holiday == holiday &&
      other.holidayEnabled == holidayEnabled &&
      other.previewing == previewing &&
      other.userBackground == userBackground;

  @override
  int get hashCode =>
      Object.hash(holiday, holidayEnabled, previewing, userBackground);
}
