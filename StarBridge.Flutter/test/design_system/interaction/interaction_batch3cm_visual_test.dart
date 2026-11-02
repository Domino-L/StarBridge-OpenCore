import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/platform/window/menu_read_feedback.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;

Future<Uint8List> pixels(WidgetTester t, GlobalKey boundary) async {
  final image = (await t.runAsync(
    () => (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
        .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  expect(t.takeException(), isNull);
  final data = await pixels(t, boundary);
  final file = File('build/reviews/interaction-batch3cm/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final origin in MenuReadOrigin.values) {
      testWidgets(
        '$suite $origin slim paint moves only for a real pointer request',
        (t) async {
          size(t, const Size(600, 120));
          final boundary = GlobalKey();
          await t.pumpWidget(
            scopedApp(
              RepaintBoundary(
                key: boundary,
                child: MenuLoading(feedback: MenuReadFeedback(1, origin)),
              ),
              suite,
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 120));
          final first = await pixels(t, boundary);
          await t.pump(const Duration(milliseconds: 320));
          final second = await pixels(t, boundary);
          expect(
            second,
            origin == MenuReadOrigin.pointer
                ? isNot(orderedEquals(first))
                : orderedEquals(first),
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite $config real history read wait visual review', (
        t,
      ) async {
        viewport(t, config);
        final boundary = GlobalKey();
        final view = ValueNotifier(
          MenuCommsView(
            'ready',
            name: '白鸦',
            profileKey: 'c1',
            refreshing: true,
            readFeedback: MenuReadFeedback(1, MenuReadOrigin.pointer),
            messages: [
              (
                incoming: true,
                text: '读取时保留历史内容和草稿入口',
                time: DateTime.utc(2026),
                attachment: false,
              ),
            ],
          ),
        );
        final reduce = ValueNotifier(false);
        final old = debugDisableShadows;
        debugDisableShadows = false;
        final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
        try {
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ValueListenableBuilder(
                valueListenable: reduce,
                builder: (_, value, _) => scopedApp(
                  ValueListenableBuilder(
                    valueListenable: view,
                    builder: (_, raw, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: MenuCommsHistory(
                        view: raw,
                        active: false,
                        onAction: (_, _) {},
                      ),
                    ),
                  ),
                  suite,
                  reduce: value,
                  light: config.$1 > 1000,
                ),
              ),
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 120));
          await capture(t, boundary, '$name-reading120');
          await t.pump(const Duration(milliseconds: 320));
          await capture(t, boundary, '$name-reading440');
          reduce.value = true;
          await t.pump();
          await t.pump();
          await capture(t, boundary, '$name-live-reduce');
          view.value = MenuCommsView(
            'ready',
            name: '白鸦',
            profileKey: 'c1',
            messages: view.value.messages,
            notice: '消息刷新失败，当前显示上次内容。草稿已保留，请重新读取。',
          );
          await frames(t);
          await capture(t, boundary, '$name-failure');
        } finally {
          await t.pumpWidget(const SizedBox());
          await frames(t);
          view.dispose();
          reduce.dispose();
          debugDisableShadows = old;
        }
      });
    }
  }
}
