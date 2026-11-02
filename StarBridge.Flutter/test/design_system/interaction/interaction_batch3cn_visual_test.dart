import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_game_pin.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_window.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_inline_avatar.dart';
import 'package:starbridge_flutter/platform/window/menu_exec_hangar_game_overlay.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cn_test.dart' show Port, mount, activate;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ca_visual_test.dart' show viewport;

Future<Uint8List> pixels(WidgetTester t, Finder target) async {
  final image = (await t.runAsync(
    () => t.renderObject<RenderRepaintBoundary>(target).toImage(),
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

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  expect(t.takeException(), isNull);
  // ensureVisible during action/keyboard tests intentionally scrolls to the
  // target. Review the same top-of-window anatomy in each state instead of
  // accidentally photographing only the last chooser row or the schedule.
  final scroll = find
      .descendant(
        of: find.byKey(const Key('menu-hangar-window')),
        matching: find.byType(Scrollable),
      )
      .first;
  t.state<ScrollableState>(scroll).position.jumpTo(0);
  await t.pump();
  final data = await pixels(t, find.byKey(frame));
  final file = File('build/reviews/interaction-batch3cn/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source actual pending paints motion only for active pointer',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = Port();
          try {
            final h = await mount(t, p, suite);
            await activate(t, source, 'menu-hangar-game-pin');
            await activate(t, source, 'menu-hangar-game-confirm');
            final pending = find.byKey(const Key('menu-hangar-game-paint'));
            await t.pump(const Duration(milliseconds: 120));
            final first = await pixels(t, pending);
            await t.pump(const Duration(milliseconds: 320));
            final second = await pixels(t, pending);
            expect(
              second,
              source == 'pointer'
                  ? isNot(orderedEquals(first))
                  : orderedEquals(first),
            );
            h.change(() => h.reduce = true);
            await t.pump();
            await t.pump();
            final stopped = await pixels(t, pending);
            await t.pump(const Duration(milliseconds: 300));
            expect(await pixels(t, pending), orderedEquals(stopped));
            expect(find.byType(MenuExecHangarGamePin), findsOneWidget);
            p.requests.last.reply.complete(p.state);
            await frames(t);
            expect(pending, findsNothing);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite $config actual hangar chooser/pending/unknown/reconciled frames',
        (t) async {
          viewport(t, config);
          final p = Port()..holdRead = true;
          final reduce = ValueNotifier(false), frame = GlobalKey();
          final old = debugDisableShadows;
          debugDisableShadows = false;
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          try {
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: ValueListenableBuilder(
                  valueListenable: reduce,
                  builder: (_, value, _) => scopedApp(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              MenuInlineAvatar(name: '白鸦'),
                              MenuInlineAvatar(name: 'Warden'),
                              MenuInlineAvatar(name: 'e\u0301toile'),
                              MenuInlineAvatar(name: '👩🏽‍🚀 Pilot'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: MenuExecHangarWindow(
                            port: p,
                            active: true,
                            pinned: false,
                            onPinned: (_) {},
                            onSettings: () {},
                          ),
                        ),
                      ],
                    ),
                    suite,
                    reduce: value,
                    light: config.$1 > 1000,
                  ),
                ),
              ),
            );
            await frames(t, 3);
            await capture(t, frame, '$name-initial-static');
            p.requests.single.reply.complete(p.state);
            await frames(t);
            await activate(t, 'pointer', 'menu-hangar-game-pin');
            await activate(t, 'pointer', 'menu-hangar-game-bottomRight');
            await frames(t);
            await capture(t, frame, '$name-chooser');
            await activate(t, 'pointer', 'menu-hangar-game-confirm');
            await t.pump(const Duration(milliseconds: 120));
            await capture(t, frame, '$name-pending120');
            await t.pump(const Duration(milliseconds: 320));
            await capture(t, frame, '$name-pending440');
            reduce.value = true;
            await t.pump();
            await t.pump();
            await capture(t, frame, '$name-live-reduce');
            p.requests.last.reply.completeError(StateError('not confirmed'));
            await frames(t);
            await capture(t, frame, '$name-unconfirmed');
            await activate(t, 'keyboard', 'menu-hangar-game-retry');
            await capture(t, frame, '$name-reread-static');
            p.requests.last.reply.complete(
              const MenuExecHangarGameState(
                true,
                MenuExecHangarGamePosition.bottomRight,
              ),
            );
            await frames(t);
            await capture(t, frame, '$name-confirmed-by-read');
            expect(p.requests.map((r) => r.action), ['read', 'pin', 'read']);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t, 2);
            reduce.dispose();
            debugDisableShadows = old;
          }
        },
      );
    }
  }
}
