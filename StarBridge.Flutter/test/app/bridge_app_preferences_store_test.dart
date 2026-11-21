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
  _holidayAppearanceTests();
  _performanceModeTests();
  _readOwnHealthTests();
  _readOwnHealthInBackgroundTests();
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

// 读取自己的血量：单独开关，默认关。旧 Host 不带这个字段时按关；改动时只发这一个字段。
void _readOwnHealthTests() {
  test('readOwnHealth: missing reads as false, true reads as true', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final updateRequest = Completer<BridgeEnvelope>();
    var reads = 0;
    unawaited(
      pair.host.incoming.forEach((request) async {
        Map<String, Object?> payload(int revision, bool? value) {
          final p = _payload(
            revision: revision,
            localeOverride: null,
            appearanceMode: 'dark',
            motionPreference: 'followSystem',
            storageState: 'ready',
          );
          if (value != null) {
            p['preferences'] = Map<String, Object?>.from(
              p['preferences'] as Map,
            )..['readOwnHealth'] = value;
          }
          return p;
        }

        if (request.name == 'applicationPreferences.get') {
          await pair.host.send(_ok(request, payload(1, reads++ > 0 ? true : null)));
          return;
        }
        if (request.name == 'applicationPreferences.update') {
          updateRequest.complete(request);
          await pair.host.send(_ok(request, payload(2, true)));
        }
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final store = BridgeAppPreferencesStore(session);

    final missing = await store.read();
    expect(missing.values.readOwnHealth, isFalse);
    final explicit = await store.read();
    expect(explicit.values.readOwnHealth, isTrue);

    final updated = await store.update(
      const AppPreferencesPatch.readOwnHealth(true),
      expectedRevision: 1,
    );
    final request = await updateRequest.future;
    expect(request.payload['patch'], {'readOwnHealth': true});
    expect(updated.values.readOwnHealth, isTrue);
    expect(
      const AppPreferencesPatch.holidayAppearance(false).readOwnHealth,
      isNull,
    );
    expect(const AppPreferencesPatch.readOwnHealth(false).isEmpty, isFalse);
    expect(AppPreferences.defaults.readOwnHealth, isFalse);

    store.dispose();
    await session.close();
    await pair.host.close();
  });

  test('readOwnHealth: a non-boolean value from the Host is rejected', () async {
    final pair = InMemoryBridgeConnection.createPair();
    unawaited(
      pair.host.incoming.forEach((request) async {
        final p = _payload(
          revision: 1,
          localeOverride: null,
          appearanceMode: 'dark',
          motionPreference: 'followSystem',
          storageState: 'ready',
        );
        p['preferences'] = Map<String, Object?>.from(p['preferences'] as Map)
          ..['readOwnHealth'] = 'yes';
        await pair.host.send(_ok(request, p));
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final store = BridgeAppPreferencesStore(session);
    await expectLater(
      store.read(),
      throwsA(isA<AppPreferencesStoreException>()),
    );
    store.dispose();
    await session.close();
    await pair.host.close();
  });
}

// 游戏在后台时也读取：读血的子开关，默认关（用户 11-13）。b93 的 Host 不带这个字段时按关；改动时只发这一个字段。
void _readOwnHealthInBackgroundTests() {
  Map<String, Object?> payload(int revision, Object? value, {bool include = true}) {
    final p = _payload(
      revision: revision,
      localeOverride: null,
      appearanceMode: 'dark',
      motionPreference: 'followSystem',
      storageState: 'ready',
    );
    if (include) {
      p['preferences'] = Map<String, Object?>.from(p['preferences'] as Map)
        ..['readOwnHealthInBackground'] = value;
    }
    return p;
  }

  test('readOwnHealthInBackground: missing reads as false, true reads as true', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final updateRequest = Completer<BridgeEnvelope>();
    var reads = 0;
    unawaited(
      pair.host.incoming.forEach((request) async {
        if (request.name == 'applicationPreferences.get') {
          await pair.host.send(
            _ok(request, reads++ > 0 ? payload(1, true) : payload(1, null, include: false)),
          );
          return;
        }
        if (request.name == 'applicationPreferences.update') {
          updateRequest.complete(request);
          await pair.host.send(_ok(request, payload(2, true)));
        }
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final store = BridgeAppPreferencesStore(session);

    final missing = await store.read();
    expect(missing.values.readOwnHealthInBackground, isFalse);
    final explicit = await store.read();
    expect(explicit.values.readOwnHealthInBackground, isTrue);

    final updated = await store.update(
      const AppPreferencesPatch.readOwnHealthInBackground(true),
      expectedRevision: 1,
    );
    final request = await updateRequest.future;
    expect(request.payload['patch'], {'readOwnHealthInBackground': true});
    expect(updated.values.readOwnHealthInBackground, isTrue);
    expect(const AppPreferencesPatch.readOwnHealth(true).readOwnHealthInBackground, isNull);
    expect(const AppPreferencesPatch.readOwnHealthInBackground(true).readOwnHealth, isNull);
    expect(const AppPreferencesPatch.readOwnHealthInBackground(false).isEmpty, isFalse);
    expect(AppPreferences.defaults.readOwnHealthInBackground, isFalse);

    store.dispose();
    await session.close();
    await pair.host.close();
  });

  for (final bad in <Object?>['yes', null, 1]) {
    test('readOwnHealthInBackground: $bad from the Host is rejected', () async {
      final pair = InMemoryBridgeConnection.createPair();
      unawaited(
        pair.host.incoming.forEach((request) async {
          await pair.host.send(_ok(request, payload(1, bad)));
        }),
      );
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final store = BridgeAppPreferencesStore(session);
      await expectLater(
        store.read(),
        throwsA(isA<AppPreferencesStoreException>()),
      );
      store.dispose();
      await session.close();
      await pair.host.close();
    });
  }
}

// 节日外观：旧 Host 不带这个字段时按默认开；带了就照读；改动时只发这一个字段。
void _holidayAppearanceTests() {
  test(
    'holidayAppearance: missing reads as true, false reads as false',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final updateRequest = Completer<BridgeEnvelope>();
      var reads = 0;
      unawaited(
        pair.host.incoming.forEach((request) async {
          if (request.name == 'applicationPreferences.get') {
            final payload = _payload(
              revision: 1,
              localeOverride: null,
              appearanceMode: 'dark',
              motionPreference: 'followSystem',
              storageState: 'ready',
            );
            if (reads++ > 0) {
              payload['preferences'] = Map<String, Object?>.from(
                payload['preferences'] as Map,
              )..['holidayAppearance'] = false;
            }
            await pair.host.send(_ok(request, payload));
            return;
          }
          if (request.name == 'applicationPreferences.update') {
            updateRequest.complete(request);
            final payload = _payload(
              revision: 2,
              localeOverride: null,
              appearanceMode: 'dark',
              motionPreference: 'followSystem',
              storageState: 'ready',
            );
            payload['preferences'] = Map<String, Object?>.from(
              payload['preferences'] as Map,
            )..['holidayAppearance'] = false;
            await pair.host.send(_ok(request, payload));
          }
        }),
      );
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final store = BridgeAppPreferencesStore(session);

      final missing = await store.read();
      expect(missing.values.holidayAppearance, isTrue);
      final explicit = await store.read();
      expect(explicit.values.holidayAppearance, isFalse);

      final updated = await store.update(
        const AppPreferencesPatch.holidayAppearance(false),
        expectedRevision: 1,
      );
      final request = await updateRequest.future;
      expect(request.payload['patch'], {'holidayAppearance': false});
      expect(updated.values.holidayAppearance, isFalse);
      // 其他改动不会顺带发这个字段。
      expect(
        const AppPreferencesPatch.motion(MotionPreference.reduce)
            .holidayAppearance,
        isNull,
      );
      expect(
        const AppPreferencesPatch.holidayAppearance(true).isEmpty,
        isFalse,
      );

      store.dispose();
      await session.close();
      await pair.host.close();
    },
  );
}

// 性能模式：旧 Host 不带这个字段时按默认关（用户 11-10）；带了就照读；改动时只发这一个字段。
void _performanceModeTests() {
  test('performanceMode: missing reads as false, true reads as true', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final updateRequest = Completer<BridgeEnvelope>();
    var reads = 0;
    unawaited(
      pair.host.incoming.forEach((request) async {
        if (request.name == 'applicationPreferences.get') {
          final payload = _payload(
            revision: 1,
            localeOverride: null,
            appearanceMode: 'dark',
            motionPreference: 'followSystem',
            storageState: 'ready',
          );
          if (reads++ > 0) {
            payload['preferences'] = Map<String, Object?>.from(
              payload['preferences'] as Map,
            )..['performanceMode'] = true;
          }
          await pair.host.send(_ok(request, payload));
          return;
        }
        if (request.name == 'applicationPreferences.update') {
          updateRequest.complete(request);
          final payload = _payload(
            revision: 2,
            localeOverride: null,
            appearanceMode: 'dark',
            motionPreference: 'followSystem',
            storageState: 'ready',
          );
          payload['preferences'] = Map<String, Object?>.from(
            payload['preferences'] as Map,
          )..['performanceMode'] = true;
          await pair.host.send(_ok(request, payload));
        }
      }),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final store = BridgeAppPreferencesStore(session);

    final missing = await store.read();
    expect(missing.values.performanceMode, isFalse);
    final explicit = await store.read();
    expect(explicit.values.performanceMode, isTrue);

    final updated = await store.update(
      const AppPreferencesPatch.performanceMode(true),
      expectedRevision: 1,
    );
    final request = await updateRequest.future;
    expect(request.payload['patch'], {'performanceMode': true});
    expect(updated.values.performanceMode, isTrue);
    // 其他改动不会顺带发这个字段。
    expect(
      const AppPreferencesPatch.motion(MotionPreference.reduce).performanceMode,
      isNull,
    );
    expect(const AppPreferencesPatch.performanceMode(true).isEmpty, isFalse);

    store.dispose();
    await session.close();
    await pair.host.close();
  });
  // 显式的 null、字符串、数字都要报错；显式 false 照读（复审 CX-PERF-MODE-073-REVIEW P2）。
  test('performanceMode: explicit null, text or number is rejected; false reads false', () async {
    for (final value in <Object?>[null, 'true', 1, false]) {
      final pair = InMemoryBridgeConnection.createPair();
      unawaited(
        pair.host.incoming.forEach((request) async {
          final payload = _payload(
            revision: 1,
            localeOverride: null,
            appearanceMode: 'dark',
            motionPreference: 'followSystem',
            storageState: 'ready',
          );
          payload['preferences'] = Map<String, Object?>.from(
            payload['preferences'] as Map,
          )..['performanceMode'] = value;
          await pair.host.send(_ok(request, payload));
        }),
      );
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 9,
      );
      final store = BridgeAppPreferencesStore(session);
      if (value == false) {
        expect((await store.read()).values.performanceMode, isFalse);
      } else {
        await expectLater(store.read(), throwsA(anything), reason: '$value');
      }
      store.dispose();
      await session.close();
      await pair.host.close();
    }
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
