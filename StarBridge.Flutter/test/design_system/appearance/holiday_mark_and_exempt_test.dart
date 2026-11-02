import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/shell/chrome/presence_color.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_layers.dart';
import 'package:starbridge_flutter/design_system/appearance/appearance_scope.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_calendar.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_halloween_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/user_background.dart';
import 'package:starbridge_flutter/design_system/brand/brand_lockup.dart';
import 'package:starbridge_flutter/design_system/brand/brand_lockup_spec.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/styles/holiday_halloween_palette.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';

const _defaultDark = 'assets/brand/starbridge_mark_dark_surface.png';
const _defaultLight = 'assets/brand/starbridge_mark_light_surface.png';

StarBridgeTokens _tokens(AppearanceMode mode) =>
    FutureRestraintStyle.resolve(mode);

Future<void> _pumpLockup(
  WidgetTester tester, {
  required AppearanceLayers layers,
  AppearanceMode mode = AppearanceMode.dark,
  double ratio = 1,
}) async {
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppearanceScope(
      layers: layers,
      child: MaterialApp(
        theme: buildStarBridgeTheme(_tokens(mode), const Locale('zh', 'CN')),
        home: const Scaffold(
          body: BrandLockup(scale: BrandLockupScale.navigationExpanded),
        ),
      ),
    ),
  );
  // 主题切换带过渡动画，等它走完。
  await tester.pumpAndSettle();
}

String _markAsset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image).first);
  return (image.image as AssetImage).assetName;
}

List<String> _assetNames(WidgetTester tester) => [
  for (final image in tester.widgetList<Image>(find.byType(Image)))
    (image.image as AssetImage).assetName,
];

Future<(int, int, int, int, int)> _opaqueBounds(String path) async {
  final codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
  );
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  final bytes = Uint8List.sublistView(data);
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (bytes[(y * image.width + x) * 4 + 3] <= 32) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return (image.width, left, top, right, bottom);
}

void main() {
  final halloween = AppearanceLayers(holiday: halloweenHolidayTheme);
  final xmas = AppearanceLayers(holiday: xmasHolidayTheme);

  group('左上角星标', () {
    testWidgets('不在节日里，或者没有外观层：平时的星标', (tester) async {
      await _pumpLockup(tester, layers: AppearanceLayers.standard);
      expect(_markAsset(tester), _defaultDark);
      await _pumpLockup(
        tester,
        layers: AppearanceLayers.standard,
        mode: AppearanceMode.light,
      );
      expect(_markAsset(tester), _defaultLight);
    });

    testWidgets('万圣节：普通缩放用去掉绿色的小图，高缩放用完整的脸', (tester) async {
      await _pumpLockup(tester, layers: halloween);
      expect(_markAsset(tester), halloweenHolidayTheme.mark.smallDarkSurface);
      // 34 × 1.5 = 51 实际像素，够看清绿色了。
      await _pumpLockup(tester, layers: halloween, ratio: 1.5);
      expect(_markAsset(tester), halloweenHolidayTheme.mark.darkSurface);
      await _pumpLockup(
        tester,
        layers: halloween,
        mode: AppearanceMode.light,
        ratio: 2,
      );
      expect(_markAsset(tester), halloweenHolidayTheme.mark.lightSurface);
    });

    testWidgets('圣诞：深浅两种底各一张', (tester) async {
      await _pumpLockup(tester, layers: xmas);
      expect(_markAsset(tester), xmasHolidayTheme.mark.darkSurface);
      await _pumpLockup(tester, layers: xmas, mode: AppearanceMode.light);
      expect(_markAsset(tester), xmasHolidayTheme.mark.lightSurface);
    });

    testWidgets('字标不动，大小不变', (tester) async {
      await _pumpLockup(tester, layers: AppearanceLayers.standard);
      final plainNames = _assetNames(tester);
      final plain = tester.getSize(find.byType(Image).first);
      await _pumpLockup(tester, layers: halloween);
      expect(_assetNames(tester).last, plainNames.last);
      expect(tester.getSize(find.byType(Image).first), plain);
    });

    testWidgets('关掉节日外观：改回平时的星标；预览时不看开关', (tester) async {
      final off = AppearanceLayers(
        holiday: halloweenHolidayTheme,
        holidayEnabled: false,
      );
      await _pumpLockup(tester, layers: off);
      expect(_markAsset(tester), _defaultDark);
      await _pumpLockup(tester, layers: off.copyWith(previewing: true));
      expect(_markAsset(tester), halloweenHolidayTheme.mark.smallDarkSurface);
    });

    test('每个节日的星标都和平时的星标占同样的位置', () async {
      Future<void> check(String asset, String standard) async {
        final (w, l, t, r, b) = await _opaqueBounds(asset);
        final (sw, sl, st, sr, sb) = await _opaqueBounds(standard);
        final k = w / sw;
        // 容差 1% 画布、至少 3 像素：缩小时细尖端的半透明边缘会差一两个像素。
        final tolerance = math.max(w * .01, 3);
        expect((l - sl * k).abs(), lessThanOrEqualTo(tolerance), reason: asset);
        expect((t - st * k).abs(), lessThanOrEqualTo(tolerance), reason: asset);
        expect((r - sr * k).abs(), lessThanOrEqualTo(tolerance), reason: asset);
        expect((b - sb * k).abs(), lessThanOrEqualTo(tolerance), reason: asset);
      }

      for (final theme in BuiltInHolidayCalendar().themes) {
        final mark = theme.mark;
        await check(mark.darkSurface, _defaultDark);
        await check(mark.lightSurface, _defaultLight);
        if (mark.smallDarkSurface case final small?) {
          await check(small, _defaultDark);
        }
        if (mark.smallLightSurface case final small?) {
          await check(small, _defaultLight);
        }
      }
    });
  });

  group('状态色不跟节日走', () {
    for (final mode in AppearanceMode.values) {
      for (final theme in BuiltInHolidayCalendar().themes) {
        test('${theme.id} ${mode.name}：只换主色，状态色和平时一样', () {
          final base = _tokens(mode).colors;
          final holiday = theme.applyTo(_tokens(mode)).colors;
          expect(holiday.accent, isNot(base.accent));
          // 平时状态主色就是主色，所以平时的外观一点没变。
          expect(base.stateAccent, base.accent);
          expect(base.stateAccentSoft, base.accentSoft);
          expect(holiday.stateAccent, base.stateAccent);
          expect(holiday.stateAccentSoft, base.stateAccentSoft);
          expect(holiday.success, base.success);
          expect(holiday.warning, base.warning);
          expect(holiday.danger, base.danger);
          expect(holiday.info, base.info);
          expect(holiday.offline, base.offline);
          for (final key in const [
            'presence.online',
            'presence.inGame',
            'presence.away',
            'presence.manualOffline',
            'presence.offline',
          ]) {
            expect(presenceColor(holiday, key), presenceColor(base, key));
          }
        });
      }
    }

    test('过渡动画里状态色也不跳', () {
      final base = _tokens(AppearanceMode.dark).colors;
      final holiday = halloweenHolidayTheme
          .applyTo(_tokens(AppearanceMode.dark))
          .colors;
      expect(base.lerp(holiday, .5).stateAccent, base.stateAccent);
    });
  });

  group('交易页不跟节日配色', () {
    final standardTheme = buildStarBridgeTheme(
      _tokens(AppearanceMode.dark),
      const Locale('zh', 'CN'),
    );
    final holidayTheme = buildStarBridgeTheme(
      halloweenHolidayTheme.applyTo(_tokens(AppearanceMode.dark)),
      const Locale('zh', 'CN'),
    );

    Widget app({required ThemeData? exempt, required Widget child}) =>
        MaterialApp(
          theme: holidayTheme,
          builder: (context, navigator) =>
              HolidayExemptThemeScope(data: exempt, child: navigator!),
          home: Scaffold(body: child),
        );

    testWidgets('节日期间：里面是平时的主色，外面还是节日主色', (tester) async {
      const inner = Key('inner');
      const outer = Key('outer');
      await tester.pumpWidget(
        app(
          exempt: standardTheme,
          child: const Column(
            children: [
              SizedBox(key: outer),
              HolidayColorExempt(child: SizedBox(key: inner)),
            ],
          ),
        ),
      );
      final standardAccent = _tokens(AppearanceMode.dark).colors.accent;
      expect(standardAccent, isNot(HolidayHalloweenPalette.accentDark));
      expect(tester.element(find.byKey(inner)).tokens.colors.accent, standardAccent);
      expect(
        Theme.of(tester.element(find.byKey(inner))).colorScheme.primary,
        standardTheme.colorScheme.primary,
      );
      expect(
        tester.element(find.byKey(outer)).tokens.colors.accent,
        HolidayHalloweenPalette.accentDark,
      );
    });

    testWidgets('不在节日里：什么都不改', (tester) async {
      const inner = Key('inner');
      await tester.pumpWidget(
        app(
          exempt: null,
          child: const HolidayColorExempt(child: SizedBox(key: inner)),
        ),
      );
      expect(
        Theme.of(tester.element(find.byKey(inner))).colorScheme.primary,
        holidayTheme.colorScheme.primary,
      );
    });

    testWidgets('里面弹出的对话框也是平时的主色', (tester) async {
      late BuildContext opener;
      await tester.pumpWidget(
        app(
          exempt: standardTheme,
          child: HolidayColorExempt(
            child: Builder(
              builder: (context) {
                opener = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      const inDialog = Key('in-dialog');
      showDialog<void>(
        context: opener,
        builder: (_) => const SizedBox(key: inDialog),
      );
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(inDialog)).tokens.colors.accent,
        _tokens(AppearanceMode.dark).colors.accent,
      );
    });

    testWidgets('整页还原：节日期间铺平时的底色，平时和用户背景图都不盖', (tester) async {
      Widget page(ThemeData? exempt, {AppearanceLayers? layers}) =>
          AppearanceScope(
            layers: layers ?? AppearanceLayers.standard,
            child: app(
              exempt: exempt,
              child: const HolidayColorExempt(
                key: Key('hall-exempt'),
                restoreGround: true,
                child: SizedBox(),
              ),
            ),
          );
      Color? painted() => tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byKey(const Key('hall-exempt')),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;
      await tester.pumpWidget(page(standardTheme));
      expect(painted(), _tokens(AppearanceMode.dark).surfaces.ground.fill);
      await tester.pumpWidget(page(null));
      expect(painted(), Colors.transparent);
      await tester.pumpWidget(
        page(
          standardTheme,
          layers: AppearanceLayers(
            userBackground: const UserBackgroundImage(path: 'x.png'),
          ),
        ),
      );
      expect(painted(), Colors.transparent);
    });

    testWidgets('里面的交互调色板也是平时的颜色', (tester) async {
      const inner = Key('inner');
      await tester.pumpWidget(
        app(
          exempt: standardTheme,
          child: const HolidayColorExempt(child: SizedBox(key: inner)),
        ),
      );
      expect(
        InteractionScope.of(tester.element(find.byKey(inner))).palette.accent,
        _tokens(AppearanceMode.dark).colors.accent,
      );
    });

    testWidgets('还原主题时保留用户当前的交互风格', (tester) async {
      const inner = Key('inner');
      await tester.pumpWidget(
        MaterialApp(
          theme: holidayTheme,
          builder: (context, navigator) => StarBridgeInteractionConfiguration(
            suite: InteractionSuite.values.last,
            child: HolidayExemptThemeScope(
              data: standardTheme,
              child: navigator!,
            ),
          ),
          home: const Scaffold(
            body: HolidayColorExempt(child: SizedBox(key: inner)),
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byKey(inner)));
      expect(
        theme.extension<StarBridgeInteractionTheme>()!.suite,
        InteractionSuite.values.last,
      );
      expect(theme.colorScheme.primary, standardTheme.colorScheme.primary);
    });

    testWidgets('从根浮层打开的交易弹窗也是平时的主色', (tester) async {
      late BuildContext root;
      await tester.pumpWidget(
        app(
          exempt: standardTheme,
          child: Builder(
            builder: (context) {
              root = context;
              return const SizedBox();
            },
          ),
        ),
      );
      const inDialog = Key('in-dialog');
      unawaited(
        tradeMotionDialog<void>(
          Navigator.of(root, rootNavigator: true).overlay!.context,
          (_) => const SizedBox(key: inDialog),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(inDialog)).tokens.colors.accent,
        _tokens(AppearanceMode.dark).colors.accent,
      );
    });

    testWidgets('外观切换时，里面的页面不重建', (tester) async {
      var created = 0;
      Widget page(ThemeData? exempt) => app(
        exempt: exempt,
        child: HolidayColorExempt(child: _CountsCreation(() => created++)),
      );
      await tester.pumpWidget(page(null));
      await tester.pumpWidget(page(standardTheme));
      await tester.pumpWidget(page(null));
      expect(created, 1);
    });
  });
}

class _CountsCreation extends StatefulWidget {
  const _CountsCreation(this.onCreate);

  final VoidCallback onCreate;

  @override
  State<_CountsCreation> createState() => _CountsCreationState();
}

class _CountsCreationState extends State<_CountsCreation> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
