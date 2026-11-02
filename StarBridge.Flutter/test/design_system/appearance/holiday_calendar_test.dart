import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';

// 圣诞按本地日期 12-18 到 01-02 生效，两端都算；跨年。
void main() {
  final calendar = BuiltInHolidayCalendar();

  test('12-17 还不是圣诞，12-18 零点开始，01-02 整天都算', () {
    expect(calendar.activeOn(DateTime(2026, 12, 17, 23, 59)), isNull);
    expect(calendar.activeOn(DateTime(2026, 12, 18)), xmasHolidayTheme);
    expect(calendar.activeOn(DateTime(2026, 12, 25, 12)), xmasHolidayTheme);
    expect(calendar.activeOn(DateTime(2026, 12, 31, 23, 59)), xmasHolidayTheme);
    expect(calendar.activeOn(DateTime(2027, 1, 1)), xmasHolidayTheme);
    expect(calendar.activeOn(DateTime(2027, 1, 2, 23, 59)), xmasHolidayTheme);
    expect(calendar.activeOn(DateTime(2027, 1, 3)), isNull);
    expect(calendar.activeOn(DateTime(2027, 7, 1)), isNull);
  });

  test('下一次变化：节前指向开始日零点，节中指向结束日次日零点', () {
    expect(
      calendar.nextChangeAfter(DateTime(2026, 11, 3, 10)),
      DateTime(2026, 12, 18),
    );
    expect(
      calendar.nextChangeAfter(DateTime(2026, 12, 18, 0, 0, 1)),
      DateTime(2027, 1, 3),
    );
    expect(
      calendar.nextChangeAfter(DateTime(2027, 1, 2, 22)),
      DateTime(2027, 1, 3),
    );
    // 刚过完节，下一次变化是今年的万圣节（10-24）。
    expect(
      calendar.nextChangeAfter(DateTime(2027, 1, 3, 0, 0, 1)),
      DateTime(2027, 10, 24),
    );
  });

  test('没有任何节日时，一天看一次', () {
    final empty = BuiltInHolidayCalendar(const []);
    expect(empty.activeOn(DateTime(2026, 12, 25)), isNull);
    expect(
      empty.nextChangeAfter(DateTime(2026, 12, 25, 8)),
      DateTime(2026, 12, 26),
    );
  });

  test('不跨年的节日照常判断', () {
    const spring = HolidayDate(2, 10);
    final theme = HolidayTheme(
      id: 'test',
      start: spring,
      end: const HolidayDate(2, 20),
      iconVariant: 'test',
      blessingKey: 'home.holiday.xmas',
      mark: xmasHolidayTheme.mark,
      dark: xmasHolidayTheme.dark,
      light: xmasHolidayTheme.light,
      printDark: xmasHolidayTheme.printDark,
      printLight: xmasHolidayTheme.printLight,
    );
    expect(theme.crossesYearEnd, isFalse);
    expect(theme.containsDate(DateTime(2027, 2, 9)), isFalse);
    expect(theme.containsDate(DateTime(2027, 2, 10)), isTrue);
    expect(theme.containsDate(DateTime(2027, 2, 20)), isTrue);
    expect(theme.containsDate(DateTime(2027, 2, 21)), isFalse);
    expect(theme.containsDate(DateTime(2027, 12, 25)), isFalse);
  });
}
