import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/first_use_recovery_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_first_use_startup.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../features/onboarding/connection_mode_test.dart' show modeWire;

class RecoveryHost {
  RecoveryHost() {
    session.acceptHostCapabilities([
      BridgeFirstUseStartup.capability,
      BridgeConnectionModeAdapter.capability,
    ]);
    subscription = pair.host.incoming.listen((r) async {
      requests.add(r);
      expectSync(r.accountContext, isNull);
      expectSync(r.payload, {'schemaVersion': 1});
      expectSync(
        r.name,
        anyOf('onboarding.startup.read', 'onboarding.mode.read'),
      );
      if (r.name == 'onboarding.startup.read' && hold != null) {
        held = r;
        await hold!.future;
      }
      await reply(
        r,
        r.name == 'onboarding.startup.read' ? startup : modeWire(state),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final mode = ConnectionModeController(
    BridgeConnectionModeAdapter(session),
  );
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?> startup = startupWire('unknown', 'unreadableProgress');
  String state = 'online';
  Completer<void>? hold;
  BridgeEnvelope? held;
  Future<void> reply(BridgeEnvelope r, Map<String, Object?> payload) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          status: 'ok',
          payload: payload,
        ),
      );
  Future<void> event({int generation = 7}) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: generation == 7 ? 'onboarding.changed' : 'account.changed',
      sessionGeneration: generation,
      sequence: 1,
      payload: const {},
    ),
  );
  Future<void> close(WidgetTester tester) async {
    mode.dispose();
    await tester.runAsync(() async {
      await session.close();
      await subscription.cancel();
      await pair.host.close();
    });
  }
}

Map<String, Object?> startupWire(String eligibility, String reason) => {
  'schemaVersion': 1,
  'eligibility': eligibility,
  'reason': reason,
  'hasProgress': reason == 'resume',
};
Future<void> pump(WidgetTester tester, StartupPromptQueue queue) =>
    tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [queue],
        home: const Scaffold(body: Text('original')),
      ),
    );
Future<bool> check(WidgetTester tester, FirstUseRecoveryFlow flow) async {
  final result = flow.check();
  var done = false;
  unawaited(result.then((_) => done = true));
  for (var i = 0; i < 10 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(
    done,
    true,
    reason: 'original read must finish after its zero-delay mode task',
  );
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final pair in [
    ('firstUse', 'freshInstallation'),
    ('firstUse', 'resume'),
    ('returning', 'previousUse'),
    ('returning', 'completedSetup'),
    ('returning', 'updateInstallation'),
    ('unknown', 'unreadableHistory'),
    ('unknown', 'unreadableProgress'),
    ('unknown', 'installationUnknown'),
  ]) {
    test(
      'strict original startup facts accept ${pair.$2} without mode or completion permission',
      () {
        final value = BridgeFirstUseStartup.parse(
          startupWire(pair.$1, pair.$2),
          7,
        );
        expect(value.reason, pair.$2);
        expect(value.scope, 7);
      },
    );
  }
  final invalid = [
    {...startupWire('firstUse', 'freshInstallation'), 'schemaVersion': 1.0},
    {...startupWire('firstUse', 'freshInstallation'), 'hasProgress': true},
    {...startupWire('firstUse', 'resume'), 'hasProgress': false},
    {...startupWire('firstUse', 'previousUse')},
    {...startupWire('returning', 'resume')},
    {...startupWire('unknown', 'completedSetup')},
    {...startupWire('unknown', 'installationUnknown'), 'reset': true},
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('contradictory or extended startup evidence $i is rejected', () {
      expect(
        () => BridgeFirstUseStartup.parse(invalid[i], 7),
        throwsFormatException,
      );
    });
  }
  for (final state in [
    'unavailable',
    'recoveryRequired',
    'online',
    'local',
    'offline',
    'signInRequired',
    'switching',
  ]) {
    testWidgets(
      'recovery classification follows original mode $state and returning startup metadata',
      (tester) async {
        final host = RecoveryHost()
          ..state = state
          ..startup = startupWire('returning', 'previousUse');
        final queue = StartupPromptQueue(
          quietPeriod: const Duration(milliseconds: 5),
        );
        var shown = 0;
        final flow = FirstUseRecoveryFlow(
          session: host.session,
          mode: host.mode,
          queue: queue,
          ready: () => true,
          current: () => true,
          show: (_) async {
            shown++;
            return FirstUseRecoveryChoice.keepCurrent;
          },
          openSetup: () => throw StateError('No explicit open'),
        );
        await pump(tester, queue);
        expect(
          await check(tester, flow),
          ['unavailable', 'recoveryRequired', 'switching'].contains(state),
        );
        await tester.pumpAndSettle();
        expect(
          shown,
          ['unavailable', 'recoveryRequired'].contains(state) ? 1 : 0,
        );
        flow.dispose();
        queue.dispose();
        await tester.pump();
        await host.close(tester);
      },
    );
  }
  testWidgets(
    'keeping records is one prompt per launch and never an onboarding write',
    (tester) async {
      final host = RecoveryHost(),
          queue = StartupPromptQueue(
            quietPeriod: const Duration(milliseconds: 5),
          );
      var shown = 0, opened = 0;
      final flow = FirstUseRecoveryFlow(
        session: host.session,
        mode: host.mode,
        queue: queue,
        ready: () => true,
        current: () => true,
        show: (_) async {
          shown++;
          return FirstUseRecoveryChoice.keepCurrent;
        },
        openSetup: () async => opened++,
      );
      await pump(tester, queue);
      expect(await check(tester, flow), true);
      await tester.pumpAndSettle();
      expect(await check(tester, flow), true);
      await tester.pumpAndSettle();
      expect(shown, 1);
      expect(opened, 0);
      flow.dispose();
      queue.dispose();
      await host.close(tester);
    },
  );
  testWidgets(
    'manual navigation wins and the queued recheck can retire a now-healthy offer',
    (tester) async {
      final host = RecoveryHost(),
          queue = StartupPromptQueue(
            quietPeriod: const Duration(milliseconds: 5),
          );
      var ready = false, shown = 0, healthy = 0;
      final flow = FirstUseRecoveryFlow(
        session: host.session,
        mode: host.mode,
        queue: queue,
        ready: () => ready,
        current: () => true,
        show: (_) async {
          shown++;
          return null;
        },
        openSetup: () async {},
        onHealthy: () => healthy++,
      );
      await pump(tester, queue);
      expect(await check(tester, flow), true);
      await tester.pumpAndSettle();
      expect(flow.blocksOptionalPrompts, true);
      host.startup = startupWire('returning', 'previousUse');
      ready = true;
      queue.wake();
      await tester.pumpAndSettle();
      expect(shown, 0);
      expect(flow.blocksOptionalPrompts, false);
      expect(healthy, 1);
      flow.consumeManualEntry();
      expect(await check(tester, flow), true);
      flow.dispose();
      queue.dispose();
      await host.close(tester);
    },
  );
  for (final change in ['generation', 'event', 'dispose', 'capability']) {
    testWidgets('held original startup read is not adopted after $change', (
      tester,
    ) async {
      final host = RecoveryHost()..hold = Completer<void>();
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      var shown = 0;
      final flow = FirstUseRecoveryFlow(
        session: host.session,
        mode: host.mode,
        queue: queue,
        ready: () => true,
        current: () => true,
        show: (_) async {
          shown++;
          return null;
        },
        openSetup: () async {},
      );
      await pump(tester, queue);
      final read = flow.check();
      await tester.pump();
      expect(host.held, isNotNull);
      if (change == 'dispose') {
        flow.dispose();
      } else if (change == 'capability') {
        host.session.acceptHostCapabilities([]);
      } else {
        await host.event(generation: change == 'generation' ? 8 : 7);
        await tester.pump();
      }
      host.hold!.complete();
      await tester.pump();
      await read;
      await tester.pumpAndSettle();
      expect(shown, 0);
      flow.dispose();
      queue.dispose();
      await host.close(tester);
    });
  }
  testWidgets('late setup navigation from a retired dialog does not run', (
    tester,
  ) async {
    final host = RecoveryHost(),
        queue = StartupPromptQueue(
          quietPeriod: const Duration(milliseconds: 5),
        );
    final choice = Completer<FirstUseRecoveryChoice?>();
    FirstUseRecoveryNotice? notice;
    var opened = 0;
    final flow = FirstUseRecoveryFlow(
      session: host.session,
      mode: host.mode,
      queue: queue,
      ready: () => true,
      current: () => true,
      show: (value) {
        notice = value;
        return choice.future;
      },
      openSetup: () async => opened++,
    );
    await pump(tester, queue);
    await check(tester, flow);
    await tester.pumpAndSettle();
    expect(notice!.active, true);
    await host.event(generation: 8);
    await tester.pump();
    expect(notice!.active, false);
    choice.complete(FirstUseRecoveryChoice.openSetup);
    await tester.pumpAndSettle();
    expect(opened, 0);
    flow.dispose();
    queue.dispose();
    await host.close(tester);
  });
}
