import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/game_log/game_log_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../../features/game_log/game_log_test.dart' show Harness;
import 'interaction_batch3bj_test.dart' show showPanel, close;
import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> remove(WidgetTester t, String source, String channel) async {
  if (source == 'keyboard') {
    Focus.of(t.element(find.text(channel == 'PTU' ? 'PTU 测试版' : channel)))
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
  } else if (source == 'pointer') {
    // InputChip still owns the native hit target beneath the accessibility
    // sibling. Drive the actual pointer coordinate, not a fake callback.
    await t.tapAt(t.getCenter(find.byKey(Key('game-log-remove-$channel'))));
  } else {
    await activate(t, source, Key('game-log-remove-$channel'));
  }
  await t.pump();
  await t.pump();
}

Future<void> invalidate(Harness h, String name) => h.pair.host.send(
  BridgeEnvelope(
    protocolVersion: 1,
    messageType: 'event',
    name: name,
    sessionGeneration: h.session.activeGeneration,
    sequence: 1,
    payload: const {'schemaVersion': 1},
  ),
);

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source input chip exposes independent labeled actions',
        (t) async {
          final selected = <InteractionSource>[],
              deleted = <InteractionSource>[];
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              scopedApp(
                Center(
                  child: StarBridgeChoiceChip.input(
                    label: 'PTU 测试版',
                    selected: false,
                    controlKey: const Key('game-log-version-PTU'),
                    deleteKey: const Key('game-log-remove-PTU'),
                    deleteLabel: '移除版本 · PTU',
                    onSelected: (_) =>
                        selected.add(currentStarBridgeActivationSource),
                    onDeleted: deleted.add,
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            expect(find.bySemanticsLabel('PTU 测试版'), findsOneWidget);
            expect(find.bySemanticsLabel('移除版本 · PTU'), findsOneWidget);
            await activate(t, source, const Key('game-log-version-PTU'));
            await remove(t, source, 'PTU');
            expect(selected, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            expect(deleted, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            expect(
              t
                  .widget<StarBridgeChoiceChip>(
                    find.byType(StarBridgeChoiceChip),
                  )
                  .selected,
              isFalse,
            );
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite input chip may disable selection without disabling removal',
      (t) async {
        var removed = 0;
        final semantics = t.ensureSemantics();
        try {
          await t.pumpWidget(
            scopedApp(
              Center(
                child: StarBridgeChoiceChip.input(
                  label: 'PTU 测试版',
                  selected: false,
                  controlKey: const Key('game-log-version-PTU'),
                  deleteKey: const Key('game-log-remove-PTU'),
                  deleteLabel: '移除版本 · PTU',
                  onDeleted: (_) => removed++,
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await remove(t, 'reader', 'PTU');
          expect(removed, 1);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '$suite version targets retain selection and removal via the approved module',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          expect(find.byType(StarBridgeChoiceChip), findsNWidgets(2));
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite logout retires an open version removal confirmation', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        t
            .widget<StarBridgeChoiceChip>(
              find.byKey(const ValueKey(('game-log-version', 'PTU'))),
            )
            .onDeleted!(InteractionSource.pointer);
        await t.pumpAndSettle();
        expect(find.text('移除 PTU？'), findsOneWidget);
        h.session.advanceGeneration(2);
        h.account.value = h.account.value.copyWith(
          generation: 2,
          sessionState: AccountSessionState.signedOut,
        );
        await t.pump();
        await t.pump();
        expect(find.text('移除 PTU？'), findsNothing);
        expect(
          h.requests.where((r) => r.name == 'gameLog.removeVersion'),
          isEmpty,
        );
      } finally {
        await close(t, h);
      }
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source selection waits and LIVE has no remove action',
        (t) async {
          final h = Harness();
          final semantics = t.ensureSemantics();
          try {
            await showPanel(t, h, suite);
            expect(find.byKey(const Key('game-log-remove-LIVE')), findsNothing);
            h.hold = true;
            await activate(t, source, const Key('game-log-version-PTU'));
            expect(h.held!.name, 'gameLog.configure');
            expect(h.held!.payload['channel'], 'PTU');
            expect(h.controller.value.channel, 'LIVE');
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            for (final chip in t.widgetList<StarBridgeChoiceChip>(
              find.byType(StarBridgeChoiceChip),
            )) {
              expect(chip.onSelected, isNull);
              expect(chip.onDeleted, isNull);
            }
            h.hold = false;
            h.respond(h.held!);
            await t.pump();
            await t.pumpAndSettle();
            expect(h.controller.value.channel, 'PTU');
            expect(
              t
                  .widget<StarBridgeChoiceChip>(
                    find.byKey(const ValueKey(('game-log-version', 'PTU'))),
                  )
                  .selected,
              isTrue,
            );
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
      for (final confirmation in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $source removal then $confirmation confirmation waits without deleting early',
          (t) async {
            final h = Harness();
            final semantics = t.ensureSemantics();
            try {
              await showPanel(t, h, suite);
              await remove(t, source, 'PTU');
              final route = ModalRoute.of(
                t.element(find.text('移除 PTU？')),
              ) as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              await t.pumpAndSettle();
              h.hold = true;
              await activate(
                t,
                confirmation,
                const Key('game-log-confirm-remove'),
              );
              await t.pump(const Duration(milliseconds: 400));
              expect(h.held!.name, 'gameLog.removeVersion');
              expect(h.held!.payload['channel'], 'PTU');
              expect(h.controller.value.channels, contains('PTU'));
              expect(h.controller.value.busy, isTrue);
              expect(
                InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                    .reduceMotion,
                confirmation != 'pointer',
              );
              h.hold = false;
              h.respond(h.held!);
              await t.pump();
              await t.pumpAndSettle();
              expect(h.controller.value.channels, isNot(contains('PTU')));
              if (confirmation != 'pointer') {
                final add = t.widget<StarBridgeActionButton>(
                  find.ancestor(
                    of: find.byKey(const Key('game-log-add-version')),
                    matching: find.byType(StarBridgeActionButton),
                  ),
                );
                expect(FocusManager.instance.primaryFocus, same(add.focusNode));
              }
              expect(
                h.requests.where((r) => r.name == 'gameLog.removeVersion'),
                hasLength(1),
              );
            } finally {
              await close(t, h);
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        '$suite $source cancellation preserves version and sends nothing',
        (t) async {
          final h = Harness();
          final semantics = t.ensureSemantics();
          try {
            await showPanel(t, h, suite);
            await remove(t, source, 'PTU');
            await t.pumpAndSettle();
            await activate(t, source, const Key('game-log-keep-version'));
            await t.pumpAndSettle();
            expect(find.text('移除 PTU？'), findsNothing);
            expect(h.controller.value.channels, contains('PTU'));
            expect(
              h.requests.where((r) => r.name == 'gameLog.removeVersion'),
              isEmpty,
            );
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite Escape closes a pointer-opened confirmation immediately',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.text('移除 PTU？'), findsNothing);
          expect(
            h.requests.where((r) => r.name == 'gameLog.removeVersion'),
            isEmpty,
          );
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite open confirmation follows live reduce and palette', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        await remove(t, 'pointer', 'PTU');
        await t.pump(const Duration(milliseconds: 50));
        await t.pumpWidget(
          scopedApp(
            SingleChildScrollView(
              child: GameLogPanel(controller: h.controller),
            ),
            suite,
            reduce: true,
            light: true,
          ),
        );
        await t.pump();
        await t.pump();
        final data = InteractionScope.of(t.element(find.text('移除 PTU？')));
        expect(data.reduceMotion, isTrue);
        expect(data.palette.brightness, Brightness.light);
        await activate(t, 'keyboard', const Key('game-log-keep-version'));
        await t.pumpAndSettle();
      } finally {
        await close(t, h);
      }
    });
    testWidgets('$suite replacing Controller retires the old confirmation', (
      t,
    ) async {
      final old = Harness(), next = Harness();
      try {
        await showPanel(t, old, suite);
        await remove(t, 'pointer', 'PTU');
        await t.pumpAndSettle();
        await showPanel(t, next, suite);
        expect(find.text('移除 PTU？'), findsNothing);
        expect(
          old.requests.where((r) => r.name == 'gameLog.removeVersion'),
          isEmpty,
        );
        expect(
          next.requests.where((r) => r.name == 'gameLog.removeVersion'),
          isEmpty,
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        await old.close(t);
        await next.close(t);
      }
    });
    testWidgets(
      '$suite late removal receipt after account change does not steal focus',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          h.hold = true;
          await activate(t, 'keyboard', const Key('game-log-confirm-remove'));
          final old = h.held!;
          h.hold = false;
          h.session.advanceGeneration(2);
          h.account.value = h.account.value.copyWith(generation: 2);
          await t.pump();
          await t.pumpAndSettle();
          final focus = Focus.of(t.element(find.text('LIVE 正式版')));
          focus.requestFocus();
          await t.pump();
          h.respond(old);
          await t.pump();
          await t.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(h.controller.value.channels, contains('PTU'));
        } finally {
          await close(t, h);
        }
      },
    );
    for (final event in ['account.changed', 'bootstrap.invalidated']) {
      testWidgets(
        '$suite $event invalidates confirmation in the same account generation',
        (t) async {
          final h = Harness();
          try {
            await showPanel(t, h, suite);
            await remove(t, 'pointer', 'PTU');
            await t.pumpAndSettle();
            await invalidate(h, event);
            await t.pump();
            await t.pumpAndSettle();
            expect(find.text('移除 PTU？'), findsNothing);
            expect(
              h.requests.where((r) => r.name == 'gameLog.removeVersion'),
              isEmpty,
            );
          } finally {
            await close(t, h);
          }
        },
      );
    }
    testWidgets(
      '$suite removal rejection preserves channel for explicit retry',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          h.error = 'gameLog.storage';
          await activate(t, 'keyboard', const Key('game-log-confirm-remove'));
          await t.pumpAndSettle();
          expect(h.controller.value.error, 'storage');
          expect(h.controller.value.channels, contains('PTU'));
          // The fixture mutates its simulated server before forming an error;
          // restore that server list, not the real controller's projection.
          h.channels.add('PTU');
          h.error = null;
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          await activate(t, 'pointer', const Key('game-log-confirm-remove'));
          await t.pumpAndSettle();
          expect(h.controller.value.channels, isNot(contains('PTU')));
          expect(
            h.requests.where((r) => r.name == 'gameLog.removeVersion'),
            hasLength(2),
          );
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets(
      '$suite changing generation ignores a saved stale confirmation callback',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          final stale = t
              .widget<StarBridgeActionButton>(
                find.ancestor(
                  of: find.byKey(const Key('game-log-confirm-remove')),
                  matching: find.byType(StarBridgeActionButton),
                ),
              )
              .onActivate!;
          h.session.advanceGeneration(2);
          h.account.value = h.account.value.copyWith(generation: 2);
          await t.pump();
          await t.pumpAndSettle();
          stale(InteractionSource.keyboard);
          await t.pump();
          expect(find.text('移除 PTU？'), findsNothing);
          expect(
            h.requests.where((r) => r.name == 'gameLog.removeVersion'),
            isEmpty,
          );
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets(
      '$suite leaving retires only the owned confirmation, not a newer dialog',
      (t) async {
        final h = Harness();
        final visibility = ValueNotifier(true);
        BuildContext? rootContext;
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) {
                  rootContext = context;
                  return ValueListenableBuilder<bool>(
                    valueListenable: visibility,
                    builder: (_, visible, _) => visible
                        ? GameLogPanel(controller: h.controller)
                        : const Text('left'),
                  );
                },
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await remove(t, 'pointer', 'PTU');
          await t.pumpAndSettle();
          unawaited(
            showStarBridgeDialog<void>(
              rootContext!,
              builder: (_) => const AlertDialog(content: Text('newer dialog')),
            ),
          );
          await t.pumpAndSettle();
          visibility.value = false;
          await t.pump();
          await t.pump();
          expect(find.text('newer dialog'), findsOneWidget);
          expect(find.text('移除 PTU？'), findsNothing);
          expect(
            h.requests.where((r) => r.name == 'gameLog.removeVersion'),
            isEmpty,
          );
        } finally {
          await close(t, h);
          visibility.dispose();
        }
      },
    );
  }
}
