import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_holiday.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_native_popup.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_app_frame.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';

Future<List<String>> _dockAssets(WidgetTester tester, String? holiday) async {
  await tester.pumpWidget(
    MenuSurfaceAppFrame(
      observer: MenuNativePopupObserver(),
      interaction: MenuInteractionPresentation(
        language: 'zh-CN',
        holiday: holiday,
      ),
      child: Scaffold(
        body: BridgePreviewDock(selected: null, onToggle: (_) {}),
      ),
    ),
  );
  await tester.pump();
  return [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image case final AssetImage asset) asset.assetName,
  ];
}

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(BridgePreviewDock)));

void main() {
  testWidgets('菜单浮层的星标跟节日走，字标和配色不动', (tester) async {
    final standard = await _dockAssets(tester, null);
    expect(standard, contains('assets/brand/starbridge_mark_dark_surface.png'));
    final primary = _theme(tester).colorScheme.primary;
    final wordmark = standard.singleWhere((name) => name.contains('wordmark'));

    for (final (id, part) in const [
      ('halloween', 'holiday/halloween_mark'),
      ('xmas', 'holiday/xmas_mark'),
    ]) {
      final assets = await _dockAssets(tester, id);
      expect(assets.where((name) => name.contains(part)), hasLength(1), reason: id);
      expect(assets, isNot(contains('assets/brand/starbridge_mark_dark_surface.png')));
      expect(assets, contains(wordmark));
      expect(_theme(tester).colorScheme.primary, primary, reason: id);
    }

    expect(
      await _dockAssets(tester, 'not-a-holiday'),
      contains('assets/brand/starbridge_mark_dark_surface.png'),
    );
  });

  testWidgets('星标和字标缩小时不用只适合放大的采样', (tester) async {
    await _dockAssets(tester, 'halloween');
    final images = tester.widgetList<Image>(find.byType(Image)).where(
      (image) =>
          image.image is AssetImage &&
          (image.image as AssetImage).assetName.startsWith('assets/brand/'),
    );
    expect(images, hasLength(2));
    for (final image in images) {
      expect(image.filterQuality, FilterQuality.medium);
    }
  });

  test('节日只在日期内且开关开着时传给浮层', () {
    final calendar = BuiltInHolidayCalendar();
    final halloween = DateTime(2026, 11, 1, 23);
    expect(menuHolidayId(enabled: true, now: halloween, calendar: calendar), 'halloween');
    expect(menuHolidayId(enabled: false, now: halloween, calendar: calendar), isNull);
    expect(
      menuHolidayId(enabled: true, now: DateTime(2026, 11, 2), calendar: calendar),
      isNull,
    );
    expect(
      menuHolidayId(enabled: true, now: DateTime(2026, 12, 18), calendar: calendar),
      'xmas',
    );
  });

  test('每个节日都能放进显示设置，放不进的内容不收', () {
    for (final HolidayTheme theme in BuiltInHolidayCalendar().themes) {
      final original = MenuInteractionPresentation(
        language: 'zh-CN',
        holiday: theme.id,
      );
      final payload = original.encode();
      expect(utf8.encode(payload).length, lessThanOrEqualTo(MenuInteractionPresentation.maxPayloadLength));
      expect(MenuInteractionPresentation.parse(payload)!.holiday, theme.id);
    }
    expect(MenuInteractionPresentation.parse(const MenuInteractionPresentation().encode())!.holiday, isNull);
    for (final bad in <Object>[1, '', 'A B', 'x' * 33]) {
      expect(
        MenuInteractionPresentation.parse(
          jsonEncode({
            'schemaVersion': 1,
            'style': 'rail',
            'reduceMotion': false,
            'holiday': bad,
          }),
        ),
        isNull,
        reason: '$bad',
      );
    }
  });
}
