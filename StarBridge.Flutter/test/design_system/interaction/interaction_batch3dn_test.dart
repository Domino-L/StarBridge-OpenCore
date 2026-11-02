import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_waiting.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_save_bar.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';

import 'interaction_batch3dm_test.dart' show act;
import 'interaction_batch3i_test.dart' show scopedApp;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_presets.dart';
import '../../features/tools/exec_hangar_test.dart' as original;

class Tool extends original.Port {
  Completer<ExecHangarSnapshot>? readGate, saveGate, monitorGate;
  final readFlags = <bool>[];
  final saveInputs = <({ExecHangarReminders rules, int revision})>[];
  final commands =
      <({ExecHangarAction action, int revision, int minutes, bool next})>[];
  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) {
    readFlags.add(refresh);
    final gate = readGate;
    if (gate == null) return super.read(refresh: refresh);
    reads++;
    return gate.future.then((next) {
      snapshot = next;
      return next;
    });
  }

  @override
  Future<ExecHangarSnapshot> save(ExecHangarReminders rules, int revision) {
    saveInputs.add((rules: rules, revision: revision));
    final gate = saveGate;
    if (gate == null) return super.save(rules, revision);
    saves++;
    return gate.future.then((next) {
      snapshot = next;
      return next;
    });
  }

  @override
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) {
    commands.add((
      action: action,
      revision: revision,
      minutes: durationMinutes,
      next: onlyNext,
    ));
    final gate = monitorGate;
    if (gate == null) {
      return super.monitor(
        action,
        revision,
        durationMinutes: durationMinutes,
        onlyNext: onlyNext,
      );
    }
    starts++;
    return gate.future.then((next) {
      snapshot = next;
      return next;
    });
  }
}

InteractionData waitData(WidgetTester t, Finder waiting) => InteractionScope.of(
  t.element(
    find.descendant(of: waiting, matching: find.byType(SuiteBusyFrame)),
  ),
);
InteractionSource sourceOf(String source) => source == 'pointer'
    ? InteractionSource.pointer
    : InteractionSource.keyboard;
Future<void> action(
  WidgetTester t,
  String key,
  String copy,
  String source,
) async {
  final target = find.byKey(Key(key));
  await act(
    t,
    target,
    source,
    AppStrings.of(t.element(target)).text('execHangar.$copy'),
  );
}

void expectWait(
  WidgetTester t,
  InteractionSource source, {
  bool opening = false,
}) {
  final target = find.byType(ExecHangarWaiting);
  expect(target, findsOneWidget);
  final wait = t.widget<ExecHangarWaiting>(target);
  expect(wait.source, source);
  expect(wait.opening, opening);
  expect(
    waitData(t, target).reduceMotion,
    source != InteractionSource.pointer && !opening,
  );
  expect(
    t
        .getSize(
          find.descendant(
            of: target,
            matching: find.byType(SocialReadActivity),
          ),
        )
        .width,
    greaterThan(100),
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final opening in [
      InteractionSource.pointer,
      InteractionSource.keyboard,
    ]) {
      testWidgets(
        '$suite $opening first read freezes opening and follows live reduce',
        (t) async {
          size(t, const Size(1000, 900));
          final port = Tool()..readGate = Completer();
          final key = GlobalKey<ExecHangarPageState>();
          Widget host({bool reduce = false, InteractionSource? changed}) =>
              scopedApp(
                Builder(
                  builder: (context) => starBridgeInitialReadViewport(
                    context,
                    source: changed ?? opening,
                    child: ExecHangarPage(key: key, port: port),
                  ),
                ),
                suite,
                reduce: reduce,
              );
          await t.pumpWidget(host());
          await t.pump(const Duration(milliseconds: 90));
          final waiting = find.byType(ExecHangarWaiting),
              phase = t.widget(waiting).key;
          expect(port.reads, 1);
          expect(t.widget<ExecHangarWaiting>(waiting).opening, isTrue);
          expect(
            waitData(t, waiting).reduceMotion,
            opening == InteractionSource.keyboard,
          );
          expect(
            t
                .getSize(
                  find.descendant(
                    of: waiting,
                    matching: find.byType(SocialReadActivity),
                  ),
                )
                .width,
            greaterThan(100),
          );
          await t.pumpWidget(
            host(
              changed: opening == InteractionSource.keyboard
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ),
          );
          await t.pump();
          expect(t.widget(waiting).key, phase);
          expect(
            waitData(t, waiting).reduceMotion,
            opening == InteractionSource.keyboard,
          );
          await t.pumpWidget(host(reduce: true));
          await t.pump();
          await t.pump();
          expect(waitData(t, waiting).reduceMotion, isTrue);
          expect(port.reads, 1);
          port.readGate!.complete(original.sample());
          await t.pumpAndSettle();
          expect(waiting, findsNothing);
          expect(port.saveInputs, isEmpty);
          expect(port.commands, isEmpty);
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source refresh and dirty save-monitor phases preserve origin, guards and results',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(1440, 1200));
            final port = Tool();
            await t.pumpWidget(scopedApp(ExecHangarPage(port: port), suite));
            await t.pumpAndSettle();
            port.readGate = Completer();
            await action(t, 'exec-refresh', 'refresh', source);
            await t.pump();
            expectWait(t, sourceOf(source));
            final phase = t.widget(find.byType(ExecHangarWaiting)).key;
            await t.pump(const Duration(seconds: 1));
            expect(t.widget(find.byType(ExecHangarWaiting)).key, phase);
            expect(port.readFlags, [false, true]);
            port.readGate!.completeError(StateError('synthetic offline'));
            await t.pumpAndSettle();
            port.readGate = null;
            expect(find.byType(ExecHangarWaiting), findsNothing);
            expect(execPresetShown(t, execBeforeOpen), 5);
            await pickExecPreset(t, execBeforeOpen, 15);
            port.saveGate = Completer();
            await action(t, 'exec-save', 'save', source);
            await t.pump();
            expectWait(t, sourceOf(source));
            expect(
              t.getTopLeft(find.byType(ExecHangarWaiting)).dy,
              greaterThanOrEqualTo(0),
            );
            expect(
              t.getBottomRight(find.byType(ExecHangarWaiting)).dy,
              lessThanOrEqualTo(1200),
            );
            expect(port.saveInputs.single.rules.beforeOpenMinutes, 15);
            port.saveGate!.completeError(StateError('synthetic save refusal'));
            await t.pumpAndSettle();
            expect(execPresetShown(t, execBeforeOpen), 15);
            expect(find.byType(ExecHangarSaveBar), findsOneWidget);
            port.saveGate = Completer();
            port.monitorGate = Completer();
            await action(t, 'exec-start', 'startMonitor', source);
            await t.pump();
            expectWait(t, sourceOf(source));
            final savePhase = t.widget(find.byType(ExecHangarWaiting)).key;
            expect(port.commands, isEmpty);
            expect(port.saveInputs, hasLength(2));
            port.saveGate!.complete(
              original.sample(
                revision: 1,
                reminders: port.saveInputs.last.rules,
              ),
            );
            await t.pump();
            await t.pump();
            expect(port.commands, hasLength(1));
            expect(port.commands.single.revision, 1);
            expect(port.commands.single.action, ExecHangarAction.start);
            expect(port.commands.single.minutes, 60);
            expect(port.commands.single.next, isFalse);
            expectWait(t, sourceOf(source));
            expect(
              t.widget(find.byType(ExecHangarWaiting)).key,
              isNot(savePhase),
            );
            port.monitorGate!.complete(
              original.sample(
                revision: 2,
                reminders: port.saveInputs.last.rules,
                plan: ExecHangarPlan(
                  active: true,
                  state: 'watching',
                  onlyNext: false,
                  endsAt: original.origin.add(const Duration(hours: 1)),
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(find.byType(ExecHangarWaiting), findsNothing);
            expect(find.byType(ExecHangarSaveBar), findsNothing);
            await pickExecPreset(t, execBeforeOpen, 30);
            port.monitorGate = Completer();
            await action(t, 'exec-stop', 'stopMonitor', source);
            await t.pump();
            expectWait(t, sourceOf(source));
            expect(
              port.saveInputs,
              hasLength(2),
              reason: 'stop must not save dirty draft',
            );
            expect(port.commands.last.action, ExecHangarAction.stop);
            port.monitorGate!.completeError(
              StateError('synthetic stop refusal'),
            );
            await t.pumpAndSettle();
            expect(execPresetShown(t, execBeforeOpen), 30);
            expect(find.byType(ExecHangarSaveBar), findsOneWidget);
            expect(find.byType(ExecHangarWaiting), findsNothing);
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
