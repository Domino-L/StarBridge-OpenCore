import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_support_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_support_models.dart';
import 'package:starbridge_flutter/features/settings/application_support_module.dart';
import 'package:starbridge_flutter/features/settings/application_support_port.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_controller.dart';
import 'package:starbridge_flutter/features/settings/continuous_play_dialog.dart';
import 'package:starbridge_flutter/features/settings/installation_check_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_game_recognition_dialog.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_controller.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app;

const entries = [
  'support',
  'continuous',
  'runtime',
  'recognition',
  'installation',
];
const rowKey = Key('open-actual-settings-dialog');

Key closeKey(String entry) => Key(switch (entry) {
  'support' => 'application-support-close',
  'runtime' => 'runtime-status-close',
  'installation' => 'installation-check-close',
  _ => 'settings-entry-close',
});

void main() {
  for (final suite in InteractionSuite.values) {
    for (final entry in entries) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('$suite $entry actual opener and close source=$source', (
          tester,
        ) async {
          final fixture = Fixture();
          addTearDown(fixture.dispose);
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final semantics = tester.ensureSemantics();
          try {
            final opener = StarBridgeActionRow(
              controlKey: rowKey,
              focusNode: focus,
              semanticLabel: 'Open',
              onActivate: (context, _) =>
                  unawaited(fixture.open(entry, context)),
              child: const Text('Open'),
            );
            await tester.pumpWidget(app(opener, suite: suite));
            await tester.pumpAndSettle();
            if (source == 'pointer') {
              await tester.tap(find.byKey(rowKey));
            } else if (source == 'keyboard') {
              focus.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              final node = tester.getSemantics(find.byKey(rowKey));
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
            final dialog = find.byType(Dialog);
            expect(dialog, findsOneWidget);
            final route = ModalRoute.of(tester.element(dialog))!;
            expect(route, isA<StarBridgeDialogRoute<void>>());
            if (source == 'pointer') {
              expect(route.animation!.value, inExclusiveRange(0, 1));
            } else {
              expect(route.animation!.value, 1);
            }
            // Change theme/reduced motion while the real pointer route enters.
            await tester.pumpWidget(
              app(opener, suite: suite, reduce: true, light: true),
            );
            await tester.pump();
            expect(route.animation!.value, 1);
            expect(
              InteractionScope.of(tester.element(dialog)).reduceMotion,
              isTrue,
            );
            expect(InteractionScope.of(tester.element(dialog)).suite, suite);
            final barrier = tester.widget<ModalBarrier>(
              find.byWidgetPredicate(
                (widget) => widget is ModalBarrier && widget.color != null,
              ),
            );
            expect(barrier.color, const Color(0x66000000));
            await tester.pumpAndSettle();
            // Restore motion before closing: otherwise reduced motion could
            // hide a missing keyboard/reader source on the close action.
            await tester.pumpWidget(app(opener, suite: suite, light: true));
            await tester.pumpAndSettle();
            expect(
              InteractionScope.of(tester.element(dialog)).reduceMotion,
              isFalse,
            );
            final close = find.byKey(closeKey(entry));
            await tester.ensureVisible(close);
            if (source == 'keyboard') {
              final text = find
                  .descendant(of: close, matching: find.byType(Text))
                  .first;
              Focus.of(tester.element(text)).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            } else if (source == 'reader') {
              final node = tester.getSemantics(close);
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
            } else {
              await tester.tap(close);
            }
            await tester.pump();
            await tester.pump();
            if (source == 'pointer') {
              expect(dialog, findsOneWidget);
              await tester.pump(const Duration(milliseconds: 40));
              expect(dialog, findsOneWidget);
              await tester.pumpAndSettle();
            }
            expect(dialog, findsNothing);
            // Opening/closing never writes reminder settings, repairs an install,
            // opens a directory or disposes controllers borrowed from the caller.
            expect(fixture.reminderPort.writes, 0);
            expect(fixture.supportPort.opens, 0);
            expect(fixture.supportPort.closed, isFalse);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }
    }

    testWidgets(
      '$suite runtime pending read remains busy and late partial result is safe after exit',
      (tester) async {
        final pending = Completer<RuntimeInstallationFacts?>();
        var reads = 0;
        final controller = RuntimeStatusController(
          readInstallation: () {
            reads++;
            return pending.future;
          },
          readOverlay: () async =>
              const RuntimeOverlayFacts(windowState: 'closed'),
          readStartup: () async => null,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            StarBridgeActionRow(
              controlKey: rowKey,
              onActivate: (context, _) =>
                  unawaited(showRuntimeStatusDialog(context, controller)),
              child: const Text('Open'),
            ),
            suite: suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(rowKey));
        // The busy indicator intentionally never settles. Do not advance fake
        // time through the owner's 15-second timeout while waiting for a frame.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(controller.value.busy, isTrue);
        final refresh = find.byKey(const Key('runtime-status-refresh'));
        final adapter = tester.widget<StarBridgeActionButton>(
          find
              .ancestor(
                of: refresh,
                matching: find.byType(StarBridgeActionButton),
              )
              .first,
        );
        expect(adapter.onActivate, isNull);
        await tester.tap(refresh, warnIfMissed: false);
        expect(reads, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byType(Dialog), findsNothing);
        pending.completeError(StateError('Synthetic metadata failure'));
        await tester.pumpAndSettle();
        expect(controller.value.busy, isFalse);
        expect(controller.value.incomplete, isTrue);
        expect(controller.value.overlay!.windowState, 'closed');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite installation scan keeps owner result and failure/retry semantics',
      (tester) async {
        final port = SupportPort()..pending = Completer();
        final module = createApplicationSupportModule(port);
        addTearDown(module.dispose);
        final opener = StarBridgeActionRow(
          controlKey: rowKey,
          onActivate: (context, _) =>
              unawaited(showInstallationCheckDialog(context, module)),
          child: const Text('Open'),
        );
        await tester.pumpWidget(app(opener, suite: suite));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(rowKey));
        await tester.pumpAndSettle();
        final scan = find.byKey(const Key('installation-check-scan'));
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await tester.pump();
        expect(port.reads, 1);
        final adapter = tester.widget<StarBridgeActionButton>(
          find
              .ancestor(of: scan, matching: find.byType(StarBridgeActionButton))
              .first,
        );
        expect(adapter.onActivate, isNull);
        port.pending!.completeError(
          const ApplicationSupportException(
            ApplicationSupportFailure.inspectionFailed,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          module.projection.value.failure,
          ApplicationSupportFailure.inspectionFailed,
        );
        expect(
          find.textContaining('Current installation records'),
          findsNothing,
        );
        port.pending = Completer();
        await tester.tap(scan);
        await tester.pump();
        expect(port.reads, 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byType(Dialog), findsNothing);
        port.pending!.complete(supportSnapshot);
        await tester.pumpAndSettle();
        expect(module.projection.value.snapshot, same(supportSnapshot));
        expect(port.closed, isFalse);
        expect(port.opens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class Fixture {
  final reminderPort = ReminderPort();
  final supportPort = SupportPort();
  late final reminder = ContinuousPlayController(reminderPort);
  late final support = createApplicationSupportModule(supportPort);
  late final runtime = RuntimeStatusController(
    readInstallation: () async => null,
    readOverlay: () async => null,
    readStartup: () async => null,
  );
  Future<void> open(String entry, BuildContext context) => switch (entry) {
    'support' => showApplicationSupportDialog(context, support),
    'continuous' => showContinuousPlayDialog(context, reminder),
    'runtime' => showRuntimeStatusDialog(context, runtime),
    'recognition' => showLocalGameRecognitionDialog(context, null),
    _ => showInstallationCheckDialog(context, support),
  };
  void dispose() {
    reminder.dispose();
    support.dispose();
    runtime.dispose();
  }
}

class ReminderPort implements ContinuousPlayPort {
  int writes = 0;
  @override
  Future<ContinuousPlayValue> read() async => const ContinuousPlayValue(
    enabled: false,
    firstMinutes: 120,
    repeatMinutes: 60,
    revision: 3,
  );
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async {
    writes++;
    return desired;
  }
}

class SupportPort implements ApplicationSupportPort {
  int opens = 0, reads = 0;
  bool closed = false;
  Completer<ApplicationSupportSnapshot>? pending;
  @override
  Future<ApplicationSupportSnapshot> inspect() {
    reads++;
    return pending?.future ?? Future.value(supportSnapshot);
  }

  @override
  Future<void> openDataDirectory() async {
    opens++;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

const supportSnapshot = ApplicationSupportSnapshot(
  hasIssues: false,
  hasUnavailableChecks: false,
  dataDirectory: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'writable',
  ),
  gameLog: ApplicationSupportCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'readable',
  ),
  startup: ApplicationStartupCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'notEnabled',
    registered: false,
    targetExists: null,
    targetsCurrentExecutable: null,
  ),
  installation: ApplicationInstallationCheck(
    state: ApplicationSupportCheckState.healthy,
    detail: 'portable',
    mode: 'portable',
    currentInstallations: 1,
    otherInstallations: 0,
    orphanedRegistrations: 0,
    scanWarnings: 0,
  ),
);
