import 'holiday_halloween_theme.dart';
import 'holiday_theme.dart';

/// 节日日历：告诉外观层"现在是哪个节日"，以及"下次什么时候会变"。
///
/// 现在是内置的一张表；以后改成服务器下发时，换一个实现就行，
/// 外观层和设置都不用动。
abstract interface class HolidayCalendar {
  List<HolidayTheme> get themes;

  /// [localNow] 这一天生效的节日；没有就返回 null。
  HolidayTheme? activeOn(DateTime localNow);

  /// [localNow] 之后、第一个"生效节日会变"的本地零点。
  ///
  /// 外观层用它来定下一次重新判断的时间，这样过了日期会自动改回，
  /// 到了日期也会自动换上，不用重启客户端。
  DateTime nextChangeAfter(DateTime localNow);
}

final class BuiltInHolidayCalendar implements HolidayCalendar {
  BuiltInHolidayCalendar([List<HolidayTheme>? themes])
    : themes = themes ?? [xmasHolidayTheme, halloweenHolidayTheme];

  @override
  final List<HolidayTheme> themes;

  @override
  HolidayTheme? activeOn(DateTime localNow) {
    for (final theme in themes) {
      if (theme.containsDate(localNow)) return theme;
    }
    return null;
  }

  @override
  DateTime nextChangeAfter(DateTime localNow) {
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    DateTime? earliest;
    void consider(DateTime boundary) {
      if (!boundary.isAfter(localNow)) return;
      if (earliest == null || boundary.isBefore(earliest!)) earliest = boundary;
    }

    for (final theme in themes) {
      for (final year in [today.year, today.year + 1]) {
        consider(theme.start.at(year));
        // 结束日的第二天零点才改回。
        consider(theme.end.at(year).add(const Duration(days: 1)));
      }
    }
    // 没有任何节日时，一天看一次也够了。
    return earliest ?? today.add(const Duration(days: 1));
  }
}
