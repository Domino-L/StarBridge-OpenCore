import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_layers.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/user_background.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

// 外观层的优先级：用户图片 ＞ 节日 ＞ 默认；通知色永远不动。
void main() {
  final dark = FutureRestraintStyle.resolve(AppearanceMode.dark);
  final light = FutureRestraintStyle.resolve(AppearanceMode.light);
  final holiday = AppearanceLayers(holiday: xmasHolidayTheme);

  test('平时：颜色不变，不印花，图标是默认的', () {
    const layers = AppearanceLayers.standard;
    expect(layers.holidayActive, isFalse);
    expect(layers.iconVariant, defaultIconVariant);
    expect(identical(layers.tokensFor(dark), dark), isTrue);
    for (final role in SurfaceRole.values) {
      expect(layers.printFor(role, AppearanceMode.dark), isNull);
    }
  });

  test('节日：只换主色和底色，状态色、文字色、面板色都不动', () {
    final tokens = holiday.tokensFor(dark);
    expect(tokens.colors.accent, isNot(dark.colors.accent));
    expect(
      tokens.surfaces.navigation.fill,
      isNot(dark.surfaces.navigation.fill),
    );
    expect(tokens.colors.danger, dark.colors.danger);
    expect(tokens.colors.success, dark.colors.success);
    expect(tokens.colors.warning, dark.colors.warning);
    expect(tokens.colors.textPrimary, dark.colors.textPrimary);
    expect(tokens.colors.textSecondary, dark.colors.textSecondary);
    expect(tokens.surfaces.panel.fill, dark.surfaces.panel.fill);
    expect(tokens.surfaces.raised.fill, dark.surfaces.raised.fill);
    expect(tokens.surfaces.floating.fill, dark.surfaces.floating.fill);
    expect(tokens.density, dark.density);
    expect(tokens.typography, dark.typography);
    expect(holiday.iconVariant, 'xmas');
    // 浅色模式也有一套。
    final lightTokens = holiday.tokensFor(light);
    expect(lightTokens.isDark, isFalse);
    expect(lightTokens.colors.accent, isNot(light.colors.accent));
  });

  test('节日：侧栏、顶栏、页面底色印花，面板和浮层不印', () {
    for (final mode in AppearanceMode.values) {
      expect(holiday.printFor(SurfaceRole.navigation, mode), isNotNull);
      expect(holiday.printFor(SurfaceRole.chrome, mode), isNotNull);
      expect(holiday.printFor(SurfaceRole.ground, mode), isNotNull);
      expect(holiday.printFor(SurfaceRole.panel, mode), isNull);
      expect(holiday.printFor(SurfaceRole.floating, mode), isNull);
      expect(holiday.printFor(SurfaceRole.raised, mode), isNull);
    }
  });

  test('关掉节日外观：节日期间也按平时', () {
    final off = AppearanceLayers(
      holiday: xmasHolidayTheme,
      holidayEnabled: false,
    );
    expect(off.holidayActive, isFalse);
    expect(off.iconVariant, defaultIconVariant);
    expect(identical(off.tokensFor(dark), dark), isTrue);
    expect(off.printFor(SurfaceRole.navigation, AppearanceMode.dark), isNull);
  });

  test('用户设了背景图：图上不印花，侧栏顶栏照印，图标和主色照换', () {
    const image = UserBackgroundImage(path: r'C:\pictures\sc.jpg');
    final layers = AppearanceLayers(
      holiday: xmasHolidayTheme,
      userBackground: image,
    );
    expect(layers.printFor(SurfaceRole.ground, AppearanceMode.dark), isNull);
    expect(
      layers.printFor(SurfaceRole.navigation, AppearanceMode.dark),
      isNotNull,
    );
    expect(layers.printFor(SurfaceRole.chrome, AppearanceMode.dark), isNotNull);
    expect(layers.iconVariant, 'xmas');
    expect(layers.tokensFor(dark).colors.accent, isNot(dark.colors.accent));
  });

  test('背景图至少压四成，保证字看得清', () {
    const bright = UserBackgroundImage(path: 'x.png', darken: .1);
    expect(bright.effectiveDarken, UserBackgroundImage.minimumDarken);
    const dim = UserBackgroundImage(path: 'x.png', darken: .7);
    expect(dim.effectiveDarken, .7);
  });

  test('减少动态效果不影响印花：印花本来就不动', () {
    final stilled = dark.withReducedMotion(true);
    expect(
      holiday.printFor(SurfaceRole.navigation, stilled.appearanceMode),
      same(holiday.printFor(SurfaceRole.navigation, dark.appearanceMode)),
    );
  });

  testWidgets('AppearanceSurfaceBackdrop：节日时画印花，平时什么都不画', (tester) async {
    Widget app(AppearanceLayers layers) => AppearanceScope(
      layers: layers,
      child: MaterialApp(
        theme: buildStarBridgeTheme(
          layers.tokensFor(dark),
          const Locale('zh', 'CN'),
        ),
        home: const Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              AppearanceSurfaceBackdrop(role: SurfaceRole.navigation),
              AppearanceSurfaceBackdrop(role: SurfaceRole.panel),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(holiday));
    expect(find.byKey(const Key('surface-print-navigation')), findsOneWidget);
    expect(find.byKey(const Key('surface-print-panel')), findsNothing);

    await tester.pumpWidget(app(AppearanceLayers.standard));
    expect(find.byKey(const Key('surface-print-navigation')), findsNothing);
  });

  testWidgets('没有作用域时按平时', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(dark, const Locale('zh', 'CN')),
        home: const AppearanceSurfaceBackdrop(role: SurfaceRole.ground),
      ),
    );
    expect(find.byKey(const Key('surface-print-ground')), findsNothing);
  });
}
