import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_halloween_theme.dart';
import 'package:starbridge_flutter/design_system/brand/brand_lockup.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/styles/holiday_halloween_palette.dart';
import 'package:starbridge_flutter/design_system/styles/holiday_xmas_palette.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

// 整个外壳：节日期间侧栏、顶栏、页面底色都有印花，主色换了，图标换了；
// 关掉开关或不在节日里，一切照旧。
Future<(InMemoryWindowChrome, InMemoryAppPreferences)> _pump(
  WidgetTester tester,
  DateTime now,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final chrome = InMemoryWindowChrome();
  final preferences = InMemoryAppPreferences();
  final composition = AppComposition.forTest(
    windowChrome: chrome,
    preferences: preferences,
  );
  await tester.pumpWidget(
    StarBridgeApp(
      composition: composition,
      holidayCalendar: BuiltInHolidayCalendar(),
      now: () => now,
    ),
  );
  await tester.pumpAndSettle();
  return (chrome, preferences);
}

FeatureDescriptor _hallFeature(WidgetTester tester) => tester
    .widget<StarBridgeApp>(find.byType(StarBridgeApp))
    .composition
    .features
    .all
    .singleWhere((feature) => feature.id == 'marketplace');

final _navigation = find.byKey(const Key('surface-print-navigation'));
final _chrome = find.byKey(const Key('surface-print-chrome'));
final _ground = find.byKey(const Key('surface-print-ground'));

void main() {
  testWidgets('圣诞期间：三处印花、主色暖金、图标换成 xmas', (tester) async {
    final (chrome, preferences) = await _pump(tester, DateTime(2026, 12, 25));
    expect(_navigation, findsOneWidget);
    expect(_chrome, findsOneWidget);
    expect(_ground, findsOneWidget);
    expect(chrome.commands, contains('setIconVariant:xmas'));
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.colorScheme.primary, HolidayXmasPalette.accentDark);

    // 关掉开关：立刻改回。
    await preferences.setHolidayAppearance(false);
    await tester.pumpAndSettle();
    expect(_navigation, findsNothing);
    expect(_chrome, findsNothing);
    expect(_ground, findsNothing);
    expect(chrome.commands.last, 'setIconVariant:default');
    final plain = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(plain.colorScheme.primary, isNot(HolidayXmasPalette.accentDark));

    // 定时器跟着应用一起销毁。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('万圣节期间：左上角星标换了，交易页留在平时的主色', (tester) async {
    final (_, preferences) = await _pump(tester, DateTime(2026, 10, 31));
    String mark() => (tester
            .widget<Image>(
              find
                  .descendant(
                    of: find.byType(BrandLockup),
                    matching: find.byType(Image),
                  )
                  .first,
            )
            .image as AssetImage)
        .assetName;
    expect(mark(), halloweenHolidayTheme.mark.smallDarkSurface);
    final context = tester.element(find.byType(Scaffold).first);
    expect(context.tokens.colors.accent, HolidayHalloweenPalette.accentDark);
    final hall = _hallFeature(tester);
    final page = hall.buildDestination(context);
    expect(page, isA<HolidayColorExempt>());
    final exempt = HolidayExemptThemeScope.maybeOf(context)!;
    expect(
      exempt.extension<StarBridgeTokens>()!.colors.accent,
      FutureRestraintStyle.resolve(AppearanceMode.dark).colors.accent,
    );

    // 关掉开关：星标改回，也不再需要"平时的主题"。
    await preferences.setHolidayAppearance(false);
    await tester.pumpAndSettle();
    expect(mark(), 'assets/brand/starbridge_mark_dark_surface.png');
    expect(
      HolidayExemptThemeScope.maybeOf(
        tester.element(find.byType(Scaffold).first),
      ),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('不在节日里：没有印花，图标是默认', (tester) async {
    // 11-02：万圣节（10-24 到 11-01）刚过，圣诞（12-18 起）还没到。
    final (chrome, _) = await _pump(tester, DateTime(2026, 11, 2));
    expect(_navigation, findsNothing);
    expect(_chrome, findsNothing);
    expect(_ground, findsNothing);
    expect(chrome.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
