import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ck_test.dart' show Harness, HarnessState;
import 'interaction_batch3ck_controls_test.dart' show button, history, press;

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () =>
        (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3ck/$name.png');
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
      testWidgets(
        '$suite $config actual private panel native geometry, nested menu and history feedback review',
        (t) async {
          viewport(t, config);
          final boundary = GlobalKey(),
              host = GlobalKey<HarnessState>(),
              old = debugDisableShadows;
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
            await capture(t, boundary, '$name-directory');
            final search = find.byKey(const ValueKey('menu-comms-search'));
            await t.tap(search);
            await t.enterText(search, '白鸦');
            await t.pump();
            await t.pump(const Duration(milliseconds: 90));
            await capture(t, boundary, '$name-search-focus');
            await t.enterText(search, '');
            await frames(t);
            await press(t, 'pointer', '未读');
            await capture(t, boundary, '$name-filter');
            final avatar = find.byWidgetPredicate(
              (w) => w is MenuAvatarActions && w.name == '白鸦',
            );
            await t.tap(avatar);
            await frames(t);
            expect(find.text('查看个人页面'), findsOneWidget);
            await capture(t, boundary, '$name-avatar-open');
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await frames(t);
            expect(find.text('查看个人页面'), findsNothing);
            await capture(t, boundary, '$name-avatar-keyboard-return');
            h.change(() => h.view = history(count: 6));
            await frames(t);
            await capture(t, boundary, '$name-history');
            final older = button('较早消息');
            await t.ensureVisible(older);
            final rect = t.getRect(older);
            expect(rect.width, lessThanOrEqualTo(config.$1));
            expect(rect.height, lessThan(100));
            final gesture = await t.startGesture(rect.center);
            await t.pump();
            await t.pump(const Duration(milliseconds: 55));
            await capture(t, boundary, '$name-history-press');
            await gesture.up();
            await frames(t);
            h.change(
              () => h.view = history(notice: '消息刷新失败，当前显示上次内容。草稿已保留，请重新读取。'),
            );
            await frames(t);
            await capture(t, boundary, '$name-warning');
            h.change(() => h.reduce = true);
            await frames(t);
            await press(t, 'keyboard', '重新读取');
            await capture(t, boundary, '$name-reduced-keyboard');
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            debugDisableShadows = old;
          }
        },
      );
    }
  }
}
