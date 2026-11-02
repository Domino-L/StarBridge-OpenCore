import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/shell/widgets/window_controls.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_caption_action.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_app_test.dart' show snapshot;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3co_test.dart'
    show Chrome, caption, activate, Harness, HarnessState;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_visual_test.dart' show viewport;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      testWidgets(
        '$suite $light exact close hover pixels match original native',
        (t) async {
          final h = GlobalKey<HarnessState>();
          await t.pumpWidget(Harness(suite, (_) {}, key: h));
          h.currentState!.change(() {
            h.currentState!.reduce = true;
            h.currentState!.light = light;
          });
          await t.pumpAndSettle();
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(500, 500));
          await mouse.moveTo(t.getCenter(caption('caption')));
          await t.pumpAndSettle();
          final adapted = await pixels(
            t,
            find.byKey(const Key('caption-pixels')),
          );
          await mouse.moveTo(
            t.getCenter(find.byKey(const Key('native-reference'))),
          );
          await t.pumpAndSettle();
          expect(
            await pixels(t, find.byKey(const Key('reference-pixels'))),
            orderedEquals(adapted),
          );
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final input in ['keyboard', 'reader']) {
      testWidgets(
        '$suite pointer interrupted by $input leaves no native or suite ink',
        (t) async {
          await t.pumpWidget(Harness(suite, (_) {}));
          await t.pumpAndSettle();
          await activate(t, caption('caption'), 'pointer');
          await t.pump(const Duration(milliseconds: 20));
          await activate(t, caption('caption'), input);
          await t.pump();
          await t.pump();
          final a = await pixels(t, find.byKey(const Key('caption-pixels')));
          await t.pump(const Duration(milliseconds: 100));
          expect(
            await pixels(t, find.byKey(const Key('caption-pixels'))),
            orderedEquals(a),
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source caption actual pixel motion/static and live reduce',
        (t) async {
          final frame = GlobalKey(), h = GlobalKey<HarnessState>();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: Harness(suite, (_) {}, key: h),
            ),
          );
          await t.pumpAndSettle();
          await activate(t, caption('caption'), source);
          await t.pump(const Duration(milliseconds: 40));
          final a = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 100));
          final b = await pixels(t, find.byKey(frame));
          expect(
            b,
            source == 'pointer' ? isNot(orderedEquals(a)) : orderedEquals(a),
          );
          h.currentState!.change(() => h.currentState!.reduce = true);
          await t.pump();
          await t.pump();
          final stopped = await pixels(t, find.byKey(frame));
          await t.pump(const Duration(milliseconds: 100));
          expect(await pixels(t, find.byKey(frame)), orderedEquals(stopped));
          // Static hover preserves the caller's exact close red, not suite blue.
          final adapted = t.widget<IconButton>(
            find.descendant(
              of: caption('caption'),
              matching: find.byType(IconButton),
            ),
          );
          expect(
            adapted.style!.backgroundColor!.resolve({WidgetState.hovered}),
            HarnessState.style.overlayColor!.resolve({WidgetState.hovered}),
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final config in [(392.0, 1.0), (344.0, 2.0)]) {
      for (final surface in ['friends', 'social', 'main']) {
        testWidgets('$suite $config $surface full caption review', (t) async {
          viewport(t, config);
          final channel = const MethodChannel('starbridge/friends-surface');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'ready'
                ? {
                    ...snapshot(),
                    'presentation': {
                      'interactionStyle': suite.name,
                      'appearanceMode': config.$2 == 2 ? 'light' : 'dark',
                    },
                  }
                : true,
          );
          final frame = GlobalKey();
          final chrome = Chrome();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: switch (surface) {
                'friends' => const FriendsWindowApp(),
                'social' => scopedApp(
                  SocialWindowFrame(
                    title: '聊天',
                    control: (_) {},
                    child: const Center(child: Text('原消息内容区域')),
                  ),
                  suite,
                  light: config.$2 == 2,
                ),
                _ => scopedApp(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      WindowControls(windowChrome: chrome),
                      const Expanded(child: Center(child: Text('原客户端内容区域'))),
                    ],
                  ),
                  suite,
                  light: config.$2 == 2,
                ),
              },
            ),
          );
          await t.pumpAndSettle();
          final captions = find.byType(StarBridgeCaptionAction);
          expect(captions, findsNWidgets(3));
          for (var i = 0; i < 3; i++) {
            final rect = t.getRect(captions.at(i));
            expect(rect.right, lessThanOrEqualTo(config.$1));
            if (surface != 'main') expect(rect.size, const Size(44, 34));
          }
          Future<void> shot(String state) async {
            final bytes = await pixels(t, find.byKey(frame));
            final file = File(
              'build/reviews/interaction-batch3co/'
              '${suite.name}-$surface-${config.$1.toInt()}-${config.$2}-$state.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes);
            expect(t.takeException(), isNull);
          }

          await shot('idle');
          await t.tap(captions.last);
          await t.pump();
          await t.pump(const Duration(milliseconds: 70));
          await shot('press');
          await t.pumpWidget(const SizedBox());
          messenger.setMockMethodCallHandler(channel, null);
          chrome.maximized.dispose();
        });
      }
    }
  }
}
