import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_crosshair_portal_regression_test.dart'
    show portalParents;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3fc_visibility_test.dart' show visibilityFrames;
import 'interaction_batch3i_test.dart' show scopedApp;

const nativeName = 'Native opacity accessible name';
const nativeKey = Key('3fi-native-slider');

ThemeData nativeTheme(BuildContext context, bool material3) => ThemeData.from(
  colorScheme: Theme.of(context).colorScheme,
  textTheme: Theme.of(context).textTheme,
  useMaterial3: material3,
);

void readerStep(WidgetTester t, ui.SemanticsAction action) {
  final nodes = exposedNodes(t).where((node) {
    final data = node.getSemanticsData();
    return data.flagsCollection.isSlider &&
        data.label == nativeName &&
        data.hasAction(action);
  }).toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    action,
  );
}

Map<int, int> nativePortals(WidgetTester t) => portalParents(
  t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
);

class IndicatorText extends SliderComponentShape {
  const IndicatorText(this.texts);
  final List<String> texts;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(40, 20);
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
  }) => texts.add(labelPainter.plainText);
}

class RectangularIndicatorText extends RectangularSliderValueIndicatorShape {
  const RectangularIndicatorText(this.paints, this.measurements);
  final List<String> paints, measurements;
  @override
  Size getPreferredSize(
    bool isEnabled,
    bool isDiscrete, {
    TextPainter? labelPainter,
    double? textScaleFactor,
  }) {
    if (labelPainter != null) measurements.add(labelPainter.plainText);
    return super.getPreferredSize(
      isEnabled,
      isDiscrete,
      labelPainter: labelPainter,
      textScaleFactor: textScaleFactor,
    );
  }

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
  }) => paints.add(labelPainter.plainText);
}

void main() {
  setUpAll(loadFonts);
  for (final material3 in [false, true]) {
    for (final rtl in [false, true]) {
      for (final divisions in [null, 17]) {
        testWidgets(
          '3fi native AX material3=$material3 rtl=$rtl divisions=$divisions preserves one node and exact command',
          (t) async {
            size(t, const Size(1000, 800));
            final semantics = t.ensureSemantics();
            var value = .5, reduce = false, enabled = true;
            final step = divisions == null ? .07 : .05;
            final changes = <(double, InteractionSource)>[];
            final endings = <(double, InteractionSource)>[];
            late StateSetter update;
            try {
              await t.pumpWidget(
                StatefulBuilder(
                  builder: (_, state) {
                    update = state;
                    return scopedApp(
                      Builder(
                        builder: (context) => Theme(
                          data: nativeTheme(context, material3),
                          child: Directionality(
                            textDirection: rtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: SizedBox(
                              width: 430,
                              child: StarBridgeSlider(
                                controlKey: nativeKey,
                                semanticLabel: nativeName,
                                value: value,
                                min: .15,
                                max: 1,
                                divisions: divisions,
                                keyboardStep: step,
                                valueLabel: (v) => '${(v * 100).round()}%',
                                onChanged: !enabled
                                    ? null
                                    : (v) {
                                        changes.add((
                                          v,
                                          currentStarBridgeActivationSource,
                                        ));
                                        state(() => value = v);
                                      },
                                onChangeEnd: (v) => endings.add((
                                  v,
                                  currentStarBridgeActivationSource,
                                )),
                              ),
                            ),
                          ),
                        ),
                      ),
                      InteractionSuite.standard,
                      reduce: reduce,
                    );
                  },
                ),
              );
              await visibilityFrames(t);
              final before = nativePortals(t);
              expect(before, hasLength(1));
              var node = exposedNodes(t)
                  .where((n) => n.getSemanticsData().flagsCollection.isSlider)
                  .single;
              final sliderId = node.id;
              expect(node.getSemanticsData().label, nativeName);
              expect(node.getSemanticsData().value, '50%');
              expect(
                node.getSemanticsData().increasedValue,
                '${((.5 + step) * 100).round()}%',
              );
              expect(
                node.getSemanticsData().decreasedValue,
                '${((.5 - step) * 100).round()}%',
              );
              for (final action in [
                ui.SemanticsAction.increase,
                ui.SemanticsAction.increase,
                ui.SemanticsAction.decrease,
              ]) {
                final old = value;
                final count = endings.length;
                readerStep(t, action);
                await t.pump();
                await t.pump();
                expect(
                  value,
                  closeTo(
                    old +
                        (action == ui.SemanticsAction.increase ? step : -step),
                    1e-8,
                  ),
                );
                expect(changes.last, (value, InteractionSource.keyboard));
                expect(
                  endings,
                  hasLength(count + 1),
                  reason: 'native start/change/end produces exactly one final callback',
                );
                expect(endings.last, (value, InteractionSource.keyboard));
                node = exposedNodes(t)
                    .where((n) => n.getSemanticsData().flagsCollection.isSlider)
                    .single;
                expect(node.id, sliderId);
                expect(
                  node.getSemanticsData().value,
                  '${(value * 100).round()}%',
                );
                expect(nativePortals(t), before);
              }
              final focus = t.widget<Slider>(find.byKey(nativeKey)).focusNode!;
              FocusScope.of(t.element(find.byKey(nativeKey))).unfocus();
              await t.pump();
              await t.pump();
              for (var i = 0; !focus.hasPrimaryFocus && i < 15; i++) {
                await t.sendKeyEvent(LogicalKeyboardKey.tab);
                await t.pump();
                await t.pump();
              }
              expect(focus.hasPrimaryFocus, isTrue);
              final old = value;
              await t.sendKeyEvent(
                rtl
                    ? LogicalKeyboardKey.arrowLeft
                    : LogicalKeyboardKey.arrowRight,
              );
              await t.pump();
              await t.pump();
              expect(value, closeTo(old + step, 1e-8));
              expect(endings.last, (value, InteractionSource.keyboard));
              update(() => reduce = true);
              await t.pump();
              await t.pump();
              expect(nativePortals(t), before);
              expect(
                exposedNodes(
                  t,
                ).where((n) => n.getSemanticsData().flagsCollection.isSlider),
                hasLength(1),
              );
              final endCount = endings.length;
              update(() => enabled = false);
              await t.pump();
              await t.pump();
              node = exposedNodes(t)
                  .where((n) => n.getSemanticsData().flagsCollection.isSlider)
                  .single;
              expect(node.id, sliderId);
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.increase),
                isFalse,
              );
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.decrease),
                isFalse,
              );
              expect(nativePortals(t), before);
              expect(endings, hasLength(endCount));
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              semantics.dispose();
            }
          },
        );
      }
    }

    testWidgets(
      '3fi native material3=$material3 paints original numeric indicator not accessible name',
      (t) async {
        size(t, const Size(1000, 800));
        final paints = <String>[], measured = <String>[];
        var value = .5;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, state) => scopedApp(
                Builder(
                  builder: (context) => Theme(
                    data: nativeTheme(context, material3),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        valueIndicatorShape: material3
                            ? IndicatorText(paints)
                            : RectangularIndicatorText(paints, measured),
                        showValueIndicator: ShowValueIndicator.onDrag,
                      ),
                      child: SizedBox(
                        width: 430,
                        child: StarBridgeSlider(
                          controlKey: nativeKey,
                          semanticLabel: nativeName,
                          value: value,
                          divisions: 20,
                          valueLabel: (v) => '${(v * 100).round()}%',
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
          await visibilityFrames(t);
          final rect = t.getRect(find.byKey(nativeKey));
          final gesture = await t.startGesture(
            Offset(rect.center.dx, rect.center.dy),
            kind: ui.PointerDeviceKind.mouse,
          );
          await t.pump(const Duration(milliseconds: 300));
          await gesture.moveBy(const Offset(70, 0));
          await t.pump(const Duration(milliseconds: 200));
          expect(paints, isNotEmpty);
          expect(
            paints.every((text) => RegExp(r'^\d+%$').hasMatch(text)),
            isTrue,
          );
          expect(paints.last, '${(value * 100).round()}%');
          if (!material3) {
            // This SDK need not ask for preferred size while painting. Exercise
            // the actual wrapped public shape, with the native AX-name painter,
            // instead of asserting that the SDK chose that optional call path.
            final theme = SliderTheme.of(t.element(find.byKey(nativeKey)));
            final accessiblePainter = TextPainter(
              text: TextSpan(
                text: nativeName,
                style: theme.valueIndicatorTextStyle,
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            try {
              final shape = theme.valueIndicatorShape;
              expect(shape, isA<RectangularSliderValueIndicatorShape>());
              (shape! as RectangularSliderValueIndicatorShape).getPreferredSize(
                true,
                true,
                labelPainter: accessiblePainter,
                textScaleFactor: 1,
              );
            } finally {
              accessiblePainter.dispose();
            }
            expect(measured, isNotEmpty);
            expect(
              measured.every((text) => RegExp(r'^\d+%$').hasMatch(text)),
              isTrue,
            );
            expect(measured.last, '${(value * 100).round()}%');
          }
          expect(t.widget<Slider>(find.byKey(nativeKey)).label, nativeName);
          await gesture.up();
          await gesture.removePointer();
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets(
    '3fi native held pointer accepts one reader interruption then resumes pointer',
    (t) async {
      size(t, const Size(1000, 800));
      final semantics = t.ensureSemantics();
      var value = .4;
      final changes = <(double, InteractionSource)>[],
          endings = <(double, InteractionSource)>[];
      try {
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, state) => scopedApp(
              SizedBox(
                width: 430,
                child: StarBridgeSlider(
                  controlKey: nativeKey,
                  semanticLabel: nativeName,
                  value: value,
                  keyboardStep: .03,
                  onChanged: (v) {
                    changes.add((v, currentStarBridgeActivationSource));
                    state(() => value = v);
                  },
                  onChangeEnd: (v) =>
                      endings.add((v, currentStarBridgeActivationSource)),
                ),
              ),
              InteractionSuite.standard,
            ),
          ),
        );
        await visibilityFrames(t);
        final rect = t.getRect(find.byKey(nativeKey));
        final gesture = await t.startGesture(
          Offset(rect.left + 130, rect.center.dy),
        );
        await gesture.moveBy(const Offset(45, 0));
        await t.pump();
        final before = value;
        expect(changes.last.$2, InteractionSource.pointer);
        expect(endings, isEmpty);
        readerStep(t, ui.SemanticsAction.increase);
        await t.pump();
        await t.pump();
        expect(value, closeTo(before + .03, 1e-8));
        expect(changes.last, (value, InteractionSource.keyboard));
        expect(endings, [(value, InteractionSource.keyboard)]);
        await gesture.moveBy(const Offset(70, 0));
        await t.pump();
        expect(changes.last.$2, InteractionSource.pointer);
        await gesture.up();
        await t.pump();
        expect(endings, hasLength(2));
        expect(endings.last.$2, InteractionSource.pointer);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        semantics.dispose();
      }
    },
  );
}
