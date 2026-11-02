import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';

const _path = String.fromEnvironment('STARBRIDGE_RESTORE_DISPLAY_WIRE');
const _capabilitiesPath = String.fromEnvironment(
  'STARBRIDGE_STARTUP_CAPABILITIES',
);

final class _Host implements NativeHostLease {
  _Host(this.prepared, List<String> capabilities) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: prepared.sessionGeneration,
      correlationIdFactory: () {
        final id = 'startup-order-${callStacks.length}';
        callStacks[id] = StackTrace.current;
        return id;
      },
    )..acceptHostCapabilities(capabilities);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        if (!root.isCompleted) root.complete(request);
        return; // The complete authentication result remains physically held.
      }
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'error',
          payload: const {},
          error: const BridgeErrorBody(
            code: 'fixture.unavailable',
            message: 'No domain data in this startup-order fixture',
            retryable: false,
          ),
        ),
      );
    });
  }

  final BridgeEnvelope prepared;
  final pair = InMemoryBridgeConnection.createPair();
  final requests = <BridgeEnvelope>[];
  final callStacks = <String, StackTrace>{};
  final root = Completer<BridgeEnvelope>();
  final termination = Completer<NativeHostTermination>();
  late final StreamSubscription<BridgeEnvelope> subscription;
  @override
  late final BridgeClientSession session;
  @override
  Future<NativeHostTermination> get terminated => termination.future;
  bool closed = false;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }

  Future<void> progress(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: prepared.protocolVersion,
      messageType: prepared.messageType,
      name: prepared.name,
      sessionGeneration: prepared.sessionGeneration,
      sequence: prepared.sequence,
      payload: {
        ...prepared.payload,
        // Only transport correlation is rebound; Native cached data is intact.
        'rootCorrelationId': request.correlationId,
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scope in ['displayOnly', 'inbox', 'scenes', 'advertised']) {
    test(
      'connected product requests cached display before competing startup reads; $scope',
      () async {
        final wire = jsonDecode(File(_path).readAsStringSync()) as Map;
        final prepared = BridgeEnvelope.fromJson(
          (wire['prepared'] as Map).cast<String, Object?>(),
        );
        final capabilities = scope == 'advertised'
            ? (jsonDecode(File(_capabilitiesPath).readAsStringSync()) as List)
                  .cast<String>()
            : [
                'account.restoreDisplay',
                if (scope == 'inbox') 'notificationInbox.read',
                if (scope == 'scenes') 'overlayScenes.read',
              ];
        final host = _Host(prepared, capabilities);
        final preferences = InMemoryAppPreferences();
        final composition = AppComposition.forConnectedProduct(
          nativeHost: host,
          preferences: preferences,
        );
        addTearDown(() async {
          composition.dispose();
          await host.close();
          preferences.dispose();
        });
        final root = await host.root.future;
        expect(
          root.payload['restoreDisplayProgress'],
          isTrue,
          reason: 'First root caller: ${host.callStacks[root.correlationId]}',
        );
        final shown = Completer<void>();
        void observe() {
          if (composition.account.projection.value.isPreparingDisplay &&
              !shown.isCompleted) {
            shown.complete();
          }
        }

        composition.account.projection.addListener(observe);
        addTearDown(
          () => composition.account.projection.removeListener(observe),
        );
        await host.progress(root);
        await shown.future.timeout(const Duration(seconds: 2));
        final display = composition.account.projection.value;
        expect(display.isPreparingDisplay, isTrue);
        expect(display.sessionState, AccountSessionState.loading);
        expect(display.profileFreshness, AccountProfileFreshness.cached);
        expect(display.profile, isNotNull);
        expect(display.isSignedIn, isFalse);
        expect(
          host.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(1),
        );
      },
      skip: _path.isEmpty || scope == 'advertised' && _capabilitiesPath.isEmpty
          ? 'Requires Native wire and advertised-capabilities source fixture'
          : false,
    );
  }
}
