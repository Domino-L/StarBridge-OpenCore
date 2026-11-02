import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_halloween_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

// 万圣节按本地日期 10-24 到 11-01 生效，两端都算；和圣诞不重叠。
void main() {
  final calendar = BuiltInHolidayCalendar();
  final theme = halloweenHolidayTheme;

  test('10-23 还不是，10-24 零点开始，11-01 整天都算，11-02 改回', () {
    expect(calendar.activeOn(DateTime(2026, 10, 23, 23, 59)), isNull);
    expect(calendar.activeOn(DateTime(2026, 10, 24)), theme);
    expect(calendar.activeOn(DateTime(2026, 10, 31, 20)), theme);
    expect(calendar.activeOn(DateTime(2026, 11, 1, 23, 59)), theme);
    expect(calendar.activeOn(DateTime(2026, 11, 2)), isNull);
  });

  test('下一次变化：节前指向 10-24，节中指向 11-02，节后指向圣诞', () {
    expect(
      calendar.nextChangeAfter(DateTime(2026, 10, 1, 9)),
      DateTime(2026, 10, 24),
    );
    expect(
      calendar.nextChangeAfter(DateTime(2026, 10, 24, 0, 0, 1)),
      DateTime(2026, 11, 2),
    );
    expect(
      calendar.nextChangeAfter(DateTime(2026, 11, 2, 0, 0, 1)),
      DateTime(2026, 12, 18),
    );
  });

  test('和圣诞的日期不重叠', () {
    for (
      var day = DateTime(2026, 1, 1);
      day.year == 2026;
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      expect(
        theme.containsDate(day) && xmasHolidayTheme.containsDate(day),
        isFalse,
        reason: '$day',
      );
    }
  });

  test('图标是万圣节版', () {
    expect(theme.iconVariant, 'halloween');
  });

  test('只换主色和底色；状态色、文字色、面板色不动', () {
    for (final mode in AppearanceMode.values) {
      final base = FutureRestraintStyle.resolve(mode);
      final applied = theme.applyTo(base);
      expect(applied.colors.accent, theme.paletteFor(mode).accent);
      expect(applied.colors.accent, isNot(base.colors.accent));
      expect(applied.colors.danger, base.colors.danger);
      expect(applied.colors.success, base.colors.success);
      expect(applied.colors.textPrimary, base.colors.textPrimary);
      expect(applied.surfaces.panel, base.surfaces.panel);
      expect(applied.surfaces.status, base.surfaces.status);
    }
  });

  test('印花不是单色、不用红，月银最多', () {
    for (final mode in AppearanceMode.values) {
      final stamps = theme.printFor(mode).stamps;
      final counts = <Color, int>{};
      for (final stamp in stamps) {
        counts[stamp.color] = (counts[stamp.color] ?? 0) + 1;
      }
      expect(counts.length, greaterThanOrEqualTo(2));
      final silver = counts[stamps.first.color]!;
      for (final entry in counts.entries) {
        expect(silver, greaterThanOrEqualTo(entry.value));
      }
      for (final color in counts.keys) {
        final hsv = HSVColor.fromColor(color);
        final reddish = hsv.hue < 15 || hsv.hue > 340;
        expect(reddish && hsv.saturation > .4, isFalse, reason: '$color 太红');
      }
    }
  });

  test('印花只印侧栏、顶栏、页面底色', () {
    final spec = theme.printFor(AppearanceMode.dark);
    expect(spec.opacity.keys.toSet(), {
      SurfaceRole.navigation,
      SurfaceRole.chrome,
      SurfaceRole.ground,
    });
  });
}
