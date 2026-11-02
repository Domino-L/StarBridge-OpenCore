import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/shared/guide/guide_checklist.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_empty_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_listing_demo.dart';
import 'package:starbridge_flutter/shared/guide/guide_page_tip.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_state_adapters.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';

// In-app guide × the four interaction suites (Standard/Scan dark,
// Rail/Glow light), zh-CN at 1.5× text, 1200×1100 — the same review frame
// the motion line uses. Checks the suite face, hover, keyboard activation,
// reduce-motion stability and overflow, and writes one PNG per suite.
final _review = visualOutputDir('in_app_guide_four_style_20261024');

bool _light(InteractionSuite s) =>
    s == InteractionSuite.rail || s == InteractionSuite.glow;

final class _Rig {
  _Rig()
    : port = InMemoryGuideState(
        const GuideState(
          available: true,
          eligible: true,
          done: {'recognize', 'hangar'},
        ),
      ) {
    controller = GuideController(port);
    hub = GuideHub(
      controller: controller,
      online: ValueNotifier(true),
      navigate: routes.add,
    );
  }
  final InMemoryGuideState port;
  late final GuideController controller;
  late final GuideHub hub;
  final routes = <String>[];
  void dispose() {
    hub.dispose();
    controller.dispose();
  }
}

const _capture = Key('four-style-capture');

Future<_Rig> _mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool reduce = false,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1200, 1100);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final rig = _Rig();
  addTearDown(rig.dispose);
  const locale = Locale('zh', 'CN');
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(
          _light(suite) ? AppearanceMode.light : AppearanceMode.dark,
        ).withReducedMotion(reduce),
        locale,
        interactionSuite: suite,
      ),
      builder: (context, child) => StarBridgeInteractionConfiguration(
        suite: suite,
        reduceMotion: reduce,
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
      ),
      home: Scaffold(
        body: GuideScope(
          hub: rig.hub,
          child: GuidePageSurface(
            route: '/rooms',
            available: true,
            child: Builder(
              builder: (context) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      guideChecklist(context, fallback: const SizedBox()),
                      SizedBox(
                        height: 360,
                        child: GuideEmptyState(
                          'rooms',
                          onPrimary: () {},
                          onSecondary: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return rig;
}

Future<List<int>> _pixels(WidgetTester t, Rect rect) async {
  final boundary =
      t.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  final image = await t.runAsync(() => boundary.toImage());
  final data = await t.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final bytes = data!.buffer.asUint8List();
  final out = <int>[];
  for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
    for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
      final i = (y * image!.width + x) * 4;
      out.addAll(bytes.sublist(i, i + 4));
    }
  }
  image!.dispose();
  return out;
}

int _changed(List<int> a, List<int> b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

Future<void> _save(WidgetTester t, String name) async {
  final boundary =
      t.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$_review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

/// Every guide action button renders through the active suite.
void _expectSuiteFaces(WidgetTester t, InteractionSuite suite) {
  final buttons = find.byType(StarBridgeActionButton);
  expect(buttons, findsWidgets);
  if (suite == InteractionSuite.standard) return;
  for (final element in buttons.evaluate()) {
    expect(
      find.descendant(
        of: find.byWidget(element.widget),
        matching: find.byType(SuitePressable),
      ),
      findsWidgets,
      reason: '${element.widget} uses the ${suite.name} face',
    );
  }
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final suite in InteractionSuite.values) {
    group('${suite.name} (${_light(suite) ? 'light' : 'dark'})', () {
      testWidgets('tip, checklist and empty state: face, hover, keyboard', (
        t,
      ) async {
        final rig = await _mount(t, suite);
        expect(t.takeException(), isNull, reason: 'no overflow at 1.5× text');
        expect(find.byKey(const Key('guide-tip-rooms')), findsOneWidget);
        _expectSuiteFaces(t, suite);
        await _save(t, '${suite.name}-page');

        final target = find.byKey(const Key('guide-checklist-fleet-go'));
        final rect = t.getRect(target).inflate(4);
        final before = await _pixels(t, rect);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(target));
        await t.pumpAndSettle();
        expect(
          _changed(before, await _pixels(t, rect)),
          greaterThan(0),
          reason: 'hover shows',
        );

        // Keyboard: focus "知道了" and activate it without a pointer.
        final dismiss = find.byKey(const Key('guide-tip-rooms-dismiss'));
        // The nearest focus node above the label is the button's own.
        Focus.of(
          t.element(find.descendant(of: dismiss, matching: find.text('知道了'))),
        ).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(rig.controller.seen('tip.rooms'), isTrue);
        expect(find.byKey(const Key('guide-tip-rooms')), findsNothing);
      });

      testWidgets('reduce motion: hover settles within two frames', (t) async {
        await _mount(t, suite, reduce: true);
        final target = find.byKey(const Key('guide-empty-rooms-primary'));
        final rect = t.getRect(target).inflate(4);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(target));
        await t.pump();
        await t.pump();
        final early = await _pixels(t, rect);
        await t.pump(const Duration(milliseconds: 608));
        expect(_changed(early, await _pixels(t, rect)), 0);
      });

      testWidgets('coach card and listing demo', (t) async {
        final rig = await _mount(t, suite);
        rig.hub.start('rooms', at: 5);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('guide-tour-card')), findsOneWidget);
        _expectSuiteFaces(t, suite);
        await _save(t, '${suite.name}-coach');
        await t.tap(find.byKey(const Key('guide-tour-next')));
        await t.pumpAndSettle();
        expect(rig.hub.run.value, isNull);

        unawaited(
          showGuideListingDemo(t.element(find.byType(GuidePageSurface))),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        _expectSuiteFaces(t, suite);
        await _save(t, '${suite.name}-listing-demo');
      });
    });
  }
}
