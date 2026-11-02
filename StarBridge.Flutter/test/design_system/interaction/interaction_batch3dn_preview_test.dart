import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_monitor_panel.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_waiting.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3dm_test.dart' show act;
import 'interaction_batch3dn_test.dart' show sourceOf, waitData;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_test.dart' as original;

class Experience extends original.ExperiencePort {
  final pending = <Completer<ExecHangarSnapshot>>[];
  Completer<ExecHangarSnapshot> testGate = Completer();
  @override
  Future<ExecHangarSnapshot> preview(
    ExecHangarReminders rules,
    int minutes,
    bool onlyNext,
  ) {
    previews++;
    final gate = Completer<ExecHangarSnapshot>();
    pending.add(gate);
    return gate.future;
  }

  @override
  Future<ExecHangarSnapshot> testReminder() {
    tests++;
    return testGate.future;
  }
}

Future<void> checkbox(WidgetTester t, String source, String label) async {
  final target = find.byKey(const Key('exec-only-next'));
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
    return;
  }
  if (source == 'reader') {
    reader(t, label);
    return;
  }
  final native = find.descendant(of: target, matching: find.byType(Checkbox));
  final focus = native.evaluate().isNotEmpty
      ? t.widget<Checkbox>(native).focusNode!
      : t
            .widget<SuiteCheckbox>(
              find.descendant(of: target, matching: find.byType(SuiteCheckbox)),
            )
            .focusNode!;
  focus.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source preview true-to-true and actual reminder pending retain distinct phases',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(1000, 1300));
            final port = Experience();
            Widget host({int revision = 0, bool invalid = false}) => scopedApp(
              SingleChildScrollView(
                child: ExecHangarMonitorPanel(
                  snapshot: original.sample(revision: revision),
                  now: original.origin,
                  busy: false,
                  canStart: true,
                  experience: port,
                  previewRules: ExecHangarReminders(
                    beforeOpenMinutes: invalid ? 0 : 5,
                  ),
                  onCommand: (_, _, _) {},
                ),
              ),
              suite,
            );
            await t.pumpWidget(host());
            await t.pump();
            final preview = find.byWidgetPredicate(
              (w) => w is ExecHangarWaiting && w.label == '正在查看本次监测安排…',
            );
            expect(port.pending, hasLength(1));
            expect(waitData(t, preview).reduceMotion, isTrue);
            expect(
              t.widget<ExecHangarWaiting>(preview).source,
              InteractionSource.programmatic,
            );
            final first = t.widget(preview).key;
            final context = t.element(find.byType(ExecHangarMonitorPanel)),
                strings = AppStrings.of(context);
            await checkbox(t, source, strings.text('execHangar.onlyNext'));
            await t.pump();
            await t.pump();
            expect(port.pending, hasLength(2));
            expect(t.widget(preview).key, isNot(first));
            expect(
              t.widget<ExecHangarWaiting>(preview).source,
              sourceOf(source),
            );
            expect(waitData(t, preview).reduceMotion, source != 'pointer');
            final second = t.widget(preview).key;
            port.pending.first.completeError(StateError('old preview failure'));
            await t.pump();
            expect(t.widget(preview).key, second);
            await t.pumpWidget(host(revision: 1));
            await t.pump();
            expect(port.pending, hasLength(3));
            expect(
              t.widget<ExecHangarWaiting>(preview).source,
              InteractionSource.programmatic,
            );
            expect(waitData(t, preview).reduceMotion, isTrue);
            final third = t.widget(preview).key;
            port.pending[1].complete(original.sample());
            await t.pump();
            expect(t.widget(preview).key, third);
            await t.pumpWidget(host(revision: 1, invalid: true));
            await t.pump();
            expect(port.pending, hasLength(3));
            expect(preview, findsNothing);
            port.pending[2].completeError(
              StateError('stale invalidated preview'),
            );
            await t.pump();
            expect(
              find.text(strings.text('execHangar.previewFailed')),
              findsNothing,
            );
            await t.pumpWidget(host(revision: 2));
            await t.pump();
            expect(port.pending, hasLength(4));
            await act(
              t,
              find.byKey(const Key('exec-test')),
              source,
              strings.text('execHangar.testReminder'),
            );
            await t.pump();
            final testWait = find.byWidgetPredicate(
              (w) =>
                  w is ExecHangarWaiting &&
                  w.label == strings.text('execHangar.testPending'),
            );
            expect(testWait, findsOneWidget);
            expect(
              t.widget<ExecHangarWaiting>(testWait).source,
              sourceOf(source),
            );
            expect(waitData(t, testWait).reduceMotion, source != 'pointer');
            expect(port.tests, 1);
            expect(port.saves, 0);
            expect(port.starts, 0);
            port.testGate.complete(original.sample(deliveryState: 'submitted'));
            await t.pump();
            await t.pump();
            expect(testWait, findsNothing);
            final submitted = find.text(
              strings.text('execHangar.testSubmitted'),
            );
            expect(submitted, findsOneWidget);
            expect(
              t
                  .widgetList<Semantics>(
                    find.ancestor(
                      of: submitted,
                      matching: find.byType(Semantics),
                    ),
                  )
                  .any((w) => w.properties.liveRegion == true),
              isTrue,
            );
            port.testGate = Completer();
            await act(
              t,
              find.byKey(const Key('exec-test')),
              source,
              strings.text('execHangar.testReminder'),
            );
            await t.pump();
            expect(port.tests, 2);
            await t.pumpWidget(const SizedBox());
            port.testGate.completeError(StateError('late reminder result'));
            port.pending.last.complete(original.sample());
            await t.pump();
            expect(find.byType(ExecHangarWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
