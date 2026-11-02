import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');
const _skip = _path == ''
    ? 'Requires actual Native restore-display wire.'
    : false;
Map<String, dynamic> _wire() =>
    jsonDecode(File(_path).readAsStringSync()) as Map<String, dynamic>;
BridgeEnvelope _frame(Map<String, dynamic> wire, String key) =>
    BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());

void main() {
  test(
    'pending root publishes cached profile metadata without resolving account',
    () async {
      final wire = _wire();
      final prepared = _frame(wire, 'prepared');
      final rootId = prepared.payload['rootCorrelationId']! as String;
      var index = 0;
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
        correlationIdFactory: () =>
            index++ == 0 ? rootId : 'display-child-$index',
      );
      session.acceptHostCapabilities([
        'account.restoreDisplay',
        'account.offlineData.read',
      ]);
      final module = createAccountModule(BridgeAccountAdapter(session));
      final root = Completer<BridgeEnvelope>();
      final subscription = pair.host.incoming.listen((request) {
        if (request.name == 'account.getCurrent' && !root.isCompleted) {
          root.complete(request);
        }
        if (request.name == 'account.offlineData.read') {
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: request.sessionGeneration,
                status: 'ok',
                payload: _frame(wire, 'cachedProfile').payload,
              ),
            ),
          );
        }
      });
      var finished = false;
      final pending = module.initialize().whenComplete(() => finished = true);
      final request = await root.future;
      try {
        expect(request.payload['restoreDisplayProgress'], isTrue);
        final observed = session.events.firstWhere(
          (e) => e.name == prepared.name,
        );
        await pair.host.send(prepared);
        await observed;
        await Future<void>.delayed(Duration.zero);
        final current = module.projection.value;
        final retained = prepared.payload['retainedDisplay']! as Map;
        expect(current.profile?.displayName, retained['displayName']);
        expect(current.retainedReadId, retained['readId']);
        expect(current.profileFreshness, AccountProfileFreshness.cached);
        expect(current.sessionState, AccountSessionState.loading);
        expect(current.isBusy, isTrue);
        expect(current.canEditPreferences, isFalse);
        expect(current.canLogout, isFalse);
        expect(finished, isFalse);
        final profile = await session.request(
          'account.offlineData.read',
          payload: {
            'schemaVersion': 1,
            'readId': current.retainedReadId,
            'kind': 'profile',
          },
        );
        expect(
          (profile.payload['content'] as Map)['introduction'],
          'Stored cold introduction',
        );
      } finally {
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 0,
            payload: const {},
            status: 'cancelled',
          ),
        );
        await pending;
        module.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
    skip: _skip,
  );

  test(
    'actual preparing display is finite metadata with no account authority',
    () {
      final wire = _wire();
      final prepared = _frame(wire, 'prepared');
      final completed = _frame(wire, 'completed');
      expect(wire['nativeFirstContentObserved'], isTrue);
      expect(wire['frontendAcceptance'], isFalse);
      expect(prepared.name, 'account.restoreDisplay');
      expect(prepared.messageType, 'event');
      expect(prepared.accountContext, isNull);
      expect(prepared.payload['rootCorrelationId'], completed.correlationId);
      final display = AccountPayloadDecoder.retainedDisplay(
        prepared,
        AccountSessionState.credentialTemporarilyUnavailable,
      )!;
      expect(display.profile.email, isNull);
      expect(display.profile.locale, isNull);
      expect(display.readId, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(completed.payload['restoreDisplayReadId'], display.readId);
      expect(
        AccountPayloadDecoder.sessionState(completed.payload),
        AccountSessionState.signedIn,
      );
      expect(_frame(wire, 'cachedProfile').accountContext, isNull);
    },
    skip: _skip,
  );

  test(
    'actual progress cannot complete startup or authorize the pending account',
    () async {
      final prepared = _frame(_wire(), 'prepared');
      final rootId = prepared.payload['rootCorrelationId']! as String;
      var counter = 0;
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: prepared.sessionGeneration,
        correlationIdFactory: () =>
            counter++ == 0 ? rootId : 'restore-child-$counter',
      );
      final module = createAccountModule(BridgeAccountAdapter(session));
      final startup = StartupSession()..markPresented();
      final root = Completer<BridgeEnvelope>();
      final subscription = pair.host.incoming.listen((request) {
        if (request.name == 'account.getCurrent' && !root.isCompleted) {
          root.complete(request);
        }
      });
      var finished = false;
      final pending = module.initialize().whenComplete(() => finished = true);
      final request = await root.future;
      try {
        final observed = session.events.firstWhere(
          (e) => e.name == prepared.name,
        );
        await pair.host.send(prepared);
        await observed;
        await Future<void>.delayed(Duration.zero);
        final current = module.projection.value;
        expect(current.isSignedIn, isFalse);
        expect(current.canLogin, isFalse);
        expect(current.canLogout, isFalse);
        expect(current.canEditPreferences, isFalse);
        expect(current.isBusy, isTrue);
        expect(finished, isFalse);
        startup.resolveAccount(current);
        expect(startup.value, StartupPhase.account);
        expect(session.activeGeneration, prepared.sessionGeneration);
        expect(
          () => session.request('profile.getSelf'),
          throwsA(isA<BridgeAccountContextRequiredException>()),
        );
      } finally {
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: const {},
            status: 'cancelled',
          ),
        );
        await pending;
        startup.dispose();
        module.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
    skip: _skip,
  );
}
