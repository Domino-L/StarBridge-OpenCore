import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_update_panel.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/features/settings/application_update_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_update_status.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'interaction_batch3bq_test.dart' show button;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;

Map<String, dynamic> updateStatus([String state = 'available']) => {
  'schemaVersion': 1,
  'state': state,
  'currentVersion': '0.7.0',
  'availableVersion': state == 'available' ? '0.7.1' : null,
  'notes': state == 'available'
      ? '## Regression notes\n- Synthetic test only'
      : null,
};
Map<String, dynamic> prepared([
  String ticket = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
]) => {'schemaVersion': 1, 'version': '0.7.1', 'ticket': ticket};
Map<String, dynamic> updateProgress(
  int received,
  int? total, [
  String phase = 'downloading',
]) => {
  'schemaVersion': 1,
  'requestId': 'synthetic',
  'version': '0.7.1',
  'phase': phase,
  'receivedBytes': received,
  'totalBytes': total,
};

class UpdateBridge {
  UpdateBridge() {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities([
      'applicationUpdates.check',
      'applicationUpdates.prepare',
      'applicationUpdates.handoff',
    ]);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.messageType != 'request') return;
      if (request.name == 'applicationUpdates.check' && !holdCheck) {
        unawaited(reply(request, updateStatus(state)));
      }
      if (request.name == 'applicationUpdates.handoff') {
        unawaited(reply(request, {'schemaVersion': 1, 'accepted': accepted}));
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  bool holdCheck = false, accepted = true, current = true, allowExit = true;
  String state = 'available';
  ExitApplicationIntent? exit;
  VoidCallback? dismiss;
  int sequence = 0;
  Iterable<BridgeEnvelope> calls(String name) =>
      requests.where((r) => r.messageType == 'request' && r.name == name);
  BridgeEnvelope last(String name) => calls(name).last;
  Future<void> reply(BridgeEnvelope r, Map<String, dynamic> payload) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          payload: payload,
          status: 'ok',
        ),
      );
  Future<void> progress(
    BridgeEnvelope r,
    int received,
    int? total, {
    String? requestId,
    int generation = 1,
    String phase = 'downloading',
  }) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'applicationUpdates.progress',
      sessionGeneration: generation,
      sequence: ++sequence,
      payload: {
        ...updateProgress(received, total, phase),
        'requestId': requestId ?? r.correlationId,
      },
    ),
  );
  Widget home({bool announcement = false}) {
    final child = Builder(
      builder: (context) => StarBridgeActionButton(
        controlKey: const Key('update-open'),
        onActivate: (_) => unawaited(
          showApplicationUpdateDialog(
            context,
            session,
            initialStatus: announcement
                ? ApplicationUpdateStatus.parse(updateStatus())
                : null,
            startupAnnouncement: announcement,
            isCurrent: () => current,
            onDismissReady: (close) => dismiss = close,
          ),
        ),
        child: const Text('Open update'),
      ),
    );
    return !allowExit
        ? child
        : Actions(
            actions: {
              ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
                onInvoke: (intent) {
                  exit = intent;
                  return null;
                },
              ),
            },
            child: child,
          );
  }

  Future<void> clean(WidgetTester t) async {
    dismiss?.call();
    await t.pump();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    await t.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  }
}

Future<void> openUpdate(
  WidgetTester t,
  UpdateBridge h,
  InteractionSuite suite, [
  String source = 'pointer',
  bool announcement = false,
]) async {
  await t.pumpWidget(scopedApp(h.home(announcement: announcement), suite));
  await t.pumpAndSettle();
  await hit(t, source, 'update-open');
  await frames(t);
  final route = ModalRoute.of(
    t.element(find.byKey(const Key('application-update-dialog'))),
  );
  expect(route, isA<StarBridgeDialogRoute<String>>());
  expect((route as StarBridgeDialogRoute).instant, source != 'pointer');
  expect(route.barrierDismissible, isFalse);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final state in [
      'channel-unconfigured',
      'up-to-date',
      'configuration-invalid',
      'channel-unavailable',
      'verification-failed',
      'available',
    ]) {
      testWidgets('$suite verified state $state keeps original action gates', (
        t,
      ) async {
        final h = UpdateBridge()..state = state;
        try {
          await openUpdate(t, h, suite);
          expect(find.byKey(const Key('update-install')), findsNothing);
          expect(
            find.byKey(const Key('update-download')),
            state == 'available' ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('update-retry')),
            ['channel-unavailable', 'verification-failed'].contains(state)
                ? findsOneWidget
                : findsNothing,
          );
          expect(h.calls('applicationUpdates.check').length, 1);
          expect(h.calls('applicationUpdates.prepare'), isEmpty);
          expect(h.calls('applicationUpdates.handoff'), isEmpty);
        } finally {
          await h.clean(t);
        }
      });
    }
    testWidgets(
      '$suite startup announcement consumes the verified snapshot only',
      (t) async {
        final h = UpdateBridge();
        try {
          await openUpdate(t, h, suite, 'pointer', true);
          expect(h.calls('applicationUpdates.check'), isEmpty);
          expect(applicationUpdateShownVersions(h.session), contains('0.7.1'));
          expect(find.text('稍后'), findsOneWidget);
          await hit(t, 'keyboard', 'update-close');
          await t.pumpAndSettle();
          expect(h.exit, isNull);
          expect(h.calls('applicationUpdates.prepare'), isEmpty);
        } finally {
          await h.clean(t);
        }
      },
    );
    for (final missing in ['prepare', 'handoff', 'exit']) {
      testWidgets('$suite missing $missing cannot authorize download or exit', (
        t,
      ) async {
        final h = UpdateBridge()..allowExit = missing != 'exit';
        if (missing != 'exit') {
          h.session.acceptHostCapabilities([
            'applicationUpdates.check',
            if (missing != 'prepare') 'applicationUpdates.prepare',
            if (missing != 'handoff') 'applicationUpdates.handoff',
          ]);
        }
        try {
          await openUpdate(t, h, suite);
          expect(find.byKey(const Key('update-download')), findsNothing);
          expect(find.textContaining('此安装暂时无法在应用内更新'), findsOneWidget);
          expect(h.exit, isNull);
          expect(h.calls('applicationUpdates.prepare'), isEmpty);
        } finally {
          await h.clean(t);
        }
      });
    }
    testWidgets(
      '$suite cancel and retry ignore old prepare reply and old progress',
      (t) async {
        final h = UpdateBridge();
        try {
          await openUpdate(t, h, suite);
          await hit(t, 'pointer', 'update-download');
          await frames(t);
          final old = h.last('applicationUpdates.prepare');
          await h.progress(old, 1048576, null);
          await frames(t);
          expect(find.text('1.0 MB'), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsNothing);
          await hit(t, 'keyboard', 'update-cancel');
          await t.pumpAndSettle();
          expect(find.text('下载已取消，当前版本保持不变。'), findsOneWidget);
          await hit(t, 'pointer', 'update-download');
          await frames(t);
          final latest = h.last('applicationUpdates.prepare');
          expect(latest.correlationId, isNot(old.correlationId));
          await h.reply(old, prepared());
          await h.progress(old, 2097152, 2097152);
          await frames(t);
          expect(find.byKey(const Key('update-install')), findsNothing);
          expect(find.byType(SuiteProgressBar), findsNothing);
          await h.progress(latest, 1048576, 2097152);
          await frames(t);
          expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
          await h.reply(latest, prepared('b' * 32));
          await frames(t);
          expect(button(t, 'update-install').onActivate, isNotNull);
          expect(h.calls('applicationUpdates.handoff'), isEmpty);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets('$suite malformed ticket remains failed not ready', (t) async {
      final h = UpdateBridge();
      try {
        await openUpdate(t, h, suite);
        await hit(t, 'pointer', 'update-download');
        await frames(t);
        await h.reply(
          h.last('applicationUpdates.prepare'),
          prepared('not-a-ticket'),
        );
        await frames(t);
        expect(find.textContaining('更新未准备完成'), findsOneWidget);
        expect(find.byKey(const Key('update-install')), findsNothing);
        expect(button(t, 'update-download').onActivate, isNotNull);
        expect(h.exit, isNull);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets(
      '$suite live theme and reduce affect known progress without another request',
      (t) async {
        final h = UpdateBridge();
        try {
          await openUpdate(t, h, suite);
          await hit(t, 'pointer', 'update-download');
          await frames(t);
          final request = h.last('applicationUpdates.prepare');
          await h.progress(request, 1048576, 2097152);
          await t.pump();
          final notes = t.element(find.byType(UpdateReleaseNotes));
          await t.pumpWidget(
            scopedApp(h.home(), suite, reduce: true, light: true),
          );
          await t.pump();
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                .reduceMotion,
            isTrue,
          );
          expect(
            Theme.of(
              t.element(find.byKey(const Key('application-update-dialog'))),
            ).brightness,
            Brightness.light,
          );
          expect(t.element(find.byType(UpdateReleaseNotes)), same(notes));
          await h.progress(request, 1572864, 2097152);
          await frames(t);
          expect(
            t.widget<SuiteProgressBar>(find.byType(SuiteProgressBar)).value,
            .75,
          );
          expect(h.calls('applicationUpdates.prepare').length, 1);
          await hit(t, 'keyboard', 'update-close');
          await t.pumpAndSettle();
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite closed check ignores late offer without another popup',
      (t) async {
        final h = UpdateBridge()..holdCheck = true;
        try {
          await openUpdate(t, h, suite);
          final request = h.last('applicationUpdates.check');
          await hit(t, 'keyboard', 'update-close');
          await t.pumpAndSettle();
          await h.reply(request, updateStatus());
          await frames(t);
          expect(
            find.byKey(const Key('application-update-dialog')),
            findsNothing,
          );
          expect(applicationUpdateShownVersions(h.session), isEmpty);
          expect(h.exit, isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets('$suite owner retirement leaves a newer dialog alone', (
      t,
    ) async {
      final h = UpdateBridge();
      try {
        await openUpdate(t, h, suite);
        await hit(t, 'pointer', 'update-download');
        await frames(t);
        final request = h.last('applicationUpdates.prepare');
        final context = t.element(find.byKey(const Key('update-close')));
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) =>
                const AlertDialog(title: Text('Unrelated new dialog')),
          ),
        );
        await t.pumpAndSettle();
        h.dismiss!();
        await frames(t);
        await h.reply(request, prepared());
        await frames(t);
        expect(find.text('Unrelated new dialog'), findsOneWidget);
        expect(h.exit, isNull);
        expect(h.calls('applicationUpdates.handoff'), isEmpty);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets(
      '$suite installation confirmation invalidated before exit does not hand off',
      (t) async {
        final h = UpdateBridge();
        try {
          await openUpdate(t, h, suite);
          await hit(t, 'pointer', 'update-download');
          await frames(t);
          await h.reply(h.last('applicationUpdates.prepare'), prepared());
          await frames(t);
          h.current = false;
          await hit(t, 'keyboard', 'update-install');
          await t.pumpAndSettle();
          expect(h.exit, isNull);
          expect(h.calls('applicationUpdates.handoff'), isEmpty);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite declined handoff stays failed and keeps source-aware feedback',
      (t) async {
        final h = UpdateBridge()..accepted = false;
        try {
          await openUpdate(t, h, suite);
          await hit(t, 'pointer', 'update-download');
          await frames(t);
          await h.reply(h.last('applicationUpdates.prepare'), prepared());
          await frames(t);
          await hit(t, 'keyboard', 'update-install');
          await t.pumpAndSettle();
          final future = h.exit!.beforeExit!();
          await frames(t);
          expect(await future, isFalse);
          await frames(t);
          expect(find.text('更新未能启动，客户端保持打开。'), findsOneWidget);
          expect(h.calls('applicationUpdates.handoff').length, 1);
        } finally {
          await h.clean(t);
        }
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source explicit recheck keeps source without a prepare',
        (t) async {
          final h = UpdateBridge()..state = 'verification-failed';
          final semantics = t.ensureSemantics();
          try {
            await openUpdate(t, h, suite);
            h.holdCheck = true;
            await hit(t, source, 'update-retry');
            await frames(t);
            expect(find.text('正在检查更新…'), findsOneWidget);
            expect(
              t
                  .widget<SuiteContentSwitcher>(
                    find.byType(SuiteContentSwitcher),
                  )
                  .instant,
              source != 'pointer',
            );
            expect(h.calls('applicationUpdates.check').length, 2);
            await h.reply(
              h.last('applicationUpdates.check'),
              updateStatus('up-to-date'),
            );
            await frames(t);
            expect(find.text('当前已是最新版本。'), findsOneWidget);
            expect(h.calls('applicationUpdates.prepare'), isEmpty);
            expect(h.exit, isNull);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source real progress and explicit install preserve guards',
        (t) async {
          final h = UpdateBridge(), semantics = t.ensureSemantics();
          try {
            await openUpdate(t, h, suite, source);
            final download = button(t, 'update-download').onActivate!;
            await hit(t, source, 'update-download');
            await frames(t);
            download(InteractionSource.pointer);
            await frames(t);
            expect(h.calls('applicationUpdates.prepare').length, 1);
            final request = h.last('applicationUpdates.prepare');
            await h.progress(request, 1048576, 2097152, requestId: 'another');
            await h.progress(request, 1048576, 2097152, generation: 0);
            await frames(t);
            expect(find.byType(SuiteProgressBar), findsNothing);
            await h.progress(request, 1048576, 2097152);
            await frames(t);
            expect(
              t.widget<SuiteProgressBar>(find.byType(SuiteProgressBar)).value,
              .5,
            );
            expect(
              t.getSize(find.byType(SuiteProgressBar)).width,
              greaterThan(200),
              reason: 'Real progress must span the content, not collapse into a dot',
            );
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            final notes = t.element(find.byType(UpdateReleaseNotes));
            for (
              var received = 1050000;
              received < 2097152;
              received += 60000
            ) {
              await h.progress(request, received, 2097152);
            }
            await h.progress(request, 2097152, 2097152, phase: 'verified');
            await frames(t);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(find.byKey(const Key('update-install')), findsNothing);
            expect(t.element(find.byType(UpdateReleaseNotes)), same(notes));
            await h.reply(request, prepared());
            await frames(t);
            expect(h.exit, isNull);
            expect(h.calls('applicationUpdates.handoff'), isEmpty);
            await hit(t, source, 'update-install');
            await t.pumpAndSettle();
            expect(
              h.exit!.source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(h.calls('applicationUpdates.handoff'), isEmpty);
            final handoff = h.exit!.beforeExit!();
            await frames(t);
            expect(await handoff, isTrue);
            expect(h.calls('applicationUpdates.handoff').length, 1);
            expect(h.last('applicationUpdates.handoff').payload, {
              'schemaVersion': 1,
              'ticket': 'a' * 32,
            });
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source update factory preserves non-dismissible ownership',
        (t) async {
          final h = UpdateBridge(), semantics = t.ensureSemantics();
          try {
            await openUpdate(t, h, suite, source);
            expect(
              h.requests
                  .where((r) => r.name == 'applicationUpdates.check')
                  .length,
              1,
            );
            expect(button(t, 'update-download').onActivate, isNotNull);
            await t.tapAt(const Offset(1, 1));
            await frames(t);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await frames(t);
            expect(
              find.byKey(const Key('application-update-dialog')),
              findsOneWidget,
            );
            await hit(t, source, 'update-close');
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('application-update-dialog')),
              findsNothing,
            );
            expect(h.exit, isNull);
            expect(
              h.requests.where((r) => r.name != 'applicationUpdates.check'),
              isEmpty,
            );
          } finally {
            await h.clean(t);
            semantics.dispose();
          }
        },
      );
    }
  }
}
