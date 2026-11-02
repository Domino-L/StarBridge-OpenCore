import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');

void main() {
  test(
    'a delayed own generation event cannot turn the old root into a signed-in snapshot',
    () async {
      final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
      BridgeEnvelope native(String key) =>
          BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
      final prepared = native('prepared'), completed = native('completed');
      final pair = InMemoryBridgeConnection.createPair();
      var index = 0;
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
        correlationIdFactory: () =>
            index++ == 0 ? completed.correlationId! : 'delayed-$index',
      );
      session.acceptHostCapabilities([
        'account.restoreDisplay',
        'profile.stagedRead',
      ]);
      final account = createAccountModule(BridgeAccountAdapter(session));
      final root = Completer<void>(), fresh = Completer<void>();
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'account.getCurrent') {
          if (!root.isCompleted) {
            root.complete();
          } else {
            final payload = {...completed.payload}
              ..remove('restoreDisplayReadId');
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: request.sessionGeneration,
                  accountContext: completed.accountContext,
                  status: 'ok',
                  payload: payload,
                ),
              ),
            );
          }
        }
        if (request.name == 'profile.readDisplayCache') {
          if (request.sessionGeneration == 0) {
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: 0,
                  status: 'error',
                  payload: const {},
                  error: const BridgeErrorBody(
                    code: 'bridge.stale_generation',
                    message: 'Native already advanced',
                    retryable: false,
                  ),
                ),
              ),
            );
          } else if (!fresh.isCompleted) {
            fresh.complete();
          }
        }
      });
      final pending = account.initialize();
      await root.future;
      try {
        await pair.host.send(prepared);
        await Future<void>.delayed(Duration.zero);
        await pair.host.send(completed);
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(account.projection.value.isSignedIn, isFalse);
        expect(
          account.projection.value.profile?.displayName,
          'Synthetic Cold Pilot',
        );
        expect(
          requests.where((r) => r.name == 'profile.readDisplayCache'),
          isEmpty,
        );
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 1,
            sequence: prepared.sequence! + 1,
            payload: const {'schemaVersion': 1},
          ),
        );
        await fresh.future.timeout(const Duration(seconds: 2));
        expect(
          account.projection.value.profile?.displayName,
          'Synthetic Cold Pilot',
        );
        expect(account.projection.value.retainedReadId, isNull);
      } finally {
        account.dispose();
        await session.close();
        await pending;
        await subscription.cancel();
        await pair.host.close();
      }
    },
    skip: _path.isEmpty
        ? 'Requires actual Native restore-display wire.'
        : false,
  );

  for (final boundary in [
    'missingProof',
    'wrongProof',
    'otherOwner',
    'skippedGeneration',
    'mode',
    'directGeneration',
    'bootstrap',
    'disconnect',
    'rejected',
    'lateMetadata',
  ]) {
    test(
      '$boundary withdraws materialized display and never revives a read ID',
      () async {
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        BridgeEnvelope native(String key) =>
            BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
        final prepared = native('prepared'), completed = native('completed');
        final pair = InMemoryBridgeConnection.createPair();
        var counter = 0;
        final rootId = prepared.payload['rootCorrelationId']! as String;
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
          correlationIdFactory: () =>
              counter++ == 0 ? rootId : 'negative-$counter',
        );
        session.acceptHostCapabilities([
          'account.restoreDisplay',
          'profile.stagedRead',
        ]);
        final account = createAccountModule(BridgeAccountAdapter(session));
        final root = Completer<BridgeEnvelope>(),
            metadata = Completer<BridgeEnvelope>();
        final subscription = pair.host.incoming.listen((request) {
          if (request.name == 'account.getCurrent') {
            if (!root.isCompleted) {
              root.complete(request);
            } else {
              final signedOut =
                  boundary == 'lateMetadata' && request.sessionGeneration >= 2;
              final original = completed.accountContext!;
              final owner = boundary == 'otherOwner'
                  ? BridgeAccountContext(
                      environment: original.environment,
                      authority: original.authority,
                      subject: 'synthetic-other-owner',
                    )
                  : original;
              final payload = {...completed.payload}
                ..remove('restoreDisplayReadId');
              unawaited(
                pair.host.send(
                  BridgeEnvelope(
                    protocolVersion: 1,
                    messageType: 'response',
                    name: request.name,
                    correlationId: request.correlationId,
                    sessionGeneration: request.sessionGeneration,
                    accountContext: signedOut ? null : owner,
                    status: 'ok',
                    payload: signedOut
                        ? const {'schemaVersion': 1, 'state': 'signedOut'}
                        : payload,
                  ),
                ),
              );
            }
          }
          if (request.name == 'profile.readDisplayCache' &&
              request.sessionGeneration > 0 &&
              !metadata.isCompleted) {
            metadata.complete(request);
          }
        });
        final pending = account.initialize();
        await root.future;
        try {
          await pair.host.send(prepared);
          await Future<void>.delayed(Duration.zero);
          expect(account.projection.value.profile, isNotNull);
          final payload = {...completed.payload};
          if (boundary == 'missingProof') {
            payload.remove('restoreDisplayReadId');
          }
          if (boundary == 'wrongProof') {
            payload['restoreDisplayReadId'] = 'a' * 32;
          }
          if (boundary == 'rejected') {
            payload['state'] = 'reauthorizationRequired';
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: completed.name,
              correlationId: completed.correlationId,
              sessionGeneration: 0,
              accountContext: boundary == 'rejected'
                  ? null
                  : completed.accountContext,
              status: 'ok',
              payload: payload,
            ),
          );
          if (boundary == 'rejected') {
            await pending;
          } else {
            final next = boundary == 'skippedGeneration' ? 2 : 1;
            await pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'account.changed',
                sessionGeneration: next,
                sequence: prepared.sequence! + 1,
                payload: const {'schemaVersion': 1},
              ),
            );
            await metadata.future.timeout(const Duration(seconds: 2));
            if (const {
              'mode',
              'directGeneration',
              'bootstrap',
              'disconnect',
              'lateMetadata',
            }.contains(boundary)) {
              expect(account.projection.value.hasDisplayHandoff, isTrue);
            }
            if (boundary == 'mode') {
              await session.runConnectionModeChange(() async {});
            }
            if (boundary == 'directGeneration') session.advanceGeneration(2);
            if (boundary == 'disconnect') await session.close();
            if (boundary == 'bootstrap' || boundary == 'lateMetadata') {
              await pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'event',
                  name: boundary == 'bootstrap'
                      ? 'bootstrap.invalidated'
                      : 'account.changed',
                  sessionGeneration: boundary == 'bootstrap' ? 1 : 2,
                  sequence: prepared.sequence! + 2,
                  payload: const {'schemaVersion': 1},
                ),
              );
            }
            if (boundary == 'lateMetadata') {
              final old = await metadata.future;
              await pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: old.name,
                  correlationId: old.correlationId,
                  sessionGeneration: old.sessionGeneration,
                  accountContext: completed.accountContext,
                  status: 'ok',
                  payload: {
                    'schemaVersion': 1,
                    'source': 'cache',
                    'cachedAtUtc': '2026-10-01T00:00:00Z',
                    'profile': {'displayName': 'Do not revive old owner'},
                    'preferencesPolicy': {
                      'locales': [],
                      'timeZones': [],
                      'availableActions': [],
                    },
                  },
                ),
              );
            }
          }
          await Future<void>.delayed(Duration.zero);
          expect(account.projection.value.hasDisplayHandoff, isFalse);
          expect(account.projection.value.retainedReadId, isNull);
          expect(account.projection.value.profile, isNull);
          expect(account.projection.value.canEditPreferences, isFalse);
        } finally {
          account.dispose();
          await session.close();
          await pending;
          await subscription.cancel();
          await pair.host.close();
        }
      },
      skip: _path.isEmpty
          ? 'Requires actual Native restore-display wire.'
          : false,
    );
  }

  test(
    'actual successful root keeps readonly presentation through its queued generation',
    () async {
      final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
      BridgeEnvelope native(String key) =>
          BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
      final prepared = native('prepared'), completed = native('completed');
      final rootId = prepared.payload['rootCorrelationId']! as String;
      final pair = InMemoryBridgeConnection.createPair();
      var counter = 0;
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
        correlationIdFactory: () =>
            counter++ == 0 ? rootId : 'handoff-$counter',
      );
      session.acceptHostCapabilities([
        'account.restoreDisplay',
        'profile.stagedRead',
      ]);
      final account = createAccountModule(BridgeAccountAdapter(session));
      final root = Completer<BridgeEnvelope>();
      final heldMetadata = Completer<BridgeEnvelope>();
      final subscription = pair.host.incoming.listen((request) {
        if (request.name == 'account.getCurrent') {
          if (!root.isCompleted) {
            root.complete(request);
          } else {
            // Hot-root fixture, with actual successful Native identity fields.
            final payload = {...completed.payload}
              ..remove('restoreDisplayReadId');
            unawaited(
              pair.host.send(
                BridgeEnvelope(
                  protocolVersion: 1,
                  messageType: 'response',
                  name: request.name,
                  correlationId: request.correlationId,
                  sessionGeneration: request.sessionGeneration,
                  accountContext: completed.accountContext,
                  status: 'ok',
                  payload: payload,
                ),
              ),
            );
          }
        }
        if (request.name == 'profile.readDisplayCache' &&
            request.sessionGeneration == 1 &&
            !heldMetadata.isCompleted) {
          heldMetadata.complete(request);
        }
      });
      var settled = false;
      final pending = account.initialize().whenComplete(() => settled = true);
      await root.future;
      try {
        await pair.host.send(prepared);
        await Future<void>.delayed(Duration.zero);
        final displayName = account.projection.value.profile!.displayName;
        await pair.host.send(completed);
        // Native guarantees response-before-event; this event's finite schema /
        // generation shape follows AccountBridgeDispatcher.OnAccountChanged.
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 1,
            sequence: prepared.sequence! + 1,
            payload: const {'schemaVersion': 1},
          ),
        );
        await heldMetadata.future.timeout(const Duration(seconds: 2));
        final current = account.projection.value;
        expect(current.profile?.displayName, displayName);
        expect(current.profileFreshness, AccountProfileFreshness.cached);
        expect(current.retainedReadId, isNull);
        expect(current.generation, 1);
        expect(current.isSignedIn, isFalse);
        expect(current.canEditPreferences, isFalse);
        expect(settled, isFalse);
      } finally {
        account.dispose();
        await session.close();
        await pending;
        await subscription.cancel();
        await pair.host.close();
      }
    },
    skip: _path.isEmpty
        ? 'Requires actual Native restore-display wire.'
        : false,
  );
}
