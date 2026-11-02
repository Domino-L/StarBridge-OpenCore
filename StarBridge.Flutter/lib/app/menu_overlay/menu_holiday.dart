import '../../design_system/appearance/appearance_layers.dart';
import '../../design_system/appearance/holiday_calendar.dart';

/// 主引擎算出现在的节日，随显示设置传给菜单浮层。
String? menuHolidayId({
  required bool enabled,
  required DateTime now,
  HolidayCalendar? calendar,
}) => enabled ? (calendar ?? BuiltInHolidayCalendar()).activeOn(now)?.id : null;

/// 浮层引擎的外观层。浮层的主题不读这一层，所以这里只换星标，配色和平时一样。
AppearanceLayers menuAppearanceLayers(String? holidayId) {
  for (final theme in BuiltInHolidayCalendar().themes) {
    if (theme.id == holidayId) return AppearanceLayers(holiday: theme);
  }
  return AppearanceLayers.standard;
}
