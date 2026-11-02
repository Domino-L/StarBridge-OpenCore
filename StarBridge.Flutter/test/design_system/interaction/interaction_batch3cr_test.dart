import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' as render;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'native held drag survives enabling reduced motion and ends once',
    (t) async {
      var value = .3, reduce = false;
      late StateSetter update;
      final ended = <double>[];
      var cancelled = 0;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) {
            update = state;
            return scopedApp(
              Center(
                child: SizedBox(
                  width: 300,
                  child: StarBridgeSlider(
                    controlKey: const Key('held-slider'),
                    value: value,
                    onChanged: (v) => state(() => value = v),
                    onChangeEnd: ended.add,
                    onChangeCancel: () => cancelled++,
                  ),
                ),
              ),
              InteractionSuite.standard,
              reduce: reduce,
            );
          },
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(const Key('held-slider')));
      final gesture = await t.startGesture(
        Offset(rect.left + 95, rect.center.dy),
      );
      await gesture.moveBy(const Offset(35, 0));
      await t.pump(const Duration(milliseconds: 120));
      expect(value, greaterThan(.3));
      expect(ended, isEmpty);
      final before = value;
      update(() => reduce = true);
      await t.pump();
      await t.pump();
      await gesture.moveBy(const Offset(70, 0));
      await t.pump();
      expect(value, greaterThan(before));
      await gesture.up();
      await t.pumpAndSettle();
      expect(ended, [value]);
      expect(cancelled, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reduced discrete slider paints the actual newly selected value',
    (t) async {
      var value = .2;
      final centers = <Offset>[];
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 300,
                  child: SliderTheme(
                    data: SliderTheme.of(context)
                        .copyWith(thumbShape: RecordingThumb(centers.add)),
                    child: StarBridgeSlider(
                      controlKey: const Key('discrete-slider'),
                      value: value,
                      divisions: 100,
                      onChanged: (v) => state(() => value = v),
                    ),
                  ),
                ),
              ),
            ),
            InteractionSuite.standard,
            reduce: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      final before = centers.last.dx;
      final rect = t.getRect(find.byKey(const Key('discrete-slider')));
      await t.tapAt(Offset(rect.right - 40, rect.center.dy));
      await t.pump();
      await t.pump();
      expect(value, greaterThan(.7));
      expect(centers.last.dx, greaterThan(before + 100));
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final custom in [false, true]) {
    testWidgets(
      'static native thumb retains its original offset geometry custom=$custom',
      (t) async {
        var original = true;
        late StateSetter update;
        final centers = <Offset>[];
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, state) {
              update = state;
              return scopedApp(
                Builder(
                  builder: (context) => Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 57, top: 84),
                      child: SizedBox(
                        width: 300,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: RecordingThumb(
                              centers.add,
                              disabledThumbRadius: custom ? 30 : 10,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: custom ? 4 : 24,
                            ),
                          ),
                          child: original
                              ? Slider(
                                  value: .67,
                                  divisions: 100,
                                  onChanged: (_) {},
                                )
                              : StarBridgeSlider(
                                  value: .67,
                                  divisions: 100,
                                  onChanged: (_) {},
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                InteractionSuite.standard,
                reduce: true,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        final expected = centers.last;
        update(() => original = false);
        await t.pumpAndSettle();
        expect(centers.last, expected);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'cancelled native drag does not swallow the next keyboard commit',
    (t) async {
      var value = .4;
      final ended = <double>[];
      var cancelled = 0;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Center(
              child: SizedBox(
                width: 300,
                child: StarBridgeSlider(
                  controlKey: const Key('cancel-slider'),
                  value: value,
                  onChanged: (v) => state(() => value = v),
                  onChangeEnd: ended.add,
                  onChangeCancel: () => cancelled++,
                ),
              ),
            ),
            InteractionSuite.standard,
          ),
        ),
      );
      await t.pumpAndSettle();
      final target = find.byKey(const Key('cancel-slider'));
      final gesture = await t.startGesture(t.getCenter(target));
      await gesture.moveBy(const Offset(30, 0));
      await t.pump();
      await gesture.cancel();
      await t.pumpAndSettle();
      expect(cancelled, 1);
      expect(ended, isEmpty);
      t.widget<Slider>(target).focusNode!.requestFocus();
      await t.pump();
      final before = value;
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(value, closeTo(before + .05, .00001));
      expect(ended, [value]);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native keyboard to pointer handoff never restores the old painted value',
    (t) async {
      var value = .2;
      final centers = <Offset>[];
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 300,
                  child: SliderTheme(
                    data: SliderTheme.of(context)
                        .copyWith(thumbShape: RecordingThumb(centers.add)),
                    child: StarBridgeSlider(
                      controlKey: const Key('handoff-slider'),
                      value: value,
                      divisions: 100,
                      onChanged: (v) => state(() => value = v),
                    ),
                  ),
                ),
              ),
            ),
            InteractionSuite.standard,
          ),
        ),
      );
      await t.pumpAndSettle();
      final target = find.byKey(const Key('handoff-slider'));
      t.widget<Slider>(target).focusNode!.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.pump();
      expect(value, 1);
      final before = centers.last;
      final rect = t.getRect(target);
      final gesture = await t.startGesture(
        Offset(rect.left + before.dx, rect.center.dy),
      );
      await t.pump();
      final after = centers.last;
      final actualValue = value;
      await gesture.up();
      await t.pumpAndSettle();
      // A real pointer-down may legitimately choose the adjacent native tick.
      // Compare against the native target for that actual value, not the old key target.
      await t.pumpWidget(
        scopedApp(
          Builder(
            builder: (context) => Center(
              child: SizedBox(
                width: 300,
                child: SliderTheme(
                  data: SliderTheme.of(context)
                      .copyWith(thumbShape: RecordingThumb(centers.add)),
                  child: Slider(
                    value: actualValue,
                    divisions: 100,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
          InteractionSuite.standard,
        ),
      );
      await t.pumpAndSettle();
      expect(after, centers.last);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('first Tab focus is immediately static before any value key', (
    t,
  ) async {
    final frame = GlobalKey();
    await t.pumpWidget(
      scopedApp(
        Center(
          child: RepaintBoundary(
            key: frame,
            child: SizedBox(
              width: 300,
              child: StarBridgeSlider(
                controlKey: const Key('tab-slider'),
                value: .4,
                divisions: 100,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(
      t.widget<Slider>(find.byKey(const Key('tab-slider'))).focusNode!.hasFocus,
      isTrue,
    );
    await t.pump(const Duration(milliseconds: 20));
    final first = await render.pixels(t, find.byKey(frame));
    await t.pump(const Duration(milliseconds: 100));
    final next = await render.pixels(t, find.byKey(frame));
    expect(next, first);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Tab away and back after pointer use has no native focus fade tail',
    (t) async {
      final frame = GlobalKey(), neighbor = FocusNode();
      await t.pumpWidget(
        scopedApp(
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: frame,
                  child: SizedBox(
                    width: 300,
                    child: StarBridgeSlider(
                      controlKey: const Key('tab-away'),
                      value: .4,
                      onChanged: (_) {},
                    ),
                  ),
                ),
                Focus(
                  focusNode: neighbor,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ],
            ),
          ),
          InteractionSuite.standard,
        ),
      );
      await t.pumpAndSettle();
      // Native Slider does not take keyboard focus from a mouse click alone.
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final pointer = await t.startGesture(
        t.getCenter(find.byKey(const Key('tab-away'))),
        kind: ui.PointerDeviceKind.mouse,
      );
      await pointer.up();
      await t.pumpAndSettle();
      await pointer.moveTo(const Offset(1, 1));
      await t.pumpAndSettle();
      expect(
        t.widget<Slider>(find.byKey(const Key('tab-away'))).focusNode!.hasFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.pump();
      expect(neighbor.hasFocus, isTrue);
      await t.pump(const Duration(milliseconds: 20));
      final first = await render.pixels(t, find.byKey(frame));
      await t.pump(const Duration(milliseconds: 100));
      final next = await render.pixels(t, find.byKey(frame));
      expect(next, first);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      await t.pump();
      expect(
        t.widget<Slider>(find.byKey(const Key('tab-away'))).focusNode!.hasFocus,
        isTrue,
      );
      await t.pump(const Duration(milliseconds: 20));
      final returned = await render.pixels(t, find.byKey(frame));
      await t.pump(const Duration(milliseconds: 100));
      expect(await render.pixels(t, find.byKey(frame)), returned);
      await pointer.removePointer();
      await t.pumpWidget(const SizedBox());
      neighbor.dispose();
    },
  );
  testWidgets('mouse blur then keyboard return has no native focus fade tail', (
    t,
  ) async {
    final frame = GlobalKey(), neighbor = FocusNode();
    await t.pumpWidget(
      scopedApp(
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: frame,
                child: SizedBox(
                  width: 300,
                  child: StarBridgeSlider(
                    controlKey: const Key('mouse-blur-slider'),
                    value: .4,
                    onChanged: (_) {},
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  key: const Key('neighbor'),
                  focusNode: neighbor,
                ),
              ),
            ],
          ),
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    final focus = t
        .widget<Slider>(find.byKey(const Key('mouse-blur-slider')))
        .focusNode!;
    expect(focus.hasFocus, isTrue);
    final pointer = await t.startGesture(
      t.getCenter(find.byKey(const Key('mouse-blur-slider'))),
      kind: ui.PointerDeviceKind.mouse,
    );
    await pointer.up();
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(const Key('neighbor')),
      kind: ui.PointerDeviceKind.mouse,
    );
    await pointer.moveTo(const Offset(1, 1));
    await t.pumpAndSettle();
    expect(neighbor.hasFocus, isTrue);
    expect(focus.hasFocus, isFalse);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    await t.pump();
    expect(focus.hasFocus, isTrue);
    await t.pump(const Duration(milliseconds: 20));
    final returned = await render.pixels(t, find.byKey(frame));
    await t.pump(const Duration(milliseconds: 100));
    expect(await render.pixels(t, find.byKey(frame)), returned);
    await pointer.removePointer();
    await t.pumpWidget(const SizedBox());
    neighbor.dispose();
  });
  testWidgets(
    'native discrete value bubble stays aligned with the actual thumb',
    (t) async {
      var value = .2;
      final thumbs = <Offset>[], bubbles = <Offset>[];
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 300,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: RecordingThumb(thumbs.add),
                      valueIndicatorShape: RecordingIndicator(bubbles.add),
                      showValueIndicator: ShowValueIndicator.onDrag,
                    ),
                    child: StarBridgeSlider(
                      controlKey: const Key('bubble-slider'),
                      value: value,
                      divisions: 10,
                      onChanged: (v) => state(() => value = v),
                    ),
                  ),
                ),
              ),
            ),
            InteractionSuite.standard,
          ),
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(const Key('bubble-slider')));
      final gesture = await t.startGesture(
        Offset(rect.left + 75, rect.center.dy),
        kind: ui.PointerDeviceKind.mouse,
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      await gesture.moveBy(const Offset(140, 0));
      await t.pump();
      await gesture.moveBy(const Offset(10, 0));
      await t.pump(const Duration(milliseconds: 16));
      expect(value, greaterThan(.6));
      expect(bubbles, isNotEmpty);
      expect((bubbles.last - thumbs.last).distance, lessThan(.01));
      await gesture.up();
      await gesture.removePointer();
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final material3 in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets(
        'native default bubble visual material3=$material3 rtl=$rtl',
        (t) async {
          Future<List<int>> sample(bool original) async {
            final frame = GlobalKey();
            var value = .2;
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: StatefulBuilder(
                  builder: (_, state) => scopedApp(
                    Builder(
                      builder: (context) => Theme(
                        data: ThemeData.from(
                          colorScheme: Theme.of(context).colorScheme,
                          textTheme: Theme.of(context).textTheme,
                          useMaterial3: material3,
                        ),
                        child: Directionality(
                          textDirection: rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 61,
                                top: 130,
                              ),
                              child: SizedBox(
                                width: 300,
                                child: original
                                    ? Slider(
                                        key: const Key('default-bubble'),
                                        value: value,
                                        label: value.toStringAsFixed(2),
                                        divisions: 10,
                                        onChanged: (v) =>
                                            state(() => value = v),
                                      )
                                    : StarBridgeSlider(
                                        controlKey: const Key('default-bubble'),
                                        value: value,
                                        divisions: 10,
                                        onChanged: (v) =>
                                            state(() => value = v),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    InteractionSuite.standard,
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            final rect = t.getRect(find.byKey(const Key('default-bubble')));
            final gesture = await t.startGesture(
              Offset(rect.left + 185, rect.center.dy),
              kind: ui.PointerDeviceKind.mouse,
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 500));
            final pixels = await t.runAsync(() async {
              final picture = await t
                  .renderObject<RenderRepaintBoundary>(find.byKey(frame))
                  .toImage();
              try {
                final data = (await picture.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                return List<int>.of(
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                );
              } finally {
                picture.dispose();
              }
            });
            await gesture.up();
            await gesture.removePointer();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            return pixels!;
          }

          expect(await sample(false), await sample(true));
        },
      );
    }
  }
  for (final held in [false, true]) {
    testWidgets('native mouse held=$held retains original decorative phases', (
      t,
    ) async {
      Future<List<double?>> sample(bool original) async {
        var value = .4;
        final phases = <double>[];
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, state) => scopedApp(
              Builder(
                builder: (context) => Center(
                  child: SizedBox(
                    width: 300,
                    child: SliderTheme(
                      data: SliderTheme.of(context)
                          .copyWith(overlayShape: RecordingOverlay(phases.add)),
                      child: original
                          ? Slider(
                              key: const Key('mouse-slider'),
                              value: value,
                              onChanged: (v) => state(() => value = v),
                            )
                          : StarBridgeSlider(
                              controlKey: const Key('mouse-slider'),
                              value: value,
                              onChanged: (v) => state(() => value = v),
                            ),
                    ),
                  ),
                ),
              ),
              InteractionSuite.standard,
            ),
          ),
        );
        await t.pumpAndSettle();
        phases.clear();
        TestGesture? gesture;
        if (held) {
          gesture = await t.startGesture(
            t.getCenter(find.byKey(const Key('mouse-slider'))),
            kind: ui.PointerDeviceKind.mouse,
          );
          await t.pump(const Duration(milliseconds: 120));
        } else {
          await t.tap(
            find.byKey(const Key('mouse-slider')),
            kind: ui.PointerDeviceKind.mouse,
          );
          await t.pump();
        }
        final result = <double?>[phases.lastOrNull];
        for (var i = 0; i < 2; i++) {
          await t.pump(const Duration(milliseconds: 30));
          result.add(phases.lastOrNull);
        }
        await gesture?.up();
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        return result;
      }

      final native = await sample(true);
      final adapted = await sample(false);
      expect(adapted, native);
      if (held) {
        expect(adapted.whereType<double>().any((v) => v > 0 && v < 1), isTrue);
      }
    });
  }
}

/// Observe the public theme paint contract while retaining native thumb paint.
class RecordingThumb extends RoundSliderThumbShape {
  const RecordingThumb(
    this.record, {
    super.enabledThumbRadius,
    super.disabledThumbRadius,
  });
  final ValueChanged<Offset> record;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    record(center);
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}

class RecordingIndicator extends RectangularSliderValueIndicatorShape {
  const RecordingIndicator(this.record);
  final ValueChanged<Offset> record;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    record(center);
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}

class RecordingOverlay extends RoundSliderOverlayShape {
  const RecordingOverlay(this.record);
  final ValueChanged<double> record;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    record(activationAnimation.value);
    super.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      isDiscrete: isDiscrete,
      labelPainter: labelPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      textDirection: textDirection,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
    );
  }
}
