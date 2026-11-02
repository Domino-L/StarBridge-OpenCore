import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace, flush;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cp_test.dart'
    show Harness, HarnessState, key, hit, field;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  testWidgets('standard held splash survives a live control rebuild', (
    t,
  ) async {
    final factory = _ObservedSplashFactory();
    var calls = 0;
    Widget view(String label) => scopedApp(
      StarBridgeNativeIconAction(
        label: label,
        style: ButtonStyle(
          splashFactory: factory,
          overlayColor: const WidgetStatePropertyAll(Color(0x332199ff)),
        ),
        icon: const Icon(Icons.add),
        onActivate: (_) => calls++,
      ),
      InteractionSuite.standard,
    );
    await t.pumpWidget(view('first'));
    await t.pumpAndSettle();
    final gesture = await t.startGesture(t.getCenter(find.byType(IconButton)));
    // TapDown is deliberately delayed by Material's gesture recognition.
    await t.pump(const Duration(milliseconds: 120));
    await t.pump();
    expect(factory.createdColor, const Color(0x332199ff));
    expect(factory.feature!.color, const Color(0x332199ff));
    await t.pumpWidget(view('updated'));
    expect(factory.feature!.color, const Color(0x332199ff));
    await gesture.up();
    await t.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('held native ink follows the current icon theme', (t) async {
    final factory = _ObservedSplashFactory();
    Widget view(Color color) => scopedApp(
      IconButtonTheme(
        data: IconButtonThemeData(
          style: ButtonStyle(
            splashFactory: factory,
            overlayColor: WidgetStatePropertyAll(color),
          ),
        ),
        child: StarBridgeNativeIconAction(
          label: 'theme',
          icon: const Icon(Icons.add),
          onActivate: (_) {},
        ),
      ),
      InteractionSuite.standard,
    );
    await t.pumpWidget(view(const Color(0x332199ff)));
    await t.pumpAndSettle();
    final gesture = await t.startGesture(t.getCenter(find.byType(IconButton)));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump();
    expect(factory.feature!.color, const Color(0x332199ff));
    await t.pumpWidget(view(const Color(0x33ff2233)));
    await t.pump();
    expect(factory.feature!.color, const Color(0x33ff2233));
    await gesture.cancel();
    await t.pumpAndSettle();
    expect(factory.removed, 1);
  });
  testWidgets('owned ink disposes exactly once across interruptions', (
    t,
  ) async {
    final factory = _ObservedSplashFactory();
    var calls = 0;
    Widget view(bool reduce) => scopedApp(
      StarBridgeNativeIconAction(
        label: 'lifetime',
        style: ButtonStyle(splashFactory: factory),
        icon: const Icon(Icons.add),
        onActivate: (_) => calls++,
      ),
      InteractionSuite.standard,
      reduce: reduce,
    );
    for (var i = 0; i < 12; i++) {
      await t.pumpWidget(view(false));
      await t.pumpAndSettle();
      final gesture = await t.startGesture(
        t.getCenter(find.byType(IconButton)),
      );
      await t.pump(const Duration(milliseconds: 120));
      await t.pump();
      switch (i % 4) {
        case 0:
          await gesture.up();
        case 1:
          await gesture.cancel();
        case 2:
          await t.pumpWidget(view(true));
          await t.pump();
          await gesture.up();
        case 3:
          await t.pumpWidget(const SizedBox());
          await gesture.up();
      }
      await t.pumpAndSettle();
      expect(factory.removed, i + 1);
      expect(t.takeException(), isNull);
    }
    expect(calls, 6);
  });
  for (final suite in InteractionSuite.values) {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      testWidgets(
        '$suite $platform preserves native geometry and held gesture across reduce',
        (t) async {
          var calls = 0;
          final frame = GlobalKey();
          const constraints = BoxConstraints(minWidth: 36, minHeight: 36);
          const icon = StandardIcon(StandardIconSemantic.close, size: 16);
          Widget view(bool reduce) => scopedApp(
            Builder(
              builder: (context) => Theme(
                data: Theme.of(context).copyWith(
                  platform: platform,
                  visualDensity: VisualDensity.defaultDensityForPlatform(
                    platform,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      key: frame,
                      child: StarBridgeNativeIconAction(
                        controlKey: const Key('desktop-adapted'),
                        label: 'close',
                        constraints: constraints,
                        padding: const EdgeInsets.all(8),
                        icon: icon,
                        onActivate: (_) => calls++,
                      ),
                    ),
                    IconButton(
                      key: const Key('desktop-original'),
                      onPressed: () {},
                      constraints: constraints,
                      padding: const EdgeInsets.all(8),
                      icon: icon,
                    ),
                  ],
                ),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await t.pumpWidget(view(false));
          await t.pumpAndSettle();
          expect(
            t.getSize(find.byKey(const Key('desktop-adapted'))),
            t.getSize(find.byKey(const Key('desktop-original'))),
          );
          final element = t.element(find.byKey(const Key('desktop-adapted')));
          final gesture = await t.startGesture(
            t.getCenter(find.byKey(const Key('desktop-adapted'))),
          );
          await t.pump(const Duration(milliseconds: 120));
          await t.pump();
          final heldButton = t.widget<IconButton>(
            find.byKey(const Key('desktop-adapted')),
          );
          expect(
            heldButton.statesController!.value,
            contains(WidgetState.pressed),
          );
          await t.pumpWidget(view(true));
          await t.pump();
          expect(
            t.element(find.byKey(const Key('desktop-adapted'))),
            same(element),
          );
          final stopped = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 100));
          final later = await pixels(t, find.byKey(frame));
          final output = Directory(
            'build/reviews/interaction-batch3cp/desktop',
          );
          output.createSync(recursive: true);
          File('${output.path}/${suite.name}-${platform.name}-stopped.png')
              .writeAsBytesSync(stopped);
          File('${output.path}/${suite.name}-${platform.name}-later.png')
              .writeAsBytesSync(later);
          expect(later, orderedEquals(stopped));
          await gesture.up();
          await t.pumpAndSettle();
          expect(calls, 1);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input actual browser new-tab motion/static/reduce pixels',
        (t) async {
          final native = BrowserFake(), work = workspace(), frame = GlobalKey();
          final h = GlobalKey<HarnessState>();
          size(t, const Size(900, 650));
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: Harness(native, work, suite, key: h),
            ),
          );
          await flush(t);
          final reply = native.pendingAction = Completer<Object?>();
          await hit(t, key('browser-new-tab'), input);
          await t.pump(const Duration(milliseconds: 30));
          final a = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 110));
          final b = await pixels(t, find.byKey(frame));
          expect(
            b,
            input == 'pointer' ? isNot(orderedEquals(a)) : orderedEquals(a),
          );
          h.currentState!.change(() => h.currentState!.reduce = true);
          await flush(t);
          final stopped = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 100));
          expect(await pixels(t, find.byKey(frame)), orderedEquals(stopped));
          reply.complete();
          await flush(t);
          await t.pumpWidget(const SizedBox());
          work.dispose();
        },
      );
    }
    for (final config in [(900.0, 1.0), (344.0, 2.0), (700.0, 1.0)]) {
      testWidgets('$suite $config actual browser review states', (t) async {
        final native = BrowserFake(), work = workspace(), frame = GlobalKey();
        native.tabs.first['title'] = '星海舰桥 · 很长的页面标题需要保留省略和可访问名称';
        final h = GlobalKey<HarnessState>();
        size(t, Size(config.$1, 600));
        t.platformDispatcher.textScaleFactorTestValue = config.$2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: Harness(native, work, suite, key: h),
          ),
        );
        h.currentState!.change(() => h.currentState!.light = config.$1 == 700);
        await t.pumpAndSettle();
        Future<void> shot(String state) async {
          final data = await pixels(t, find.byKey(frame));
          final file = File(
            'build/reviews/interaction-batch3cp/'
            '${suite.name}-${config.$1.toInt()}-${config.$2}-$state.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data);
          expect(t.takeException(), isNull);
        }

        await shot('idle');
        final target = key('browser-new-tab');
        final reply = native.pendingAction = Completer<Object?>();
        await t.tap(target);
        await flush(t);
        await t.pump(const Duration(milliseconds: 70));
        await shot('press-pending');
        reply.completeError(PlatformException(code: 'menu.browser_tab_limit'));
        await flush(t);
        await shot('rejected');
        await t.ensureVisible(key('browser-address'));
        await t.enterText(key('browser-address'), '未提交的星际公民搜索');
        await t.pump();
        await t.pump(const Duration(milliseconds: 70));
        await shot('edit');
        final viewport = native.calls
            .lastWhere((c) => c.$1 == 'browserBounds')
            .$2;
        expect(viewport['height'] as double, greaterThan(0));
        expect(viewport['width'] as double, closeTo(config.$1, .01));
        expect(field(t).controller!.text, '未提交的星际公民搜索');
        await t.pumpWidget(const SizedBox());
        work.dispose();
      });
    }
  }
}

class _ObservedSplashFactory extends InteractiveInkFeatureFactory {
  InteractiveInkFeature? feature;
  Color? createdColor;
  int removed = 0;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    createdColor = color;
    return feature = InkRipple.splashFactory.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: () {
        removed++;
        onRemoved?.call();
      },
    );
  }
}
