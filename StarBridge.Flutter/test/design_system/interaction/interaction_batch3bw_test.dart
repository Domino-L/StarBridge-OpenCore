import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/account/account_safety.dart';
import 'package:starbridge_flutter/features/account/account_safety_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3bq_test.dart' show button;
import 'interaction_batch3bt_test.dart' as inherited show hit;
import 'interaction_batch3i_test.dart' show scopedApp;

final _date = DateTime.utc(2026, 10, 14);
Future<void> hit(WidgetTester t, String source, String key) async {
  if (source != 'keyboard' || key != 'account-safety-close') {
    return inherited.hit(t, source, key);
  }
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  final icon = find.descendant(
    of: target,
    matching: find.byType(StarBridgeIcon),
  );
  Focus.of(t.element(icon)).requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

AccountSafetySnapshot safetySnapshot({bool appealed = false}) =>
    AccountSafetySnapshot(
      [
        AccountSafetyRecord(
          id: 'action-a',
          type: 'warning',
          text: 'Synthetic action for regression',
          createdAt: _date,
        ),
      ],
      appealed
          ? [
              AccountSafetyRecord(
                id: 'appeal-a',
                sanctionId: 'action-a',
                type: 'warning',
                text: 'Synthetic appeal',
                createdAt: _date,
                status: 'reviewing',
              ),
            ]
          : [],
      [],
      _date,
    );

class SafetyPort implements AccountSafetyPort {
  final changes = StreamController<void>.broadcast();
  bool enabled = true, disposed = false;
  int reads = 0, disposals = 0;
  final inputs = <(String, String, String)>[];
  Completer<AccountSafetySnapshot>? pendingRead;
  Completer<AccountAppealOutcome>? pendingSubmit;
  AccountSafetyFailure? failure;
  AccountSafetySnapshot snapshot = safetySnapshot();
  AccountAppealOutcome result = AccountAppealOutcome.submitted;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get canSubmit => enabled && !disposed;
  @override
  Future<AccountSafetySnapshot> read() {
    reads++;
    if (pendingRead case final p?) return p.future;
    if (failure case final f?) return Future.error(AccountSafetyException(f));
    return Future.value(snapshot);
  }

  @override
  Future<AccountAppealOutcome> submit(
    String id,
    String details,
    String request,
  ) {
    inputs.add((id, details, request));
    return pendingSubmit?.future ?? Future.value(result);
  }

  @override
  void dispose() {
    disposed = true;
    disposals++;
    unawaited(changes.close());
  }
}

Widget safetyHome(SafetyPort port) => Builder(
  builder: (context) => StarBridgeActionButton(
    controlKey: const Key('safety-open'),
    onActivate: (_) => unawaited(showAccountSafetyDialog(context, port)),
    child: const Text('Open safety'),
  ),
);

Future<void> frames(WidgetTester t, [int count = 25]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

Future<void> openSafety(
  WidgetTester t,
  SafetyPort p,
  InteractionSuite suite, [
  String source = 'pointer',
]) async {
  await t.pumpWidget(scopedApp(safetyHome(p), suite));
  await t.pumpAndSettle();
  await hit(t, source, 'safety-open');
  await frames(t);
  final route = ModalRoute.of(
    t.element(find.byKey(const Key('account-safety-dialog'))),
  );
  expect(route, isA<StarBridgeDialogRoute<void>>());
  expect((route as StarBridgeDialogRoute).instant, source != 'pointer');
}

Future<void> editSafety(WidgetTester t, [String source = 'pointer']) async {
  await hit(t, source, 'account-safety-edit-action-a');
  await frames(t);
  expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
  await t.enterText(
    find.byKey(const Key('account-safety-reason-action-a')),
    '  Please review this action.  ',
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 220));
}

Future<void> cleanSafety(WidgetTester t, SafetyPort p) async {
  if (p.pendingRead case final c? when !c.isCompleted) {
    c.complete(p.snapshot);
  }
  if (p.pendingSubmit case final c? when !c.isCompleted) {
    c.complete(AccountAppealOutcome.unknown);
  }
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $source shared safety route and read decoration', (
        t,
      ) async {
        final p = SafetyPort()
          ..pendingRead = Completer<AccountSafetySnapshot>();
        final semantics = t.ensureSemantics();
        try {
          await openSafety(t, p, suite, source);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          final data = InteractionScope.of(
            t.element(find.byType(SuiteProgressBar)),
          );
          expect(data.reduceMotion, source != 'pointer');
          expect(p.reads, 1);
          expect(p.inputs, isEmpty);
          p.pendingRead!.complete(p.snapshot);
          p.pendingRead = null;
          await frames(t);
          expect(find.byType(SelectableText), findsOneWidget);
          await hit(t, source, 'account-safety-close');
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-safety-dialog')), findsNothing);
          expect(p.disposals, 1);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
          semantics.dispose();
        }
      });
      testWidgets(
        '$suite $source safety wait serialized and editable input retained',
        (t) async {
          final p = SafetyPort()
            ..pendingSubmit = Completer<AccountAppealOutcome>();
          final semantics = t.ensureSemantics();
          try {
            await openSafety(t, p, suite, source);
            await editSafety(t, source);
            final native = t.widget<TextField>(
              find.byKey(const Key('account-safety-reason-action-a')),
            );
            expect(native.maxLength, 2000);
            expect(native.minLines, 3);
            expect(native.maxLines, 6);
            await hit(t, source, 'account-safety-submit-action-a');
            await frames(t);
            expect(p.inputs.length, 1);
            expect(p.inputs.single.$2, 'Please review this action.');
            expect(p.inputs.single.$3, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(
              button(t, 'account-safety-submit-action-a').onActivate,
              isNull,
            );
            expect(
              button(t, 'account-safety-cancel-action-a').onActivate,
              isNull,
            );
            expect(
              t
                  .widget<TextField>(
                    find.byKey(const Key('account-safety-reason-action-a')),
                  )
                  .enabled,
              isFalse,
            );
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            p.pendingSubmit!.complete(AccountAppealOutcome.rejected);
            p.pendingSubmit = null;
            await frames(t);
            expect(native.controller!.text, '  Please review this action.  ');
            expect(
              button(t, 'account-safety-submit-action-a').onActivate,
              isNotNull,
            );
            expect(t.takeException(), isNull);
          } finally {
            await cleanSafety(t, p);
            semantics.dispose();
          }
        },
      );
    }
    for (final outcome in [
      AccountAppealOutcome.submitted,
      AccountAppealOutcome.alreadySubmitted,
      AccountAppealOutcome.rejected,
      AccountAppealOutcome.unknown,
    ]) {
      testWidgets('$suite safety outcome $outcome preserves owner meaning', (
        t,
      ) async {
        final p = SafetyPort()..result = outcome;
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          await hit(t, 'pointer', 'account-safety-submit-action-a');
          await frames(t);
          expect(p.inputs.length, 1);
          if (outcome == AccountAppealOutcome.rejected) {
            expect(find.byType(TextField), findsOneWidget);
            expect(
              button(t, 'account-safety-submit-action-a').onActivate,
              isNotNull,
            );
            p.result = AccountAppealOutcome.submitted;
            await hit(t, 'pointer', 'account-safety-submit-action-a');
            await frames(t);
            expect(p.inputs.length, 2);
            expect(p.inputs[0].$3, isNot(p.inputs[1].$3));
          }
          if (outcome == AccountAppealOutcome.unknown) {
            expect(find.text('暂未收到提交结果，正在自动核对。请勿重复提交。'), findsOneWidget);
            expect(find.byType(TextField), findsNothing);
            await t.pump(const Duration(seconds: 30));
            await frames(t);
            expect(p.inputs.length, 1);
            expect(p.reads, greaterThanOrEqualTo(3));
          } else {
            expect(find.text('已提交申诉'), findsOneWidget);
            expect(find.byType(TextField), findsNothing);
          }
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      });
    }
    testWidgets('$suite cancel and reopen preserves draft without submission', (
      t,
    ) async {
      final p = SafetyPort();
      try {
        await openSafety(t, p, suite);
        await editSafety(t);
        await hit(t, 'keyboard', 'account-safety-cancel-action-a');
        await t.pump();
        expect(find.byType(TextField), findsNothing);
        await hit(t, 'pointer', 'account-safety-edit-action-a');
        await frames(t);
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          '  Please review this action.  ',
        );
        expect(p.inputs, isEmpty);
        await t.enterText(find.byType(TextField), '   ');
        await t.pump();
        expect(button(t, 'account-safety-submit-action-a').onActivate, isNull);
      } finally {
        await cleanSafety(t, p);
      }
    });
    testWidgets(
      '$suite identity switch removes draft and ignores late appeal',
      (t) async {
        final p = SafetyPort()
          ..pendingSubmit = Completer<AccountAppealOutcome>();
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          await hit(t, 'pointer', 'account-safety-submit-action-a');
          await frames(t);
          final pending = p.pendingSubmit!;
          p.pendingSubmit = null;
          p.snapshot = AccountSafetySnapshot([], [], [], _date);
          p.changes.add(null);
          await frames(t);
          expect(find.byType(TextField), findsNothing);
          pending.complete(AccountAppealOutcome.submitted);
          await frames(t);
          expect(find.text('已提交申诉'), findsNothing);
          expect(p.inputs.length, 1);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets('$suite close while pending cannot affect a later route', (
      t,
    ) async {
      final p = SafetyPort()..pendingSubmit = Completer<AccountAppealOutcome>();
      try {
        await openSafety(t, p, suite);
        await editSafety(t);
        await hit(t, 'pointer', 'account-safety-submit-action-a');
        await frames(t);
        await hit(t, 'keyboard', 'account-safety-close');
        await t.pumpAndSettle();
        expect(p.disposals, 1);
        final context = t.element(find.byKey(const Key('safety-open')));
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) =>
                const AlertDialog(title: Text('New unrelated dialog')),
          ),
        );
        await t.pumpAndSettle();
        p.pendingSubmit!.complete(AccountAppealOutcome.submitted);
        p.pendingSubmit = null;
        await frames(t);
        expect(find.text('New unrelated dialog'), findsOneWidget);
        expect(p.inputs.length, 1);
        expect(t.takeException(), isNull);
      } finally {
        await cleanSafety(t, p);
      }
    });
    testWidgets(
      '$suite live reduce and theme settle open route and preserve draft',
      (t) async {
        final p = SafetyPort()
          ..pendingSubmit = Completer<AccountAppealOutcome>();
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          final text = t.widget<TextField>(find.byType(TextField)).controller;
          await hit(t, 'pointer', 'account-safety-submit-action-a');
          await t.pump();
          await t.pumpWidget(
            scopedApp(safetyHome(p), suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          expect(
            t.widget<TextField>(find.byType(TextField)).controller,
            same(text),
          );
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          expect(
            Theme.of(t.element(find.byKey(const Key('account-safety-dialog'))))
                .brightness,
            Brightness.light,
          );
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets(
      '$suite escape is instant and barrier policy stays dismissible',
      (t) async {
        final p = SafetyPort();
        try {
          await openSafety(t, p, suite);
          final route = ModalRoute.of(
            t.element(find.byKey(const Key('account-safety-dialog'))),
          )!;
          expect(route.barrierDismissible, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byKey(const Key('account-safety-dialog')), findsNothing);
          expect(p.disposals, 1);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    for (final failure in AccountSafetyFailure.values) {
      testWidgets('$suite read failure $failure is not empty or submitted', (
        t,
      ) async {
        final p = SafetyPort()..failure = failure;
        try {
          await openSafety(t, p, suite);
          expect(
            find.byKey(const Key('account-safety-edit-action-a')),
            findsNothing,
          );
          expect(find.text('已提交申诉'), findsNothing);
          expect(find.text('暂无记录'), findsNothing);
          expect(p.inputs, isEmpty);
          await t.pump(const Duration(seconds: 30));
          await frames(t);
          expect(p.reads, greaterThanOrEqualTo(2));
          p.failure = null;
          await t.pump(const Duration(seconds: 30));
          await frames(t);
          expect(
            button(t, 'account-safety-edit-action-a').onActivate,
            isNotNull,
          );
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      });
    }
    testWidgets(
      '$suite style change preserves input selection and native focus',
      (t) async {
        final p = SafetyPort();
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          final field = t.widget<TextField>(find.byType(TextField));
          field.controller!.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 8,
          );
          field.focusNode!.requestFocus();
          await t.pump();
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          await t.pumpWidget(scopedApp(safetyHome(p), next));
          await frames(t);
          final after = t.widget<TextField>(find.byType(TextField));
          expect(after.controller, same(field.controller));
          expect(after.focusNode, same(field.focusNode));
          expect(
            after.controller!.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(after.focusNode!.hasFocus, isTrue);
          expect(p.inputs, isEmpty);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets(
      '$suite passive refresh keeps draft and never replays a command',
      (t) async {
        final p = SafetyPort();
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          final native = t.widget<TextField>(find.byType(TextField)).controller;
          p.pendingRead = Completer<AccountSafetySnapshot>();
          await t.pump(const Duration(seconds: 30));
          await frames(t);
          expect(
            t.widget<TextField>(find.byType(TextField)).controller,
            same(native),
          );
          expect(native!.text, '  Please review this action.  ');
          expect(
            button(t, 'account-safety-submit-action-a').onActivate,
            isNull,
          );
          expect(find.byType(SuiteProgressBar), findsNothing);
          p.pendingRead!.complete(p.snapshot);
          p.pendingRead = null;
          await frames(t);
          expect(
            button(t, 'account-safety-submit-action-a').onActivate,
            isNotNull,
          );
          expect(p.inputs, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets(
      '$suite two drafts show only the actual keyboard submission wait',
      (t) async {
        final p = SafetyPort()
          ..pendingSubmit = Completer<AccountAppealOutcome>();
        p.snapshot = AccountSafetySnapshot(
          [
            ...p.snapshot.sanctions,
            AccountSafetyRecord(
              id: 'action-b',
              type: 'warning',
              text: 'Second synthetic action',
              createdAt: _date,
            ),
          ],
          [],
          [],
          _date,
        );
        try {
          await openSafety(t, p, suite);
          await editSafety(t);
          await hit(t, 'pointer', 'account-safety-edit-action-b');
          await frames(t);
          await t.enterText(
            find.byKey(const Key('account-safety-reason-action-b')),
            'Second draft',
          );
          await t.pump();
          await hit(t, 'keyboard', 'account-safety-submit-action-a');
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          expect(
            button(t, 'account-safety-submit-action-b').onActivate,
            isNull,
          );
          expect(p.inputs.length, 1);
          expect(p.inputs.single.$1, 'action-a');
          p.pendingSubmit!.complete(AccountAppealOutcome.rejected);
          p.pendingSubmit = null;
          await frames(t);
          expect(
            t
                .widget<TextField>(
                  find.byKey(const Key('account-safety-reason-action-b')),
                )
                .controller!
                .text,
            'Second draft',
          );
          expect(
            button(t, 'account-safety-submit-action-b').onActivate,
            isNotNull,
          );
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets(
      '$suite pointer barrier closes and disposes the original owner',
      (t) async {
        final p = SafetyPort();
        try {
          await openSafety(t, p, suite);
          await t.tapAt(const Offset(1, 1));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('account-safety-dialog')), findsNothing);
          expect(p.disposals, 1);
          expect(p.inputs, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets('$suite disabled appeal has no reader activation', (t) async {
      final p = SafetyPort()..enabled = false;
      final semantics = t.ensureSemantics();
      try {
        await openSafety(t, p, suite);
        final data = t
            .getSemantics(find.byKey(const Key('account-safety-edit-action-a')))
            .getSemanticsData();
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(p.inputs, isEmpty);
      } finally {
        await cleanSafety(t, p);
        semantics.dispose();
      }
    });
    testWidgets(
      '$suite initial read completing after close has no retired UI',
      (t) async {
        final p = SafetyPort()
          ..pendingRead = Completer<AccountSafetySnapshot>();
        try {
          await openSafety(t, p, suite);
          await hit(t, 'keyboard', 'account-safety-close');
          await t.pumpAndSettle();
          expect(p.disposals, 1);
          p.pendingRead!.complete(p.snapshot);
          p.pendingRead = null;
          await frames(t);
          expect(find.byKey(const Key('account-safety-dialog')), findsNothing);
          expect(p.inputs, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await cleanSafety(t, p);
        }
      },
    );
    testWidgets('$suite capability disabled keeps appeal unavailable', (
      t,
    ) async {
      final p = SafetyPort()..enabled = false;
      try {
        await openSafety(t, p, suite);
        expect(button(t, 'account-safety-edit-action-a').onActivate, isNull);
        expect(p.inputs, isEmpty);
        expect(find.byType(TextField), findsNothing);
      } finally {
        await cleanSafety(t, p);
      }
    });
  }
}
