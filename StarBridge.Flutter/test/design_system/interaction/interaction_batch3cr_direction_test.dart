import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cr_render_test.dart' show sliderNode;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite RTL left end means the high logical value', (t) async {
      var value = .3;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 300,
                  child: StarBridgeSlider(
                    controlKey: const Key('rtl-slider'),
                    value: value,
                    onChanged: (v) => state(() => value = v),
                  ),
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(const Key('rtl-slider')));
      await t.tapAt(Offset(rect.left + 20, rect.center.dy));
      await t.pumpAndSettle();
      expect(value, greaterThan(.8));
      await t.pumpWidget(const SizedBox());
    });
    for (final rtl in [false, true]) {
      for (final divisions in [null, 100]) {
        testWidgets(
          '$suite rtl=$rtl divisions=$divisions pointer keyboard and reader share logical range',
          (t) async {
            final semantics = t.ensureSemantics();
            var value = .5;
            late StateSetter update;
            final sources = <InteractionSource>[];
            final ended = <double>[];
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, state) {
                  update = state;
                  return scopedApp(
                    Directionality(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Center(
                        child: SizedBox(
                          width: 300,
                          child: StarBridgeSlider(
                            controlKey: const Key('range'),
                            value: value,
                            min: .15,
                            divisions: divisions,
                            keyboardStep: .1,
                            onChanged: (v) {
                              sources.add(currentStarBridgeActivationSource);
                              state(() => value = v);
                            },
                            onChangeEnd: ended.add,
                          ),
                        ),
                      ),
                    ),
                    suite,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            final target = find.byKey(const Key('range'));
            final rect = t.getRect(target);
            await t.tapAt(Offset(rect.left + 10, rect.center.dy));
            await t.pumpAndSettle();
            expect(value, rtl ? greaterThan(.98) : lessThan(.17));
            expect(sources.last, InteractionSource.pointer);
            await t.tapAt(Offset(rect.right - 10, rect.center.dy));
            await t.pumpAndSettle();
            expect(value, rtl ? lessThan(.17) : greaterThan(.98));
            update(() => value = .5);
            await t.pumpAndSettle();
            final raw = t.widget(target);
            (raw is Slider ? raw.focusNode! : (raw as SuiteSlider).focusNode!)
                .requestFocus();
            await t.pump();
            for (final item in [
              (LogicalKeyboardKey.arrowRight, rtl ? -.1 : .1),
              (LogicalKeyboardKey.arrowLeft, rtl ? .1 : -.1),
              (LogicalKeyboardKey.arrowUp, .1),
              (LogicalKeyboardKey.arrowDown, -.1),
            ]) {
              final before = value;
              await t.sendKeyEvent(item.$1);
              await t.pump();
              expect(value, closeTo(before + item.$2, .000001));
              expect(ended.last, value);
              expect(sources.last, InteractionSource.keyboard);
            }
            await t.sendKeyEvent(LogicalKeyboardKey.home);
            await t.pump();
            expect(value, .15);
            await t.sendKeyEvent(LogicalKeyboardKey.end);
            await t.pump();
            expect(value, 1);
            final count = ended.length;
            await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await t.pump();
            expect(ended.length, count);
            final node = sliderNode(
              t.getSemantics(find.byType(StarBridgeSlider)),
            );
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              node.id,
              ui.SemanticsAction.decrease,
            );
            await t.pump();
            expect(value, closeTo(.9, .000001));
            expect(ended.last, value);
            expect(sources.last, InteractionSource.keyboard);
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
    testWidgets('$suite reader can commit after a real pointer cancellation', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      var value = .4;
      final ended = <double>[];
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, state) => scopedApp(
            Center(
              child: SizedBox(
                width: 300,
                child: StarBridgeSlider(
                  controlKey: const Key('cancel-reader'),
                  value: value,
                  onChanged: (v) => state(() => value = v),
                  onChangeEnd: ended.add,
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(const Key('cancel-reader'))),
      );
      await gesture.moveBy(const Offset(30, 0));
      await t.pump();
      await gesture.cancel();
      await t.pumpAndSettle();
      expect(ended, isEmpty);
      final before = value;
      final node = sliderNode(t.getSemantics(find.byType(StarBridgeSlider)));
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        ui.SemanticsAction.increase,
      );
      await t.pump();
      expect(value, closeTo(before + .05, .000001));
      expect(ended, [value]);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
