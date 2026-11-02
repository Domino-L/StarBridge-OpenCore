import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/bridge_manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final scenario in [
    'persistent',
    'disposed',
    'account-change',
    'revoked',
  ]) {
    test('presence read recovery is bounded and scoped: $scenario', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      const first = BridgeAccountContext(
        environment: 'test',
        authority: 'scm.invalid',
        subject: 'first',
      );
      const second = BridgeAccountContext(
        environment: 'test',
        authority: 'scm.invalid',
        subject: 'second',
      );
      final subjects = <String>[];
      final sub = pair.host.incoming.listen((request) async {
        if (request.messageType != 'request') return;
        if (request.name != 'presence.read') {
          throw StateError('Recovery attempted a write.');
        }
        subjects.add(request.accountContext!.subject);
        final success = request.accountContext!.subject == 'second';
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            sessionGeneration: request.sessionGeneration,
            correlationId: request.correlationId,
            accountContext: request.accountContext,
            status: success ? 'ok' : 'error',
            error: success
                ? null
                : BridgeErrorBody(
                    code: scenario == 'revoked'
                        ? 'presence.account_changed'
                        : 'presence.unavailable',
                    message: 'Synthetic failure',
                    retryable: false,
                  ),
            payload: success
                ? const {
                    'schemaVersion': 1,
                    'state': 'unconfirmed',
                    'revision': 'missing',
                    'mode': 'online',
                    'realtimeStatus': 3,
                  }
                : const {},
          ),
        );
      });
      final account = ValueNotifier(
        const PresenceAccountScope(
          generation: 1,
          account: first,
          available: true,
        ),
      );
      final source = BridgeManualPresence(session, account);
      try {
        await Future<void>.delayed(Duration.zero);
        if (scenario == 'disposed') source.dispose();
        if (scenario == 'account-change') {
          account.value = const PresenceAccountScope(
            generation: 1,
            account: second,
            available: true,
          );
        }
        await Future<void>.delayed(
          Duration(milliseconds: scenario == 'persistent' ? 7600 : 1200),
        );
        expect(
          subjects.where((subject) => subject == 'first').length,
          scenario == 'persistent' ? 4 : 1,
        );
        if (scenario == 'account-change') {
          expect(subjects, ['first', 'second']);
          expect(source.value.selfKey, 'presence.invisible');
        }
        if (scenario == 'persistent') {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          expect(subjects, hasLength(4));
          expect(source.value.selfKey, 'presence.unknown');
        }
      } finally {
        source.dispose();
        account.dispose();
        await sub.cancel();
        await session.close();
        await pair.host.close();
      }
    });
  }
  test('transient SCM presence read recovers without another event', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    const owner = BridgeAccountContext(
      environment: 'test',
      authority: 'scm.invalid',
      subject: 'pilot',
    );
    var reads = 0;
    final sub = pair.host.incoming.listen((request) async {
      if (request.messageType != 'request') return;
      if (request.name != 'presence.read') {
        throw StateError('Recovery must not write.');
      }
      reads++;
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          sessionGeneration: request.sessionGeneration,
          correlationId: request.correlationId,
          accountContext: request.accountContext,
          status: reads == 1 ? 'error' : 'ok',
          error: reads == 1
              ? const BridgeErrorBody(
                  code: 'presence.unavailable',
                  message: 'Temporary',
                  retryable: true,
                )
              : null,
          payload: reads == 1
              ? const {}
              : const {
                  'schemaVersion': 1,
                  'state': 'unconfirmed',
                  'revision': 'missing',
                  'mode': 'online',
                  'realtimeStatus': 1,
                },
        ),
      );
    });
    final account = ValueNotifier(
      const PresenceAccountScope(
        generation: 1,
        account: owner,
        available: true,
      ),
    );
    final source = BridgeManualPresence(session, account);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(source.value.selfKey, 'presence.unknown');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(reads, 2);
      expect(source.value.selfKey, 'presence.online');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(reads, 2, reason: 'Recovery must not become a permanent poller.');
    } finally {
      source.dispose();
      account.dispose();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    }
  });
  test(
    'SCM heartbeat confirms display without publishing a saved mode',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      const owner = BridgeAccountContext(
        environment: 'test',
        authority: 'scm.invalid',
        subject: 'pilot',
      );
      int? status = 1;
      Completer<void>? hold;
      final calls = <String>[];
      final sub = pair.host.incoming.listen((request) async {
        if (request.messageType != 'request') return;
        calls.add(request.name);
        final captured = status;
        await hold?.future;
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            sessionGeneration: request.sessionGeneration,
            correlationId: request.correlationId,
            accountContext: request.accountContext,
            status: 'ok',
            payload: {
              'schemaVersion': 1,
              'state': 'unconfirmed',
              'revision': 'missing',
              'mode': 'online',
              'realtimeStatus': captured,
            },
          ),
        );
      });
      final account = ValueNotifier(
        const PresenceAccountScope(
          generation: 1,
          account: owner,
          available: true,
          automaticKey: 'presence.unknown',
        ),
      );
      final source = BridgeManualPresence(session, account);
      try {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(source.value.selfKey, 'presence.online');
        expect(source.value.confirmedMode, isNull);
        hold = Completer<void>();
        final delayed = hold;
        final oldRead = source.refresh();
        await Future<void>.delayed(Duration.zero);
        status = 3;
        source.invalidateRealtime();
        expect(source.value.selfKey, 'presence.unknown');
        hold = null;
        delayed.complete();
        await oldRead;
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(source.value.selfKey, 'presence.invisible');
        status = null;
        await source.refresh();
        expect(source.value.selfKey, 'presence.unknown');
        expect(calls.every((call) => call == 'presence.read'), isTrue);
      } finally {
        source.dispose();
        account.dispose();
        await sub.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );
  const owner = BridgeAccountContext(
    environment: 'test',
    authority: 'presence.invalid',
    subject: 'sample',
  );
  for (final acknowledged in [true, false]) {
    test(
      'shared source consumes real Bridge confirmation=$acknowledged',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        final requests = <BridgeEnvelope>[];
        var revision = 'missing';
        var mode = 'online';
        final subscription = pair.host.incoming.listen((r) async {
          if (r.messageType != 'request') return;
          requests.add(r);
          if (r.name == 'presence.set') {
            mode = r.payload['mode']! as String;
            revision = 'A' * 64;
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              sessionGeneration: r.sessionGeneration,
              correlationId: r.correlationId,
              accountContext: r.accountContext,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'state': r.name == 'presence.set' && !acknowledged
                    ? 'unconfirmed'
                    : 'ready',
                'revision': revision,
                'mode': mode,
              },
            ),
          );
        });
        final account = ValueNotifier(
          const PresenceAccountScope(
            generation: 1,
            account: owner,
            available: true,
            automaticKey: 'presence.online',
          ),
        );
        final source = BridgeManualPresence(session, account);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(source.value.selfKey, 'presence.online');
        await source.controller.select(PresenceVisibility.invisible);
        expect(
          source.value.confirmedMode,
          acknowledged ? PresenceVisibility.invisible : null,
        );
        expect(source.controller.failed, !acknowledged);
        expect(requests.map((r) => r.name), ['presence.read', 'presence.set']);
        expect(requests.last.payload['expectedRevision'], 'missing');
        expect(requests.last.accountContext!.subject, 'sample');
        account.value = const PresenceAccountScope(
          generation: 1,
          account: owner,
          available: true,
          automaticKey: 'presence.inGame',
        );
        expect(
          source.value.selfKey,
          acknowledged ? 'presence.invisible' : 'presence.unknown',
        );
        expect(requests.length, 2);
        account.value = const PresenceAccountScope(
          generation: 1,
          account: owner,
          available: false,
          automaticKey: 'presence.offline',
        );
        expect(
          source.value.selfKey,
          acknowledged ? 'presence.invisible' : 'presence.unknown',
        );
        expect(source.controller.canChange, false);
        source.dispose();
        account.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      },
    );
  }
  test('missing capability never requests or enables writes', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    var calls = 0;
    final sub = pair.host.incoming.listen((_) => calls++);
    final account = ValueNotifier(
      const PresenceAccountScope(
        generation: 1,
        account: owner,
        available: false,
      ),
    );
    final source = BridgeManualPresence(session, account);
    await source.refresh();
    await source.controller.select(PresenceVisibility.invisible);
    expect(calls, 0);
    expect(source.controller.canChange, false);
    source.dispose();
    account.dispose();
    await sub.cancel();
    await session.close();
    await pair.host.close();
  });
  test('changed account cannot receive a pending old result', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final request = Completer<BridgeEnvelope>();
    final sub = pair.host.incoming.listen((r) {
      if (r.messageType == 'request' && !request.isCompleted) {
        request.complete(r);
      }
    });
    final account = ValueNotifier(
      const PresenceAccountScope(
        generation: 1,
        account: owner,
        available: true,
      ),
    );
    final source = BridgeManualPresence(session, account);
    final old = await request.future;
    account.value = const PresenceAccountScope(
      generation: 2,
      account: null,
      available: false,
    );
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: old.name,
        sessionGeneration: 1,
        correlationId: old.correlationId,
        accountContext: owner,
        status: 'ok',
        payload: {
          'schemaVersion': 1,
          'state': 'ready',
          'revision': 'missing',
          'mode': 'invisible',
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.value.confirmedMode, null);
    expect(source.controller.canChange, false);
    source.dispose();
    account.dispose();
    await sub.cancel();
    await session.close();
    await pair.host.close();
  });
}
