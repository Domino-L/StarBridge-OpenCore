import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/projected_connection_mode.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

Map<String, Object?> modeWire(String state, {int revision = 4}) => {
  'schemaVersion': 1,
  'revision': revision,
  'state': state,
  'activeMode': state == 'online'
      ? 'online'
      : ['local', 'offline', 'signInRequired'].contains(state)
      ? 'local'
      : null,
  'publicationSuspended': [
    'local',
    'offline',
    'signInRequired',
  ].contains(state),
  'canEnterOffline': state == 'online',
};
ConnectionModeSnapshot modeFact(String state) =>
    ConnectionModeWire.parse(modeWire(state), 7);

class ModePort implements ConnectionModePort {
  @override
  bool supported = true;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => events.stream;
  ConnectionModeSnapshot current = modeFact('online');
  final writes = <int>[];
  Completer<ConnectionModeSnapshot>? pending;
  int reads = 0;
  @override
  Future<ConnectionModeSnapshot> read() async {
    reads++;
    return supported ? current : const ConnectionModeSnapshot();
  }

  @override
  Future<ConnectionModeSnapshot> enterOffline(int revision) {
    writes.add(revision);
    return (pending ??= Completer()).future;
  }
}

void main() {
  test('offline identity is display-only and old Hosts remain supported', () {
    final display = {
      'displayName': 'Synthetic Pilot',
      'cachedAtUtc': '2026-10-14T12:00:00Z',
    };
    final offline = ConnectionModeWire.parse({
      ...modeWire('offline'),
      'offlineAccount': display,
    }, 7);
    expect(offline.offlineAccount!.displayName, 'Synthetic Pilot');
    expect(offline.canEnterOffline, isFalse);
    expect(modeFact('offline').offlineAccount, isNull);
    for (final invalid in [
      {...modeWire('online'), 'offlineAccount': display},
      {...modeWire('local'), 'offlineAccount': display},
      {
        ...modeWire('offline'),
        'offlineAccount': {...display, 'subject': 'not-authority'},
      },
      {
        ...modeWire('offline'),
        'offlineAccount': {...display, 'cachedAtUtc': 'invalid'},
      },
    ]) {
      expect(() => ConnectionModeWire.parse(invalid, 7), throwsFormatException);
    }
  });
  test(
    'mode accountless exception is finite and never authorizes business',
    () {
      for (final route in ['onboarding.mode.read', 'onboarding.mode.offline']) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(route, null),
          returnsNormally,
        );
      }
      for (final route in [
        'onboarding.mode.online',
        'onboarding.mode.finish',
        'onboarding.mode.offline.extra',
        'presence.set',
        'friends.read',
        'profile.update',
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(route, null),
          throwsA(isA<BridgeAccountContextRequiredException>()),
        );
      }
    },
  );
  for (final state in [
    'online',
    'local',
    'offline',
    'switching',
    'unavailable',
    'signInRequired',
    'recoveryRequired',
  ]) {
    test('strict mode facts accept $state without inferring readiness', () {
      final result = modeFact(state);
      expect(result.state.name, state);
      expect(result.isOffline, state == 'offline');
      expect(result.scope, 7);
    });
  }
  final invalid = <Map<String, Object?>>[
    {...modeWire('online'), 'schemaVersion': 1.0},
    {...modeWire('online'), 'revision': -1},
    {...modeWire('online'), 'revision': '4'},
    {...modeWire('online'), 'state': 'unsupported'},
    {...modeWire('online'), 'state': 'invented'},
    {...modeWire('online'), 'activeMode': 'local'},
    {...modeWire('online'), 'publicationSuspended': true},
    {...modeWire('online'), 'canEnterOffline': 'true'},
    {...modeWire('offline'), 'canEnterOffline': true},
    {...modeWire('offline'), 'publicationSuspended': false},
    {...modeWire('switching'), 'activeMode': 'online'},
    {...modeWire('switching'), 'publicationSuspended': true},
    {...modeWire('offline'), 'token': 'not-authority'},
    modeWire('offline')..remove('revision'),
  ];
  for (var i = 0; i < invalid.length; i++) {
    test('reject contradictory or overbroad mode projection $i', () {
      expect(
        () => ConnectionModeWire.parse(invalid[i], 7),
        throwsFormatException,
      );
    });
  }
  test(
    'one confirmed offline write blocks presence and duplicate clicks',
    () async {
      final port = ModePort(), mode = ConnectionModeController(port);
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 7,
          confirmedMode: PresenceVisibility.online,
          canChange: true,
        ),
      );
      var presenceWrites = 0;
      final presence = ManualPresenceController(
        source: source,
        connectionMode: mode,
        write: (_, _) async {
          presenceWrites++;
        },
      );
      await mode.refresh();
      expect(presence.canEnterOffline, true);
      final writing = presence.selectOffline();
      expect(presence.busy, true);
      expect(presence.isOffline, false);
      expect(presence.selfKey, 'presence.unknown');
      await presence.select(PresenceVisibility.invisible);
      expect(await presence.selectOffline(), false);
      expect(port.writes, [4]);
      port.pending!.complete(modeFact('offline'));
      expect(await writing, true);
      expect(presence.selfKey, 'presence.manualOffline');
      expect(presence.canChange, false);
      expect(presenceWrites, 0);
      presence.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
  for (final state in [
    'recoveryRequired',
    'signInRequired',
    'switching',
    'local',
  ]) {
    test('non-offline receipt $state is never confirmed red offline', () async {
      final port = ModePort(), mode = ConnectionModeController(port);
      await mode.refresh();
      final writing = mode.enterOffline();
      port.pending!.complete(modeFact(state));
      expect(await writing, false);
      expect(mode.snapshot.isOffline, false);
      expect(mode.allowsOnlineTraffic, false);
      mode.dispose();
      await port.events.close();
    });
  }
  test(
    'lost observation reconciles by read only and never repeats write',
    () async {
      final port = ModePort(), mode = ConnectionModeController(port);
      await mode.refresh();
      final writing = mode.enterOffline();
      port.current = modeFact('offline');
      port.events.add(null);
      port.pending!.complete(modeFact('online'));
      expect(await writing, false);
      await mode.refresh();
      expect(mode.snapshot.isOffline, true);
      expect(port.writes, [4]);
      mode.dispose();
      await port.events.close();
    },
  );
  test(
    'capability loss after mode owner never falls back to presence writes',
    () async {
      final port = ModePort(), mode = ConnectionModeController(port);
      await mode.refresh();
      port.supported = false;
      port.events.add(null);
      await mode.refresh();
      expect(mode.snapshot.state, ConnectionModeState.unavailable);
      expect(mode.allowsOnlineTraffic, false);
      mode.dispose();
      await port.events.close();
    },
  );
  test(
    'genuinely old Host keeps legacy presence but no offline command',
    () async {
      final port = ModePort()..supported = false;
      final mode = ConnectionModeController(port);
      await mode.refresh();
      expect(mode.allowsOnlineTraffic, true);
      expect(await mode.enterOffline(), false);
      expect(port.writes, isEmpty);
      mode.dispose();
      await port.events.close();
    },
  );
  test('disposal fences late offline completion', () async {
    final port = ModePort(), mode = ConnectionModeController(port);
    await mode.refresh();
    final writing = mode.enterOffline();
    mode.dispose();
    port.pending!.complete(modeFact('offline'));
    expect(await writing, false);
    await port.events.close();
  });
  test(
    'borrowed tray does not retag a held command after scope changes',
    () async {
      final source = ValueNotifier(modeFact('online'));
      final pending = Completer<void>(), commands = <Object>[];
      final mode = ProjectedConnectionMode(
        source: source,
        write: (scope) {
          commands.add(scope);
          return pending.future;
        },
      );
      final writing = mode.enterOffline();
      source.value = const ConnectionModeSnapshot(
        scope: 8,
        state: ConnectionModeState.offline,
      );
      pending.complete();
      expect(await writing, false);
      expect(commands, [7]);
      mode.dispose();
      source.dispose();
    },
  );
  test(
    'actual Bridge uses accountless exact mode route, not presence or logout',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities([BridgeConnectionModeAdapter.capability]);
      final requests = <BridgeEnvelope>[];
      final sub = pair.host.incoming.listen((r) async {
        if (r.messageType != 'request') return;
        requests.add(r);
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: r.name,
            sessionGeneration: r.sessionGeneration,
            correlationId: r.correlationId,
            status: 'ok',
            payload: modeWire(r.name.endsWith('read') ? 'online' : 'offline'),
          ),
        );
      });
      final port = BridgeConnectionModeAdapter(session);
      expect((await port.read()).canEnterOffline, true);
      expect((await port.enterOffline(4)).isOffline, true);
      expect(requests.map((r) => r.name), [
        'onboarding.mode.read',
        'onboarding.mode.offline',
      ]);
      expect(requests.first.payload, {'schemaVersion': 1});
      expect(requests.last.payload, {'schemaVersion': 1, 'revision': 4});
      expect(requests.every((r) => r.accountContext == null), true);
      expect(() => port.enterOffline(4), throwsStateError);
      await sub.cancel();
      await session.close();
      await pair.host.close();
    },
  );
  test('Bridge without capability sends nothing', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final requests = <BridgeEnvelope>[];
    final sub = pair.host.incoming.listen(requests.add);
    final port = BridgeConnectionModeAdapter(session);
    expect((await port.read()).state, ConnectionModeState.unsupported);
    expect(() => port.enterOffline(4), throwsStateError);
    expect(requests, isEmpty);
    await sub.cancel();
    await session.close();
    await pair.host.close();
  });
  for (final scenario in ['owner', 'generation', 'contradiction']) {
    test(
      'actual Bridge rejects $scenario instead of trusting a successful transport',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 7,
        );
        session.acceptHostCapabilities([
          BridgeConnectionModeAdapter.capability,
        ]);
        final sub = pair.host.incoming.listen((r) async {
          if (r.messageType != 'request') return;
          if (scenario == 'generation') session.advanceGeneration(8);
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              sessionGeneration: r.sessionGeneration,
              correlationId: r.correlationId,
              status: 'ok',
              accountContext: scenario == 'owner'
                  ? const BridgeAccountContext(
                      environment: 'test',
                      authority: 'scm.invalid',
                      subject: 'sample',
                    )
                  : null,
              payload: {
                ...modeWire('online'),
                if (scenario == 'contradiction') 'publicationSuspended': true,
              },
            ),
          );
        });
        final port = BridgeConnectionModeAdapter(session);
        await expectLater(port.read(), throwsA(isA<Object>()));
        expect(() => port.enterOffline(4), throwsStateError);
        await sub.cancel();
        await session.close();
        await pair.host.close();
      },
    );
  }
}
