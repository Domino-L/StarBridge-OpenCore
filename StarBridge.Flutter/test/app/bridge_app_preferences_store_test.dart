import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/bridge_app_preferences.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('reads and patches device settings without account context', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final updateRequest = Completer<BridgeEnvelope>();
    unawaited(
      pair.host.incoming.forEach((request) async {
        if (request.name == 'applicationPreferences.get') {
          await pair.host.send(
            _ok(
              request,
              _payload(
                revision: 5,
                localeOverride: null,
                appearanceMode: 'dark',
                motionPreference: 'followSystem',
                storageState: 'ready',
              ),
            ),
          );
          return;
        }
        if (request.name == 'applicationPreferences.update') {
          updateRequest.complete(request);
          await pair.host.send(
            _ok(
              request,
              _payload(
                revision: 6,
                localeOverride: null,
                appearanceMode: 'light',
                motionPreference: 'followSystem',
                storageState: 'ready',
              ),
            ),
          );
        }
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final store = BridgeAppPreferencesStore(session);

    final initial = await store.read();
    expect(initial.revision, 5);
    expect(initial.values.localeOverride, isNull);

    final updated = await store.update(
      const AppPreferencesPatch.appearance(AppearanceMode.light),
      expectedRevision: 5,
    );
    final request = await updateRequest.future;
    expect(request.accountContext, isNull);
    expect(request.payload['expectedRevision'], 5);
    expect(request.payload['patch'], {'appearanceMode': 'light'});
    expect(updated.revision, 6);
    expect(updated.values.appearanceMode, AppearanceMode.light);

    store.dispose();
    await session.close();
    await pair.host.close();
  });

  test('maps a Host save failure to the typed settings boundary', () async {
    final pair = InMemoryBridgeConnection.createPair();
    unawaited(
      pair.host.incoming.forEach((request) async {
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: const {},
            status: 'error',
            error: const BridgeErrorBody(
              code: 'applicationPreferences.save_failed',
              message: 'Synthetic failure.',
              retryable: true,
            ),
          ),
        );
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final store = BridgeAppPreferencesStore(session);

    await expectLater(
      store.update(
        const AppPreferencesPatch.motion(MotionPreference.reduce),
        expectedRevision: 2,
      ),
      throwsA(
        isA<AppPreferencesStoreException>()
            .having(
              (error) => error.failure,
              'failure',
              AppPreferencesFailure.saveFailed,
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );

    await session.close();
    await pair.host.close();
  });
}

Map<String, Object?> _payload({
  required int revision,
  required String? localeOverride,
  required String appearanceMode,
  required String motionPreference,
  required String storageState,
}) {
  return {
    'schemaVersion': 1,
    'revision': revision,
    'storageState': storageState,
    'preferences': {
      'localeOverride': localeOverride,
      'appearanceMode': appearanceMode,
      'motionPreference': motionPreference,
    },
  };
}

BridgeEnvelope _ok(BridgeEnvelope request, Map<String, Object?> payload) {
  return BridgeEnvelope(
    protocolVersion: 1,
    messageType: 'response',
    name: request.name,
    correlationId: request.correlationId,
    sessionGeneration: request.sessionGeneration,
    payload: payload,
    status: 'ok',
  );
}
