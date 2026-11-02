import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ci_test.dart' show friends;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
        .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3ci/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite bottom-edge actual history popup render', (t) async {
      await loadFonts();
      size(t, const Size(900, 740));
      final boundary = GlobalKey(), old = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: scopedApp(
              MenuCommsHistory(
                view: MenuCommsView(
                  'ready',
                  name: 'Peer',
                  profileKey: 'c1',
                  messages: [
                    (
                      incoming: false,
                      text: 'Own message',
                      time: DateTime.utc(2026),
                      attachment: false,
                    ),
                  ],
                ),
                active: false,
                onAction: (_, _) {},
                onProfile: (_) {},
              ),
              suite,
            ),
          ),
        );
        await frames(t);
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is MenuAvatarActions && w.name == '我',
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        await capture(t, boundary, '${suite.name}-bottom-enter');
        await frames(t);
        final rect = t.getRect(find.text('查看个人页面'));
        expect(rect.top, greaterThanOrEqualTo(8));
        expect(rect.bottom, lessThanOrEqualTo(732));
        expect(
          t
              .widget<SuiteSurfaceTransition>(
                find.byType(SuiteSurfaceTransition),
              )
              .alignment
              .y,
          1,
        );
        await capture(t, boundary, '${suite.name}-bottom-open');
      } finally {
        await t.pumpWidget(const SizedBox());
        await frames(t);
        debugDisableShadows = old;
      }
    });
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite $config actual friends popup geometry and exit review',
        (t) async {
          await loadFonts();
          viewport(t, config);
          final old = debugDisableShadows;
          debugDisableShadows = false;
          final boundary = GlobalKey(), view = ValueNotifier(friends());
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          final calls = <String>[];
          try {
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: scopedApp(
                  Center(
                    child: SizedBox(
                      width: 340,
                      child: ValueListenableBuilder<MenuFriendsView>(
                        valueListenable: view,
                        builder: (_, v, _) => MenuFriendsPanel(
                          view: v,
                          onClose: () {},
                          onProfile: (k) => calls.add(k),
                          onChat: (k) => calls.add(k),
                          onAction: (a, k, v) => calls.add(a),
                        ),
                      ),
                    ),
                  ),
                  suite,
                  light: config.$1 > 1000,
                ),
              ),
            );
            await frames(t);
            await capture(t, boundary, '$name-ready');
            final avatar = find.byKey(const ValueKey('f1'));
            expect(t.getSize(avatar).width, lessThanOrEqualTo(40));
            await t.ensureVisible(avatar);
            await t.tap(avatar);
            await t.pump();
            await t.pump(const Duration(milliseconds: 80));
            await capture(t, boundary, '$name-enter');
            await frames(t);
            final remove = find.byKey(const ValueKey('friend-remove-f1'));
            await t.ensureVisible(remove);
            await t.pump();
            final rect = t.getRect(remove);
            expect(rect.left, greaterThanOrEqualTo(8));
            expect(rect.right, lessThanOrEqualTo(config.$1 - 8));
            expect(rect.top, greaterThanOrEqualTo(8));
            expect(rect.bottom, lessThanOrEqualTo(992));
            final mouse = await t.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(rect.center);
            await frames(t);
            await capture(t, boundary, '$name-hover');
            await mouse.removePointer();
            await t.tapAt(Offset(config.$1 - 2, 2));
            await t.pump();
            await t.pump(const Duration(milliseconds: 30));
            if (suite != InteractionSuite.standard) {
              expect(remove, findsOneWidget);
            }
            await capture(t, boundary, '$name-exit');
            await frames(t);
            expect(remove, findsNothing);
            expect(calls, isEmpty);
            view.value = friends(busy: true);
            await frames(t);
            await t.tap(avatar);
            await frames(t);
            expect(remove, findsNothing);
            expect(find.text('发消息'), findsOneWidget);
            await capture(t, boundary, '$name-busy');
            await t.pumpWidget(const SizedBox());
            await frames(t);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            view.dispose();
            debugDisableShadows = old;
          }
        },
      );
    }
  }
}
