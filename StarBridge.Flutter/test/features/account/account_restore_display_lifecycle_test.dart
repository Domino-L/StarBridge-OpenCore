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
    'a disconnected bridge still constructs a failed account module',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      );
      await session.close();
      AccountModule? account;
      try {
        account = createAccountModule(BridgeAccountAdapter(session));
        final result = await account.initialize();
        expect(result.outcome, AccountActionOutcome.failed);
        expect(account.projection.value.failure, isNotNull);
        expect(account.projection.value.profile, isNull);
        expect(account.projection.value.isSignedIn, isFalse);
      } finally {
        account?.dispose();
        await pair.host.close();
      }
    },
  );

  for (final invalid in [
    'root',
    'generation',
    'context',
    'schema',
    'schemaDouble',
    'unknown',
    'grant',
    'readId',
    'timestamp',
    'name',
  ]) {
    test(
      'invalid $invalid progress cannot expose a cache or settle the root',
      () async {
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        final original = (wire['prepared'] as Map).cast<String, Object?>();
        final payload = (original['payload'] as Map).cast<String, Object?>();
        final rootId = payload['rootCorrelationId']! as String;
        final changed =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        final body = changed['payload'] as Map;
        final retained = body['retainedDisplay'] as Map;
        switch (invalid) {
          case 'root':
            body['rootCorrelationId'] = 'another-physical-root';
          case 'generation':
            changed['sessionGeneration'] = 1;
          case 'context':
            changed['accountContext'] = {
              'environment': 'development',
              'authority': 'scm-development',
              'subject': 'synthetic-injected-owner',
            };
          case 'schema':
            body['schemaVersion'] = 2;
          case 'schemaDouble':
            body['schemaVersion'] = 1.0;
          case 'unknown':
            body['authenticated'] = true;
          case 'grant':
            retained['roles'] = ['administrator'];
          case 'readId':
            retained.remove('readId');
          case 'timestamp':
            retained['cachedAtUtc'] = '2099-01-01T00:00:00Z';
          case 'name':
            retained['displayName'] = 'x' * 257;
        }
        final pair = InMemoryBridgeConnection.createPair();
        var counter = 0;
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
          correlationIdFactory: () =>
              counter++ == 0 ? rootId : 'invalid-$counter',
        );
        session.acceptHostCapabilities(['account.restoreDisplay']);
        final account = createAccountModule(BridgeAccountAdapter(session));
        final request = Completer<BridgeEnvelope>();
        final subscription = pair.host.incoming.listen((frame) {
          if (frame.name == 'account.getCurrent' && !request.isCompleted) {
            request.complete(frame);
          }
        });
        var finished = false;
        final pending = account.initialize().whenComplete(
          () => finished = true,
        );
        final root = await request.future;
        try {
          await pair.host.send(BridgeEnvelope.fromJson(changed));
          await Future<void>.delayed(Duration.zero);
          expect(account.projection.value.retainedReadId, isNull);
          expect(account.projection.value.profile, isNull);
          expect(account.projection.value.isPreparingDisplay, isFalse);
          expect(account.projection.value.isSignedIn, isFalse);
          expect(finished, isFalse);
          // Invalid progress is ignored; the same live root can still recover.
          await pair.host.send(
            BridgeEnvelope.fromJson({
              ...original,
              'sequence': (original['sequence']! as int) + 1,
            }),
          );
          await Future<void>.delayed(Duration.zero);
          expect(account.projection.value.isPreparingDisplay, isTrue);
          expect(account.projection.value.canEditPreferences, isFalse);
        } finally {
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: root.name,
              correlationId: root.correlationId,
              sessionGeneration: 0,
              status: 'cancelled',
              payload: const {},
            ),
          );
          await pending;
          expect(account.projection.value.retainedReadId, isNull);
          expect(account.projection.value.isPreparingDisplay, isFalse);
          expect(account.projection.value.profile, isNull);
          account.dispose();
          await subscription.cancel();
          await session.close();
          await pair.host.close();
        }
      },
      skip: _path.isEmpty
          ? 'Requires actual Native restore-display wire.'
          : false,
    );
  }

  test('loading alone cannot carry a retained read across completion or generation', () {
    const display = AccountProjection(
      sessionState: AccountSessionState.loading,
      operation: AccountOperation.refreshing,
      generation: 0,
      profileFreshness: AccountProfileFreshness.cached,
      profile: AccountProfile(displayName: 'Synthetic pilot'),
      retainedReadId: '0123456789abcdef0123456789abcdef',
      identity: AccountIdentityProjection.unavailable(),
      compatibility: AccountCompatibilityProjection.unavailable(),
      localeOptions: [],
      timeZoneOptions: [],
    );
    expect(display.hasRetainedDisplayRead, isFalse);
    expect(display.copyWith().retainedReadId, isNull);
  });
}
