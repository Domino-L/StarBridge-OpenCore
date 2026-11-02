import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cl_test.dart'
    show Harness, HarnessState, draftField, projection;

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () => (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary)
        .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3cl/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets('$suite $config composer review', (t) async {
        viewport(t, config);
        final boundary = GlobalKey(), host = GlobalKey<HarnessState>();
        final old = debugDisableShadows;
        debugDisableShadows = false;
        final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
        try {
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: Harness(suite, key: host),
            ),
          );
          final h = host.currentState!;
          h.change(() => h.light = config.$1 > 1000);
          await frames(t);
          await t.enterText(draftField, '星海舰桥 · 准备出发\n保留输入与发送状态');
          await t.pump();
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, boundary, '$name-focused');
          final send = find.byKey(const ValueKey('menu-message-send'));
          await t.ensureVisible(send);
          final fieldRect = t.getRect(draftField), sendRect = t.getRect(send);
          expect(sendRect.right, closeTo(fieldRect.right, 1));
          expect(sendRect.height, lessThan(110));
          final gesture = await t.startGesture(sendRect.center);
          await t.pump();
          await t.pump(const Duration(milliseconds: 55));
          await capture(t, boundary, '$name-press');
          await gesture.up();
          await t.pump();
          h.change(
            () => h.view = projection(
              draft: '星海舰桥 · 准备出发\n保留输入与发送状态',
              revision: 2,
              delivery: 'sending',
              locked: true,
              canSend: false,
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 180));
          await capture(t, boundary, '$name-sending');
          h.change(() => h.reduce = true);
          await t.pump();
          await t.pump();
          await capture(t, boundary, '$name-static-wait');
          h.change(
            () => h.view = projection(
              draft: '星海舰桥 · 准备出发\n保留输入与发送状态',
              revision: 3,
              delivery: 'unknown',
              locked: true,
              canSend: false,
            ),
          );
          await frames(t);
          await capture(t, boundary, '$name-unknown');
          h.change(
            () => h.view = projection(
              draft: '星海舰桥 · 准备出发\n保留输入与发送状态',
              revision: 4,
              delivery: 'rejected',
            ),
          );
          await frames(t);
          await capture(t, boundary, '$name-rejected');
          h.change(() => h.disconnected = true);
          await frames(t);
          await capture(t, boundary, '$name-disconnected');
          h.change(() {
            h.disconnected = false;
            h.view = projection(revision: 5, delivery: 'sent');
          });
          await frames(t);
          await capture(t, boundary, '$name-sent');
        } finally {
          await t.pumpWidget(const SizedBox());
          await frames(t);
          debugDisableShadows = old;
        }
      });
    }
  }
}
