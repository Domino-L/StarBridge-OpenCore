import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_game_pin.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_window.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_widget.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/menu_exec_hangar_game_overlay.dart';
import 'package:starbridge_flutter/platform/window/menu_desktop_widgets.dart';

import '../../app/menu_overlay/menu_exec_hangar_widget_test.dart'
    show SummaryPort;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3bw_test.dart' show frames;

typedef Request = ({
  String action,
  MenuExecHangarGamePosition? position,
  InteractionSource source,
  Completer<MenuExecHangarGameState> reply,
});

class Port extends SummaryPort implements MenuExecHangarGameOverlayPort {
  @override
  bool gameOverlayAvailable = true;
  bool holdRead = false;
  MenuExecHangarGameState state = const MenuExecHangarGameState(
    false,
    MenuExecHangarGamePosition.topLeft,
  );
  final requests = <Request>[];
  Future<MenuExecHangarGameState> request(
    String action, [
    MenuExecHangarGamePosition? position,
  ]) {
    final reply = Completer<MenuExecHangarGameState>();
    requests.add((
      action: action,
      position: position,
      source: captureStarBridgeActivationSource()(),
      reply: reply,
    ));
    if (action == 'read' && !holdRead) reply.complete(state);
    return reply.future;
  }

  @override
  Future<MenuExecHangarGameState> readGameOverlay() => request('read');
  @override
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  ) => request('pin', position);
  @override
  Future<MenuExecHangarGameState> unpinFromGame() => request('unpin');
}

class Harness extends StatefulWidget {
  const Harness(this.port, this.suite, {this.window = false, super.key});
  final Port port;
  final InteractionSuite suite;
  final bool window;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late Port port = widget.port;
  late InteractionSuite suite = widget.suite;
  bool active = true, reduce = false, light = false, visible = true;
  bool pinned = false;
  final pins = <bool>[], menuSources = <InteractionSource>[];
  int settings = 0;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    !visible
        ? const SizedBox()
        : widget.window
        ? MenuExecHangarWindow(
            port: port,
            active: active,
            pinned: pinned,
            onPinned: (value) {
              menuSources.add(captureStarBridgeActivationSource()());
              change(() {
                pins.add(value);
                pinned = value;
              });
            },
            onSettings: () {
              menuSources.add(captureStarBridgeActivationSource()());
              settings++;
            },
          )
        : SingleChildScrollView(
            child: MenuExecHangarGamePin(port: port, active: active),
          ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  Port port,
  InteractionSuite suite, {
  bool window = false,
}) async {
  size(t, const Size(900, 1100));
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(port, suite, window: window, key: key));
  await frames(t, 3);
  return key.currentState!;
}

Future<void> activate(WidgetTester t, String input, String id) =>
    fire(t, input, find.byKey(Key(id)));

InteractionData waitData(WidgetTester t) => InteractionScope.of(
  t.element(find.byKey(const Key('menu-hangar-game-pending'))),
);

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite failed unpin retains actual pin; reposition uses returned position',
      (t) async {
        final p = Port()
          ..state = const MenuExecHangarGameState(
            true,
            MenuExecHangarGamePosition.bottomLeft,
          );
        await mount(t, p, suite);
        await activate(t, 'pointer', 'menu-hangar-game-pin');
        expect(find.text('已固定到游戏 · 左下'), findsOneWidget);
        p.requests.last.reply.completeError(StateError('unpin unconfirmed'));
        await frames(t);
        expect(find.text('已固定到游戏 · 左下'), findsOneWidget);
        expect(find.text('未能确认游戏浮层状态，请重试。'), findsOneWidget);
        await activate(t, 'keyboard', 'menu-hangar-game-retry');
        await frames(t);
        expect(p.requests.map((r) => r.action), ['read', 'unpin', 'read']);
        await activate(t, 'pointer', 'menu-hangar-game-position');
        await activate(t, 'pointer', 'menu-hangar-game-topRight');
        await activate(t, 'pointer', 'menu-hangar-game-confirm');
        expect(p.requests.last.position, MenuExecHangarGamePosition.topRight);
        p.requests.last.reply.complete(
          const MenuExecHangarGameState(
            true,
            MenuExecHangarGamePosition.topLeft,
          ),
        );
        await frames(t);
        expect(find.text('已固定到游戏 · 左上'), findsOneWidget);
        expect(find.text('已固定到游戏 · 右上'), findsNothing);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard Space chooses and cancels without a native pin request',
      (t) async {
        final p = Port();
        await mount(t, p, suite);
        Future<void> space(String id) async {
          final target = find.byKey(Key(id));
          final text = find
              .descendant(of: target, matching: find.byType(Text))
              .first;
          Focus.of(t.element(text)).requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.space);
          await t.pump();
          await t.pump();
        }

        await space('menu-hangar-game-pin');
        await space('menu-hangar-game-bottomCenter');
        final chip = t.widget<StarBridgeChoiceChip>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('menu-hangar-game-bottomCenter')),
                matching: find.byType(StarBridgeChoiceChip),
              )
              .first,
        );
        expect(chip.selected, isTrue);
        await space('menu-hangar-game-cancel');
        expect(find.byKey(const Key('menu-hangar-game-confirm')), findsNothing);
        expect(p.requests.map((r) => r.action), ['read']);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );

    for (final input in ['pointer', 'keyboard', 'reader']) {
      final expected = input == 'pointer'
          ? InteractionSource.pointer
          : InteractionSource.keyboard;
      testWidgets(
        '$suite $input full actual window pin family preserves separate owners',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = Port();
          try {
            final state = await mount(t, p, suite, window: true);
            expect(p.requests.single.source, InteractionSource.programmatic);
            await activate(t, input, 'menu-hangar-pin');
            await activate(t, input, 'menu-hangar-pin');
            await activate(t, input, 'menu-hangar-settings');
            expect(state.pins, [true, false]);
            expect(state.settings, 1);
            expect(state.menuSources, everyElement(expected));
            expect(p.requests.length, 1);
            await activate(t, input, 'menu-hangar-game-pin');
            expect(find.byType(StarBridgeChoiceChip), findsNWidgets(6));
            for (final position in MenuExecHangarGamePosition.values) {
              await activate(t, input, 'menu-hangar-game-${position.name}');
              final chip = t.widget<StarBridgeChoiceChip>(
                find
                    .ancestor(
                      of: find.byKey(
                        ValueKey('menu-hangar-game-${position.name}'),
                      ),
                      matching: find.byType(StarBridgeChoiceChip),
                    )
                    .first,
              );
              expect(chip.selected, isTrue);
              expect(p.requests.length, 1);
            }
            await activate(t, input, 'menu-hangar-game-cancel');
            expect(
              find.byKey(const Key('menu-hangar-game-confirm')),
              findsNothing,
            );
            expect(p.requests.length, 1);
            await activate(t, input, 'menu-hangar-game-pin');
            await activate(t, input, 'menu-hangar-game-bottomCenter');
            await activate(t, input, 'menu-hangar-game-confirm');
            expect(p.requests.last.action, 'pin');
            expect(
              p.requests.last.position,
              MenuExecHangarGamePosition.bottomCenter,
            );
            expect(p.requests.last.source, expected);
            expect(waitData(t).reduceMotion, input != 'pointer');
            expect(find.text('正在确认游戏固定…'), findsOneWidget);
            expect(find.textContaining('已固定到游戏'), findsNothing);
            for (final button in t.widgetList<StarBridgeActionButton>(
              find.descendant(
                of: find.byType(MenuExecHangarGamePin),
                matching: find.byType(StarBridgeActionButton),
              ),
            )) {
              expect(button.onActivate, isNull);
            }
            p.requests.last.reply.complete(
              const MenuExecHangarGameState(
                true,
                MenuExecHangarGamePosition.bottomCenter,
              ),
            );
            await frames(t);
            expect(
              find.byKey(const Key('menu-hangar-game-pending')),
              findsNothing,
            );
            expect(find.text('已固定到游戏 · 中下'), findsOneWidget);
            await activate(t, input, 'menu-hangar-game-position');
            await activate(t, input, 'menu-hangar-game-cancel');
            expect(p.requests.length, 2);
            await activate(t, input, 'menu-hangar-game-pin');
            expect(p.requests.last.action, 'unpin');
            expect(p.requests.last.source, expected);
            expect(find.text('正在取消游戏固定…'), findsOneWidget);
            expect(find.text('已固定到游戏 · 中下'), findsOneWidget);
            p.requests.last.reply.complete(
              const MenuExecHangarGameState(
                false,
                MenuExecHangarGamePosition.bottomCenter,
              ),
            );
            await frames(t);
            expect(find.textContaining('已固定到游戏'), findsNothing);
            expect(state.pins, [true, false]);
            expect(state.settings, 1);
            expect(p.requests.map((r) => r.action), ['read', 'pin', 'unpin']);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );

      testWidgets(
        '$suite $input rejected pin never claims success; retry only rereads',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = Port();
          try {
            await mount(t, p, suite);
            await activate(t, input, 'menu-hangar-game-pin');
            await activate(t, input, 'menu-hangar-game-confirm');
            p.requests.last.reply.completeError(StateError('fixture refusal'));
            await frames(t);
            expect(find.text('未能确认游戏浮层状态，请重试。'), findsOneWidget);
            expect(
              find.byKey(const Key('menu-hangar-game-confirm')),
              findsOneWidget,
            );
            expect(find.textContaining('已固定到游戏'), findsNothing);
            expect(
              find.byKey(const Key('menu-hangar-game-pending')),
              findsNothing,
            );
            p.holdRead = true;
            await activate(t, input, 'menu-hangar-game-retry');
            expect(p.requests.map((r) => r.action), ['read', 'pin', 'read']);
            expect(p.requests.last.source, expected);
            expect(waitData(t).reduceMotion, input != 'pointer');
            expect(find.text('正在读取游戏浮层状态…'), findsOneWidget);
            p.requests.last.reply.complete(p.state);
            await frames(t);
            expect(
              find.byKey(const Key('menu-hangar-game-confirm')),
              findsNothing,
            );
            expect(find.textContaining('已固定到游戏'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }

    for (final late in ['success', 'failure']) {
      testWidgets(
        '$suite late $late A cannot clear B pointer wait after port replacement',
        (t) async {
          final a = Port(), b = Port()..holdRead = true;
          final h = await mount(t, a, suite);
          await activate(t, 'keyboard', 'menu-hangar-game-pin');
          await activate(t, 'keyboard', 'menu-hangar-game-confirm');
          final old = a.requests.last;
          h.change(() => h.port = b);
          await t.pump();
          await t.pump();
          expect(b.requests.single.source, InteractionSource.programmatic);
          expect(waitData(t).reduceMotion, isTrue);
          b.requests.single.reply.complete(b.state);
          await frames(t);
          await activate(t, 'pointer', 'menu-hangar-game-pin');
          await activate(t, 'pointer', 'menu-hangar-game-confirm');
          expect(waitData(t).reduceMotion, isFalse);
          if (late == 'success') {
            old.reply.complete(
              const MenuExecHangarGameState(
                true,
                MenuExecHangarGamePosition.bottomRight,
              ),
            );
          } else {
            old.reply.completeError(StateError('late A'));
          }
          await frames(t);
          expect(waitData(t).reduceMotion, isFalse);
          expect(find.text('正在确认游戏固定…'), findsOneWidget);
          expect(find.text('未能确认游戏浮层状态，请重试。'), findsNothing);
          expect(find.textContaining('已固定到游戏'), findsNothing);
          b.requests.last.reply.complete(
            const MenuExecHangarGameState(
              true,
              MenuExecHangarGamePosition.topLeft,
            ),
          );
          await frames(t);
          expect(find.text('已固定到游戏 · 左上'), findsOneWidget);
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }

    for (final exit in ['hide', 'dispose']) {
      testWidgets(
        '$suite $exit retires request and cannot publish late completion',
        (t) async {
          final p = Port();
          final h = await mount(t, p, suite);
          await activate(t, 'pointer', 'menu-hangar-game-pin');
          await activate(t, 'pointer', 'menu-hangar-game-confirm');
          final old = p.requests.last;
          h.change(() {
            if (exit == 'hide') {
              h.active = false;
            } else {
              h.visible = false;
            }
          });
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('menu-hangar-game-pending')),
            findsNothing,
          );
          old.reply.completeError(StateError('late after exit'));
          await frames(t);
          expect(find.text('未能确认游戏浮层状态，请重试。'), findsNothing);
          if (exit == 'hide') {
            p.holdRead = true;
            h.change(() => h.active = true);
            await t.pump();
            await t.pump();
            expect(p.requests.last.action, 'read');
            expect(p.requests.last.source, InteractionSource.programmatic);
            expect(waitData(t).reduceMotion, isTrue);
            p.requests.last.reply.complete(p.state);
            await frames(t);
          }
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite actual pending follows live reduce and suite; duplicate callbacks cannot relabel',
      (t) async {
        final p = Port();
        final h = await mount(t, p, suite);
        await activate(t, 'pointer', 'menu-hangar-game-pin');
        final confirm = t
            .widget<StarBridgeActionButton>(
              find
                  .ancestor(
                    of: find.byKey(const Key('menu-hangar-game-confirm')),
                    matching: find.byType(StarBridgeActionButton),
                  )
                  .first,
            )
            .onActivate!;
        confirm(InteractionSource.pointer);
        confirm(InteractionSource.keyboard);
        await t.pump();
        await t.pump();
        expect(p.requests.length, 2);
        expect(waitData(t).reduceMotion, isFalse);
        h.change(() {
          h.reduce = true;
          h.light = true;
          h.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(waitData(t).reduceMotion, isTrue);
        expect(waitData(t).suite, InteractionSuite.glow);
        expect(waitData(t).palette.brightness, Brightness.light);
        h.change(() => h.reduce = false);
        await t.pump();
        await t.pump();
        expect(waitData(t).reduceMotion, isFalse);
        p.requests.last.reply.complete(p.state);
        await frames(t);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite initial pending is static and capability gates original entry',
      (t) async {
        final p = Port()..holdRead = true;
        await mount(t, p, suite, window: true);
        expect(waitData(t).reduceMotion, isTrue);
        expect(p.requests.single.source, InteractionSource.programmatic);
        p.requests.single.reply.complete(p.state);
        await frames(t);
        await t.pumpWidget(const SizedBox());
        final disabled = Port()..gameOverlayAvailable = false;
        await mount(t, disabled, suite, window: true);
        expect(find.byType(MenuExecHangarGamePin), findsNothing);
        expect(disabled.requests, isEmpty);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          scopedApp(
            MenuExecHangarWindow(
              port: SummaryPort(),
              active: true,
              pinned: false,
            ),
            suite,
          ),
        );
        await frames(t);
        expect(find.byType(MenuExecHangarGamePin), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );

    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input editing remove is only original widget preference callback',
        (t) async {
          size(t, const Size(900, 600));
          final semantics = t.ensureSemantics();
          final calls = <(MenuDesktopWidgets, bool, InteractionSource)>[];
          final p = Port();
          try {
            await t.pumpWidget(
              scopedApp(
                MenuExecHangarWidget(
                  port: p,
                  preferences: const MenuDesktopWidgets(),
                  editing: true,
                  onOpen: () {},
                  onEdit: () {},
                  onChanged: (v, persist) => calls.add((
                    v,
                    persist,
                    captureStarBridgeActivationSource()(),
                  )),
                ),
                suite,
              ),
            );
            await frames(t);
            await activate(t, input, 'menu-hangar-remove');
            expect(calls.single.$1.hangar, isFalse);
            expect(calls.single.$2, isTrue);
            expect(
              calls.single.$3,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(p.requests, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }
}
