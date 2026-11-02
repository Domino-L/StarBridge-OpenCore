import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../app/menu_overlay/menu_reference_crop_test.dart' show pixels;
import 'interaction_batch3cq_support.dart';

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in [
        'success',
        'cancel',
        'fail',
        'dispose',
        'rebound',
      ]) {
        testWidgets(
          '$suite $input actual screenshot save gates/maps/receipt $outcome',
          (t) async {
            size(t, const Size(900, 900));
            final semantics = t.ensureSemantics();
            final png = await pixels(t), reply = Completer<Object?>();
            final calls = <(String, Map<String, Object?>)>[];
            final tools = owner(png, (name, args) {
              calls.add((name, args));
              return reply.future;
            }, capture: true);
            final fresh = owner(png, (_, _) async => false, capture: true);
            final h = GlobalKey<ImageHarnessState>();
            await t.pumpWidget(
              ImageHarness(tools, suite, capture: true, key: h),
            );
            await cache(t, png);
            await fire(t, '另存为', input);
            expect(calls.single.$1, 'save');
            expect(calls.single.$2, {
              ...const MenuImageEdit().toMap(),
              'export': {'format': 'png', 'jpegQuality': 90},
            });
            expect(tools.screenshotNoticeKey, isEmpty);
            expect(tools.busy, isTrue);
            expect(
              t.widget<MenuImageBusy>(find.byType(MenuImageBusy)).source,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await t.tap(action('另存为'));
            await frames(t);
            expect(calls.length, 1);
            if (outcome == 'dispose') {
              await t.pumpWidget(const SizedBox());
              tools.dispose();
            } else if (outcome == 'rebound') {
              h.currentState!.change(() => h.currentState!.tools = fresh);
              await frames(t);
            }
            if (outcome == 'fail') {
              reply.completeError(PlatformException(code: 'synthetic'));
            } else {
              reply.complete(outcome != 'cancel');
            }
            await frames(t);
            expect(
              tools.screenshotNoticeKey,
              outcome == 'dispose'
                  ? ''
                  : outcome == 'fail'
                  ? 'saveFailed'
                  : outcome == 'cancel'
                  ? 'cancelled'
                  : 'exported',
            );
            if (outcome == 'rebound') {
              expect(fresh.screenshotNoticeKey, isEmpty);
              expect(fresh.busy, isFalse);
              expect(find.byType(MenuImageBusy), findsNothing);
            }
            expect(calls.length, 1);
            await t.pumpWidget(const SizedBox());
            if (!tools.closed) tools.dispose();
            fresh.dispose();
            semantics.dispose();
          },
        );
      }
      testWidgets(
        '$suite $input local image actions retain selection and no phantom writes',
        (t) async {
          size(t, const Size(900, 900));
          final semantics = t.ensureSemantics();
          final png = await pixels(t);
          final calls = <(String, Map<String, Object?>)>[];
          final tools = owner(png, (name, args) async {
            calls.add((name, args));
            return png;
          });
          await t.pumpWidget(ImageHarness(tools, suite));
          await cache(t, png);
          await fire(t, '放大', input);
          expect(
            tools.referenceTransform.value.getMaxScaleOnAxis(),
            closeTo(1.25, .001),
          );
          await fire(t, '缩小', input);
          expect(
            tools.referenceTransform.value.getMaxScaleOnAxis(),
            closeTo(1, .001),
          );
          await fire(t, '旋转', input);
          expect(tools.referenceTurns, 1);
          await fire(t, '适合窗口', input);
          expect(tools.referenceScaleMode, 'fit');
          expect(calls, isEmpty);
          await fire(t, '裁剪', input);
          final label = find.descendant(
            of: action('取消裁剪'),
            matching: find.text('取消裁剪'),
          );
          expect(
            DefaultTextStyle.of(t.element(label)).style.color,
            BridgeInk.blue,
          );
          await fire(t, '取消裁剪', input);
          expect(calls, isEmpty);
          await fire(t, '清除预览', input);
          expect(calls.single.$1, 'imageClear');
          expect(calls.single.$2, <String, Object?>{});
          expect(tools.reference, isNull);
          await t.pumpWidget(const SizedBox());
          tools.dispose();
          semantics.dispose();
        },
      );
    }
  }
}
