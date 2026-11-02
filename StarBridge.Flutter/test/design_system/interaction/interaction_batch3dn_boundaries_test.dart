import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_waiting.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dn_test.dart' show Tool, action, waitData;
import 'interaction_batch3dn_visual_test.dart' show capture;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_presets.dart';
import '../../features/tools/exec_hangar_test.dart' as original;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source clean monitor waiting stays visible after scrolling to the command',
        (t) async {
          size(t, const Size(390, 800));
          final port = Tool(), frame = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: scopedApp(ExecHangarPage(port: port), suite),
            ),
          );
          await t.pumpAndSettle();
          port.monitorGate = Completer();
          await action(t, 'exec-start', 'startMonitor', source);
          await t.pump(const Duration(milliseconds: 120));
          final waiting = find.byType(ExecHangarWaiting);
          expect(waiting, findsOneWidget);
          expect(t.getTopLeft(waiting).dy, greaterThanOrEqualTo(0));
          expect(t.getBottomRight(waiting).dy, lessThanOrEqualTo(800));
          expect(port.saveInputs, isEmpty);
          expect(port.commands, hasLength(1));
          expect(waitData(t, waiting).reduceMotion, source != 'pointer');
          await capture(t, frame, '3dn-${suite.name}-$source-clean-monitor');
          port.monitorGate!.completeError(
            StateError('synthetic monitor refusal'),
          );
          await t.pumpAndSettle();
          expect(waiting, findsNothing);
          expect(execPresetShown(t, execBeforeOpen), 5);
          expect(port.saveInputs, isEmpty);
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$suite hidden pending keeps original owner; active resume is programmatic even inside pointer command',
      (t) async {
        size(t, const Size(1000, 900));
        final port = Tool()..readGate = Completer();
        final key = GlobalKey<ExecHangarPageState>();
        Widget host(bool active) => scopedApp(
          Offstage(
            offstage: !active,
            child: ExecHangarPage(key: key, port: port, active: active),
          ),
          suite,
        );
        await t.pumpWidget(host(true));
        await t.pump(const Duration(milliseconds: 100));
        expect(port.reads, 1);
        await t.pumpWidget(host(false));
        await t.pump();
        expect(port.reads, 1);
        expect(t.hasRunningAnimations, isFalse);
        port.readGate!.complete(original.sample());
        await t.pump();
        port.readGate = Completer();
        await runStarBridgeActivation<void>(
          InteractionSource.pointer,
          () => t.pumpWidget(host(true)),
        );
        await t.pump();
        final waiting = find.byType(ExecHangarWaiting);
        expect(port.reads, 2);
        expect(
          t.widget<ExecHangarWaiting>(waiting).source,
          InteractionSource.programmatic,
        );
        expect(t.widget<ExecHangarWaiting>(waiting).opening, isFalse);
        expect(waitData(t, waiting).reduceMotion, isTrue);
        port.readGate!.completeError(StateError('resume read failed'));
        await t.pumpAndSettle();
        expect(waiting, findsNothing);
        expect(port.saveInputs, isEmpty);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite dirty start refused save never enters monitor; dispose does not start a late monitor',
      (t) async {
        size(t, const Size(1440, 1200));
        final port = Tool();
        await t.pumpWidget(scopedApp(ExecHangarPage(port: port), suite));
        await t.pumpAndSettle();
        await pickExecPreset(t, execBeforeOpen, 15);
        port.saveGate = Completer();
        await action(t, 'exec-start', 'startMonitor', 'keyboard');
        await t.pump();
        expect(
          waitData(t, find.byType(ExecHangarWaiting)).reduceMotion,
          isTrue,
        );
        port.saveGate!.completeError(StateError('save before monitor refused'));
        await t.pumpAndSettle();
        expect(port.commands, isEmpty);
        expect(find.byType(ExecHangarWaiting), findsNothing);
        expect(execPresetShown(t, execBeforeOpen), 15);
        port.saveGate = Completer();
        await action(t, 'exec-start', 'startMonitor', 'pointer');
        await t.pump();
        expect(port.saveInputs, hasLength(2));
        await t.pumpWidget(const SizedBox());
        port.saveGate!.complete(
          original.sample(revision: 1, reminders: port.saveInputs.last.rules),
        );
        await t.pump();
        await t.pump();
        expect(port.commands, isEmpty);
        expect(find.byType(ExecHangarWaiting), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite fresh cached reopen avoids read and stale pending read cannot undo mutation',
      (t) async {
        size(t, const Size(1440, 1200));
        final port = Tool();
        final cache = CachedExecHangar(port);
        await cache.read();
        await t.pumpWidget(scopedApp(ExecHangarPage(port: cache), suite));
        await t.pumpAndSettle();
        expect(port.reads, 1);
        expect(find.byType(ExecHangarWaiting), findsNothing);
        port.readGate = Completer();
        await action(t, 'exec-refresh', 'refresh', 'pointer');
        await t.pump();
        expect(port.reads, 2);
        final waiting = find.byType(ExecHangarWaiting),
            phase = t.widget(find.byType(ExecHangarWaiting)).key;
        const rules = ExecHangarReminders(beforeOpenMinutes: 12);
        await cache.save(rules, 0);
        await t.pump();
        expect(t.widget(waiting).key, phase);
        expect(
          t.widget<ExecHangarWaiting>(waiting).source,
          InteractionSource.pointer,
        );
        port.readGate!.complete(original.sample());
        await t.pumpAndSettle();
        expect(cache.snapshot!.revision, 1);
        expect(execPresetShown(t, execBeforeOpen), 12);
        expect(waiting, findsNothing);
        expect(port.saveInputs, hasLength(1));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
