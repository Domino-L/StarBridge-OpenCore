import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/design_system/styles/native_appearance_player.dart';

import 'interaction_batch3bf_test.dart'
    show ControlledCodec, tinyImage, TinyBundle;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ac_test.dart' show Live, LiveState;
import 'interaction_batch3m_test.dart' show keyPress;
import 'interaction_batch3b_test.dart' show exposedNodes;

class PreviewFixture {
  PreviewFixture(this.image);
  final ui.Image image;
  final codecs = <ControlledCodec>[];
  final bundle = TinyBundle();
  Future<ui.Codec> decode(List<int> bytes, {int? targetWidth}) async {
    final codec = ControlledCodec(image);
    codecs.add(codec);
    return codec;
  }

  Widget player({bool native = false, bool controls = true}) =>
      NativeAppearancePlayer(
        asset: 'fixtures/native-appearance-cycle',
        repeat: true,
        nativePixels: native,
        controls: controls,
        decoder: decode,
        assetBundle: bundle,
      );
  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    for (final codec in codecs) {
      while (codec.pending.isNotEmpty) {
        codec.finish();
      }
    }
    await t.pump();
    image.dispose();
  }
}

class SplashProbe extends InteractiveInkFeatureFactory {
  int created = 0;
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
    created++;
    return NoSplash.splashFactory.create(
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
      onRemoved: onRemoved,
    );
  }
}

Future<PreviewFixture> mount(
  WidgetTester t,
  InteractionSuite suite, {
  bool native = false,
  bool controls = true,
  bool reduce = false,
}) async {
  final fixture = PreviewFixture(await tinyImage(t));
  addTearDown(() => fixture.dispose(t));
  await t.pumpWidget(
    scopedApp(
      fixture.player(native: native, controls: controls),
      suite,
      reduce: reduce,
    ),
  );
  await t.pump();
  await t.pump();
  return fixture;
}

Future<void> activate(WidgetTester t, String source, Key key) async {
  final target = find.byKey(key);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    await keyPress(t, target);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pump();
}

double position(WidgetTester t) =>
    t.widget<StarBridgeSlider>(find.byType(StarBridgeSlider)).value;
void focusProgress(WidgetTester t) {
  if (find.byType(SuiteSlider).evaluate().isNotEmpty) {
    t.widget<SuiteSlider>(find.byType(SuiteSlider)).focusNode!.requestFocus();
  } else {
    t.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
  }
}

void main() {
  for (final source in ['pointer', 'keyboard', 'reader']) {
    testWidgets('standard $source creates only intentional pointer ink', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      try {
        final fixture = PreviewFixture(await tinyImage(t));
        addTearDown(() => fixture.dispose(t));
        final splash = SplashProbe();
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (c) => Theme(
                data: Theme.of(c).copyWith(
                  textButtonTheme: TextButtonThemeData(
                    style: ButtonStyle(splashFactory: splash),
                  ),
                ),
                child: fixture.player(),
              ),
            ),
            InteractionSuite.standard,
          ),
        );
        await t.pump();
        await t.pump();
        await activate(t, source, const Key('native-appearance-playback'));
        expect(splash.created, source == 'pointer' ? 1 : 0);
      } finally {
        semantics.dispose();
      }
    });
  }
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite preview controls use approved shared adapters', (
      t,
    ) async {
      await mount(t, suite);
      expect(find.byType(StarBridgeActionButton), findsNWidgets(2));
      expect(find.byType(StarBridgeSlider), findsOneWidget);
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source pause/play/replay keep actual media commands',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final fixture = await mount(t, suite);
            await activate(t, source, const Key('native-appearance-playback'));
            fixture.codecs.last.hold = true;
            await t.pump(const Duration(milliseconds: 600));
            expect(position(t), 0);
            expect(fixture.codecs.last.requests, 1);
            await activate(t, source, const Key('native-appearance-playback'));
            await t.pump(const Duration(milliseconds: 40));
            expect(fixture.codecs.last.pending.length, 1);
            fixture.codecs.last.finish();
            await t.pump();
            await t.pump();
            expect(position(t), 1);
            await activate(t, source, const Key('native-appearance-replay'));
            expect(fixture.codecs.length, 2);
            expect(position(t), 0);
            await activate(t, source, const Key('native-appearance-playback'));
            await t.pump(const Duration(milliseconds: 600));
            expect(position(t), 0);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source seeking uses committed frames and cancels safely',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final fixture = await mount(t, suite);
            await activate(
              t,
              'keyboard',
              const Key('native-appearance-playback'),
            );
            if (source == 'pointer') {
              final slider = t.widget<StarBridgeSlider>(
                find.byType(StarBridgeSlider),
              );
              slider.onChanged!(2);
              await t.pump();
              expect(position(t), 2);
              expect(
                fixture.codecs.length,
                1,
                reason: 'no decode until release',
              );
              slider.onChangeCancel!();
              await t.pump();
              await t.pump();
              expect(position(t), 0);
              final updated = t.widget<StarBridgeSlider>(
                find.byType(StarBridgeSlider),
              );
              updated.onChanged!(2);
              updated.onChangeEnd!(2);
            } else if (source == 'keyboard') {
              focusProgress(t);
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            } else {
              final label = t
                  .widget<StarBridgeSlider>(find.byType(StarBridgeSlider))
                  .semanticLabel;
              final node = exposedNodes(t).singleWhere(
                (node) =>
                    node.getSemanticsData().flagsCollection.isSlider &&
                    node.getSemanticsData().label == label,
              );
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.increase),
                isTrue,
              );
              t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
                node.id,
                ui.SemanticsAction.increase,
              );
            }
            await t.pump();
            await t.pump();
            expect(position(t), source == 'pointer' ? 2 : 1);
            await t.pump(const Duration(milliseconds: 600));
            expect(
              position(t),
              source == 'pointer' ? 2 : 1,
              reason: 'seek stays paused',
            );
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite live app reduce stops decode and preserves static seeking',
      (t) async {
        final fixture = PreviewFixture(await tinyImage(t));
        addTearDown(() => fixture.dispose(t));
        final live = GlobalKey<LiveState>();
        await t.pumpWidget(Live(fixture.player(), suite, key: live));
        await t.pump();
        await t.pump();
        fixture.codecs.last.hold = true;
        await t.pump(const Duration(milliseconds: 40));
        expect(fixture.codecs.last.pending.length, 1);
        live.currentState!.change(() => live.currentState!.reduce = true);
        await t.pump();
        fixture.codecs.last.finish();
        await t.pump();
        await t.pump();
        expect(position(t), 0);
        final play = t
            .widgetList<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            )
            .first;
        expect(play.onActivate, isNull);
        await t.pump(const Duration(milliseconds: 600));
        expect(position(t), 0);
        expect(t.binding.hasScheduledFrame, isFalse);
        focusProgress(t);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.end);
        await t.pump();
        await t.pump();
        expect(position(t), 2);
        expect(t.binding.hasScheduledFrame, isFalse);
      },
    );
    for (final native in [false, true]) {
      testWidgets(
        '$suite native=$native pointer feedback and keyboard settle',
        (t) async {
          // Keep Material's focus-mode colour transition out of the command
          // feedback assertion. Focus behaviour is checked separately.
          final strategy = FocusManager.instance.highlightStrategy;
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
          final fixture = await mount(t, suite, native: native);
          fixture.codecs.last.hold = true;
          await activate(t, 'pointer', const Key('native-appearance-playback'));
          if (suite != InteractionSuite.standard) {
            expect(
              t.binding.hasScheduledFrame,
              isTrue,
              reason: 'active pointer feedback retained',
            );
          }
          await t.pump(const Duration(milliseconds: 600));
          expect(t.binding.hasScheduledFrame, isFalse);
          await activate(
            t,
            'keyboard',
            const Key('native-appearance-playback'),
          );
          await t.pump(const Duration(milliseconds: 40));
          expect(fixture.codecs.last.pending.length, 1);
          if (suite == InteractionSuite.standard) {
            // Native Material's focus colour has its own short transition;
            // the SplashProbe above checks the command itself without this
            // global scheduled-frame false positive.
            await t.pump(const Duration(milliseconds: 200));
          }
          expect(
            t.binding.hasScheduledFrame,
            isFalse,
            reason: 'intentional playback is not control decoration',
          );
          await activate(
            t,
            'keyboard',
            const Key('native-appearance-playback'),
          );
          fixture.codecs.last.finish();
          await t.pump();
          await t.pump();
          expect(position(t), 0);
          expect(t.binding.hasScheduledFrame, isFalse);
          final picture = t.widget<RawImage>(find.byType(RawImage));
          expect(picture.fit, native ? BoxFit.none : BoxFit.contain);
          expect(
            picture.filterQuality,
            native ? FilterQuality.none : FilterQuality.medium,
          );
        },
      );
    }
    testWidgets(
      '$suite fullscreen Space activates a focused control only once',
      (t) async {
        final fixture = await mount(t, suite, native: true);
        await activate(t, 'keyboard', const Key('native-appearance-playback'));
        final target = find.byKey(const Key('native-appearance-playback'));
        final text = find
            .descendant(of: target, matching: find.byType(Text))
            .first;
        Focus.of(t.element(text)).requestFocus();
        await t.pump();
        fixture.codecs.last.hold = true;
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(
          fixture.codecs.last.pending.length,
          1,
          reason: 'one Play rather than Play then Pause',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pump();
        fixture.codecs.last.finish();
        await t.pump();
        await t.pump();
        expect(position(t), 0);
      },
    );
    testWidgets('$suite hidden controls do not create input or focus targets', (
      t,
    ) async {
      await mount(t, suite, native: true, controls: false);
      expect(find.byType(StarBridgeActionButton), findsNothing);
      expect(find.byType(StarBridgeSlider), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
    });
    testWidgets(
      '$suite palette-only changes do not postpone the media deadline',
      (t) async {
        final fixture = PreviewFixture(await tinyImage(t));
        addTearDown(() => fixture.dispose(t));
        final live = GlobalKey<LiveState>();
        await t.pumpWidget(Live(fixture.player(), suite, key: live));
        await t.pump();
        await t.pump();
        fixture.codecs.last.hold = true;
        await t.pump(const Duration(milliseconds: 30));
        live.currentState!.change(() => live.currentState!.light = true);
        await t.pump();
        await t.pump(const Duration(milliseconds: 10));
        expect(
          fixture.codecs.last.pending.length,
          1,
          reason: 'original 40ms deadline survives a palette rebuild',
        );
      },
    );
    testWidgets(
      '$suite real pointer drag cancellation restores displayed frame',
      (t) async {
        final fixture = await mount(t, suite);
        await activate(t, 'keyboard', const Key('native-appearance-playback'));
        await t.pump(const Duration(milliseconds: 600));
        final area = t.getRect(
          find.byKey(const Key('native-appearance-progress')),
        );
        final gesture = await t.startGesture(area.center);
        await gesture.moveBy(Offset(area.width * .2, 0));
        await t.pump();
        expect(position(t), greaterThan(0));
        await gesture.cancel();
        await t.pump();
        await t.pump();
        expect(position(t), 0);
        expect(fixture.codecs.length, 2);
        await t.pump(const Duration(milliseconds: 600));
        expect(position(t), 0);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite real pointer drag release commits without tick snapping',
      (t) async {
        final fixture = await mount(t, suite);
        await activate(t, 'keyboard', const Key('native-appearance-playback'));
        await t.pump(const Duration(milliseconds: 600));
        final area = t.getRect(
          find.byKey(const Key('native-appearance-progress')),
        );
        final gesture = await t.startGesture(area.center);
        await gesture.moveBy(Offset(area.width * .4, 0));
        await t.pump();
        await gesture.up();
        await t.pump();
        await t.pump();
        expect(position(t), 2);
        expect(fixture.codecs.length, 2);
        expect(
          t.widget<StarBridgeSlider>(find.byType(StarBridgeSlider)).divisions,
          isNull,
        );
        await t.pump(const Duration(milliseconds: 600));
        expect(position(t), 2);
      },
    );
  }
}
