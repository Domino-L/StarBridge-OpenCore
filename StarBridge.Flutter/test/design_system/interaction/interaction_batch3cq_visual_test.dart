import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_controls.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../app/menu_overlay/menu_reference_crop_test.dart' as image;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cq_support.dart';

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite $platform text$scale toolbar retains native target',
          (t) async {
            const icon = StandardIcon(StandardIconSemantic.add, size: 16);
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => Theme(
                    data: Theme.of(context).copyWith(
                      platform: platform,
                      visualDensity: VisualDensity.defaultDensityForPlatform(
                        platform,
                      ),
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: Column(
                        children: [
                          OutlinedButton.icon(
                            key: const Key('original'),
                            onPressed: () {},
                            icon: icon,
                            label: const Text('放大'),
                          ),
                          MenuImageAction(
                            title: '放大',
                            icon: icon,
                            action: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            if (platform == TargetPlatform.windows && scale == 1) {
              for (final label in find.text('放大').evaluate()) {
                final style = DefaultTextStyle.of(label).style;
                debugPrint('3cq $suite label style=$style');
              }
            }
            expect(
              t.getSize(find.byType(MenuImageAction)),
              t.getSize(find.byKey(const Key('original'))),
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual pending image feedback is static for $input and live reduce',
        (t) async {
          size(t, const Size(900, 900));
          final semantics = t.ensureSemantics();
          final png = await image.pixels(t), reply = Completer<Object?>();
          final tools = owner(png, (_, _) => reply.future, capture: true);
          final h = GlobalKey<ImageHarnessState>(), frame = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: ImageHarness(tools, suite, capture: true, key: h),
            ),
          );
          await cache(t, png);
          await fire(t, '另存为', input);
          await t.pump(const Duration(milliseconds: 30));
          final before = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 110));
          expect(
            await pixels(t, find.byKey(frame)),
            input == 'pointer'
                ? isNot(orderedEquals(before))
                : orderedEquals(before),
          );
          h.currentState!.change(() => h.currentState!.reduce = true);
          await frames(t);
          final stopped = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 120));
          expect(await pixels(t, find.byKey(frame)), orderedEquals(stopped));
          reply.complete(false);
          await frames(t);
          await t.pumpWidget(const SizedBox());
          tools.dispose();
          semantics.dispose();
        },
      );
    }
    for (final capture in [false, true]) {
      for (final config in [(900.0, 1.0), (344.0, 2.0), (392.0, 1.0)]) {
        testWidgets('$suite capture=$capture $config actual image review', (
          t,
        ) async {
          size(t, Size(config.$1, 700));
          final png = await image.pixels(t), reply = Completer<Object?>();
          final tools = owner(
            png,
            (name, _) => name == 'image' || name == 'save'
                ? reply.future
                : Future<Object?>.value(false),
            capture: capture,
          );
          final h = GlobalKey<ImageHarnessState>(), frame = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQueryData(
                    size: Size(config.$1, 700),
                    textScaler: TextScaler.linear(config.$2),
                  ),
                  child: ImageHarness(tools, suite, capture: capture, key: h),
                ),
              ),
            ),
          );
          h.currentState!.change(
            () => h.currentState!.light = config.$1 == 900,
          );
          await cache(t, png);
          Future<void> shot(String state) async {
            final file = File(
              'build/reviews/interaction-batch3cq/${suite.name}-'
              '${capture ? 'shot' : 'reference'}-${config.$1.toInt()}-${config.$2}-$state.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(await pixels(t, find.byKey(frame)));
            expect(t.takeException(), isNull);
          }

          await shot('idle');
          await fire(t, capture ? '另存为' : '选择图片', 'pointer');
          await t.pump(const Duration(milliseconds: 70));
          await shot('pending');
          reply.completeError(StateError('synthetic image failure'));
          await frames(t);
          await shot('failed');
          await fire(t, '裁剪', 'pointer');
          await t.pump(const Duration(milliseconds: 70));
          await shot('crop');
          await t.pumpWidget(const SizedBox());
          tools.dispose();
        });
      }
    }
  }
}
