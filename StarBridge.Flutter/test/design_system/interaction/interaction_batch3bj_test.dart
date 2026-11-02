import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/game_log/game_log_panel.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';

import '../../features/game_log/game_log_test.dart' show Harness;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bg_test.dart' show activate;

Future<void> showPanel(
  WidgetTester t,
  Harness h,
  InteractionSuite suite, {
  Future<String?> Function()? picker,
  bool reduce = false,
}) async {
  await t.pumpWidget(
    scopedApp(
      SingleChildScrollView(
        child: GameLogPanel(
          controller: h.controller,
          pickLog: picker ?? () async => null,
        ),
      ),
      suite,
      reduce: reduce,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> close(WidgetTester t, Harness h) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  await h.close(t);
}

Future<void> input(WidgetTester t, String source, String id) async {
  final key = Key('game-log-$id');
  await t.ensureVisible(find.byKey(key));
  await t.pump();
  await activate(t, source, key);
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite log actions use the approved feedback module', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        expect(find.byType(StarBridgeActionButton), findsNWidgets(5));
      } finally {
        await close(t, h);
      }
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final command in ['find', 'retry', 'resume', 'stop']) {
        testWidgets('$suite $source $command waits for the real receipt', (
          t,
        ) async {
          final h = Harness()..enabled = command == 'stop';
          final semantics = t.ensureSemantics();
          try {
            await showPanel(t, h, suite);
            final before = h.controller.value;
            h.hold = true;
            await input(t, source, command);
            expect(h.held!.name, 'gameLog.$command');
            expect(h.held!.accountContext, isNotNull);
            expect(h.controller.value.busy, isTrue);
            expect(h.controller.value.enabled, before.enabled);
            expect(h.controller.value.state, before.state);
            expect(find.byType(SuiteProgressBar), findsOneWidget);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            for (final button in t.widgetList<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            )) {
              expect(button.onActivate, isNull);
            }
            h.hold = false;
            h.respond(h.held!);
            await t.pump();
            await t.pumpAndSettle();
            expect(h.controller.value.busy, isFalse);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(
              h.requests.where((r) => r.name == 'gameLog.$command'),
              hasLength(1),
            );
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        });
      }
      for (final command in ['select', 'add-version']) {
        testWidgets(
          '$suite $source $command keeps picker cancellation and failure',
          (t) async {
            final h = Harness();
            final semantics = t.ensureSemantics();
            var picker = Completer<String?>();
            try {
              await showPanel(t, h, suite, picker: () => picker.future);
              await input(t, source, command);
              expect(h.controller.value.busy, isTrue);
              expect(
                InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                    .reduceMotion,
                source != 'pointer',
              );
              picker.complete(null);
              await t.pump();
              await t.pumpAndSettle();
              expect(
                h.requests.where(
                  (r) =>
                      r.name == 'gameLog.select' ||
                      r.name == 'gameLog.addVersion',
                ),
                isEmpty,
              );
              expect(h.controller.value.channel, 'LIVE');
              picker = Completer<String?>();
              await input(t, source, command);
              picker.completeError(StateError('synthetic picker failure'));
              await t.pump();
              await t.pumpAndSettle();
              expect(h.controller.value.error, 'picker');
              expect(h.controller.value.busy, isFalse);
            } finally {
              await close(t, h);
              semantics.dispose();
            }
          },
        );
        testWidgets(
          '$suite $source $command preserves original picker payload',
          (t) async {
            final h = Harness();
            final semantics = t.ensureSemantics();
            try {
              await showPanel(
                t,
                h,
                suite,
                picker: () async => 'C:/synthetic/HOTFIX/Game.log',
              );
              await input(t, source, command);
              await t.pumpAndSettle();
              final request = h.requests.singleWhere(
                (r) =>
                    r.name ==
                    (command == 'select'
                        ? 'gameLog.select'
                        : 'gameLog.addVersion'),
              );
              expect(request.payload['path'], 'C:/synthetic/HOTFIX/Game.log');
              expect(request.accountContext, isNotNull);
              expect(h.controller.value.busy, isFalse);
              expect(find.byType(SelectableText), findsOneWidget);
            } finally {
              await close(t, h);
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets('$suite failure persists until retry; clicks are not merged', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        h.error = 'gameLog.notFound';
        await input(t, 'pointer', 'find');
        await t.pumpAndSettle();
        expect(h.controller.value.error, 'notFound');
        h.error = null;
        await t.pump(const Duration(seconds: 3));
        await t.pumpAndSettle();
        expect(h.controller.value.error, 'notFound');
        for (var i = 0; i < 4; i++) {
          await input(t, 'pointer', 'retry');
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pumpAndSettle();
        expect(h.controller.value.error, isNull);
        expect(
          h.requests.where((r) => r.name == 'gameLog.retry'),
          hasLength(4),
        );
      } finally {
        await close(t, h);
      }
    });
    testWidgets(
      '$suite live reduce stops a held wait and resumes when allowed',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          h.hold = true;
          await input(t, 'pointer', 'find');
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: GameLogPanel(controller: h.controller),
              ),
              suite,
              reduce: true,
            ),
          );
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          await t.pump(const Duration(seconds: 1));
          await t.pump();
          expect(t.binding.hasScheduledFrame, isFalse);
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: GameLogPanel(controller: h.controller),
              ),
              suite,
            ),
          );
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isFalse,
          );
          h.hold = false;
          h.respond(h.held!);
          await t.pump();
          await t.pumpAndSettle();
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite keyboard opening gives a static initial wait', (
      t,
    ) async {
      final h = Harness()..hold = true;
      try {
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: const Key('open-log'),
                onActivate: (source) => unawaited(
                  showStarBridgeDialog<void>(
                    context,
                    source: source,
                    builder: (_) =>
                        Dialog(child: GameLogPanel(controller: h.controller)),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
            suite,
          ),
        );
        await t.pump();
        await activate(t, 'keyboard', const Key('open-log'));
        expect(
          InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
              .reduceMotion,
          isTrue,
        );
        final route = ModalRoute.of(t.element(find.byType(GameLogPanel)))!;
        route.navigator!.removeRoute(route);
        h.hold = false;
        h.respond(h.held!);
        await t.pump();
        await t.pumpAndSettle();
      } finally {
        await close(t, h);
      }
    });
    testWidgets(
      '$suite completed keyboard action does not silence a later native pointer selection',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await input(t, 'keyboard', 'find');
          await t.pumpAndSettle();
          h.hold = true;
          await t.tap(find.text('PTU 测试版'));
          await t.pump();
          expect(h.held!.name, 'gameLog.configure');
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isFalse,
          );
          h.hold = false;
          h.respond(h.held!);
          await t.pump();
          await t.pumpAndSettle();
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets(
      '$suite same-account status refresh preserves a keyboard wait',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          h.hold = true;
          await input(t, 'keyboard', 'find');
          h.account.value = h.account.value.copyWith(
            operation: AccountOperation.refreshing,
          );
          await t.pump();
          // The owner and pending operation have not changed. Updating the
          // account's status must not change the input origin of this wait.
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: GameLogPanel(controller: h.controller),
              ),
              suite,
            ),
          );
          await t.pump();
          expect(h.controller.value.busy, isTrue);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          h.hold = false;
          h.respond(h.held!);
          await t.pump();
          await t.pumpAndSettle();
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite unsupported Host disables every action', (t) async {
      final h = Harness(supported: false);
      try {
        await showPanel(t, h, suite);
        for (final button in t.widgetList<StarBridgeActionButton>(
          find.byType(StarBridgeActionButton),
        )) {
          expect(button.onActivate, isNull);
        }
        expect(h.requests, isEmpty);
      } finally {
        await close(t, h);
      }
    });
    testWidgets(
      '$suite controller replacement does not inherit an old keyboard wait',
      (t) async {
        final old = Harness(), next = Harness();
        try {
          await showPanel(t, old, suite);
          old.hold = true;
          await input(t, 'keyboard', 'find');
          next.hold = true;
          unawaited(next.controller.run(command: 'find'));
          await t.pump();
          await t.pumpWidget(
            scopedApp(
              SingleChildScrollView(
                child: GameLogPanel(controller: next.controller),
              ),
              suite,
            ),
          );
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isFalse,
          );
          old.hold = false;
          old.respond(old.held!);
          await t.pump();
          expect(next.controller.value.busy, isTrue);
          next.hold = false;
          next.respond(next.held!);
          await t.pump();
          await t.pumpAndSettle();
        } finally {
          await t.pumpWidget(const SizedBox());
          await old.close(t);
          await next.close(t);
        }
      },
    );
    testWidgets(
      '$suite late picker result cannot configure a changed account',
      (t) async {
        final h = Harness();
        final picker = Completer<String?>();
        try {
          await showPanel(t, h, suite, picker: () => picker.future);
          await input(t, 'pointer', 'add-version');
          h.session.advanceGeneration(2);
          h.account.value = h.account.value.copyWith(
            generation: 2,
            sessionState: AccountSessionState.signedOut,
          );
          picker.complete('C:/synthetic/HOTFIX/Game.log');
          await t.pump();
          await t.pumpAndSettle();
          expect(
            h.requests.where((r) => r.name == 'gameLog.addVersion'),
            isEmpty,
          );
          expect(h.controller.value.visible, isFalse);
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite old held reply cannot restore identity after logout', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        h.hold = true;
        await input(t, 'pointer', 'find');
        final old = h.held!;
        h.session.advanceGeneration(2);
        h.account.value = h.account.value.copyWith(
          generation: 2,
          sessionState: AccountSessionState.signedOut,
        );
        await t.pump();
        expect(find.byType(StarBridgeActionButton), findsNothing);
        h.hold = false;
        h.respond(old);
        await t.pump();
        expect(h.controller.value.visible, isFalse);
        expect(h.controller.value.handle, isNull);
      } finally {
        await close(t, h);
      }
    });
  }
}
