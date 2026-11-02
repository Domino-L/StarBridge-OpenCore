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

void main() {
  const path = String.fromEnvironment('STARBRIDGE_ACCOUNT_PROFILE_WIRE');
  final skip = path.isEmpty
      ? 'Requires the actual Runtime account-profile cache fixture.'
      : false;
  for (final phase in [
    'forbidden',
    'invalid',
    'unavailable',
    'internalError',
  ]) {
    test(
      'Native $phase removes old account profile without losing the same-owner draft',
      () async {
        final host = await AccountProfileWireHost.create(path);
        final module = host.module();
        addTearDown(() async {
          module.dispose();
          await host.close();
        });
        await module.initialize();
        expect(module.projection.value.canEditPreferences, isTrue);
        module.preferencesDraft.setLocale('en-US');
        host.phase = phase;
        await module.refresh();
        expect(module.projection.value.profile, isNull);
        expect(module.projection.value.canEditPreferences, isFalse);
        expect(module.projection.value.isSignedIn, isTrue);
        expect(module.preferencesDraft.locale, 'en-US');
        expect(module.preferencesDraft.hasChanges, isTrue);
        expect(module.projection.value.failure, isNotNull);
        host.phase = 'transientWithoutCache';
        await module.refresh();
        expect(module.projection.value.profile, isNull);
        expect(module.projection.value.canEditPreferences, isFalse);
        expect(
          host.names.every(
            (name) => [
              'account.getCurrent',
              'profile.getSelf',
              'gameIdentity.getPolicy',
            ].contains(name),
          ),
          isTrue,
        );
      },
      skip: skip,
    );
  }
  test('actual cached Native reply is read-only, excludes email and keeps its original time', () async {
    final host = await AccountProfileWireHost.create(path);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    module.preferencesDraft.setLocale('en-US');
    host.phase = 'cached';
    await module.refresh();
    final retained = module.projection.value;
    expect(retained.profileFreshness, AccountProfileFreshness.cached);
    expect(retained.profile?.email, isNull);
    expect(retained.canEditPreferences, isFalse);
    expect(module.preferencesDraft.locale, 'en-US');
    expect(
      retained.cachedAt,
      DateTime.parse(
        ((host.fixture['cached'] as Map)['payload'] as Map)['cachedAtUtc']
            as String,
      ),
    );
    await module.refresh();
    expect(module.projection.value.cachedAt, retained.cachedAt);
  }, skip: skip);
  test('known transient without Host cache retains only the last same-scope read-only profile', () async {
    final host = await AccountProfileWireHost.create(path);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    final liveName = module.projection.value.profile?.displayName;
    host.phase = 'transientWithoutCache';
    await module.refresh();
    final retained = module.projection.value;
    expect(retained.profile?.displayName, liveName);
    expect(retained.profile?.email, isNull);
    expect(retained.profileFreshness, AccountProfileFreshness.cached);
    expect(retained.cachedAt, isNotNull);
    expect(retained.canEditPreferences, isFalse);
    await module.refresh();
    expect(module.projection.value.cachedAt, retained.cachedAt);
    await host.pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.generation, 8);
    expect(module.projection.value.profile, isNull);
  }, skip: skip);
  for (final code in ['profile.read_unavailable', 'bridge.disconnected']) {
    test(
      'old ambiguous $code retryable flag cannot retain a live editable profile',
      () async {
        final host = await AccountProfileWireHost.create(path);
        final module = host.module();
        addTearDown(() async {
          module.dispose();
          await host.close();
        });
        await module.initialize();
        host.phase = 'unavailable';
        host.errorOverride = {
          'code': code,
          'message': 'Synthetic old Host failure',
          'retryable': true,
        };
        await module.refresh();
        expect(module.projection.value.profile, isNull);
        expect(module.projection.value.canEditPreferences, isFalse);
      },
      skip: skip,
    );
  }
  test('confirmed Native preference response replaces the local profile retention snapshot', () async {
    final host = await AccountProfileWireHost.create(path);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    await module.savePreferences(locale: 'en-US', timeZone: 'UTC');
    expect(module.projection.value.profile?.locale, 'en-US');
    host.phase = 'transientWithoutCache';
    await module.refresh();
    expect(module.projection.value.profile?.locale, 'en-US');
    expect(
      host.names.where((name) => name == 'profile.patchPreferences'),
      hasLength(1),
    );
  }, skip: skip);
  test(
    'confirmed Native clear also retires the client profile retention snapshot',
    () async {
      final host = await AccountProfileWireHost.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      await module.clearLocalCache();
      host.phase = 'transientWithoutCache';
      await module.refresh();
      expect(module.projection.value.profile, isNull);
      expect(module.projection.value.canEditPreferences, isFalse);
    },
    skip: skip,
  );
  for (final inFlight in [false, true]) {
    test(
      'hard account generation change hides old profile before held current read completes ($inFlight)',
      () async {
        final host = await AccountProfileWireHost.create(path);
        final module = host.module();
        addTearDown(() async {
          module.dispose();
          await host.close();
        });
        await module.initialize();
        module.preferencesDraft.setLocale('en-US');
        host.holdCurrent = true;
        final previous = inFlight ? module.refresh() : Future<void>.value();
        await Future<void>.delayed(Duration.zero);
        host.phase = 'transientWithoutCache';
        await host.pair.host.send(
          const BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'account.changed',
            sessionGeneration: 8,
            sequence: 1,
            payload: {'schemaVersion': 1},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(module.projection.value.profile, isNull);
        expect(module.projection.value.generation, 8);
        expect(module.preferencesDraft.locale, isEmpty);
        expect(module.projection.value.canEditPreferences, isFalse);
        await host.releaseCurrent();
        await previous;
        await Future<void>.delayed(Duration.zero);
        expect(module.projection.value.generation, 8);
        expect(module.projection.value.profile, isNull);
      },
      skip: skip,
    );
  }
  test(
    'profile retention preserves the confirmed current-account presentation',
    () async {
      final host = await AccountProfileWireHost.create(path);
      host.currentDisplayName = 'Current pilot';
      host.session.acceptHostCapabilities(['account.avatar.read']);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      expect(module.projection.value.profile?.displayName, 'Current pilot');
      host.phase = 'transientWithoutCache';
      await module.refresh();
      expect(module.projection.value.profile?.displayName, 'Current pilot');
    },
    skip: skip,
  );
}

final class AccountProfileWireHost {
  AccountProfileWireHost(this.fixture, this.pair, this.session) {
    incoming = pair.host.incoming.listen((request) {
      names.add(request.name);
      if (request.name == 'account.getCurrent' && holdCurrent) {
        heldCurrents.add(request);
        return;
      }
      reply(request);
    });
  }
  void reply(BridgeEnvelope request) {
    if (request.name == 'account.readAvatar') {
      unawaited(
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            sessionGeneration: request.sessionGeneration,
            correlationId: request.correlationId,
            status: 'error',
            payload: const {},
            error: const BridgeErrorBody(
              code: 'bridge.capability_unavailable',
              message: 'Optional media unavailable',
              retryable: false,
            ),
          ),
        ),
      );
      return;
    }
    final key = switch (request.name) {
      'account.getCurrent' => 'current',
      'gameIdentity.getPolicy' => 'identity',
      'profile.getSelf' => phase,
      'profile.patchPreferences' => 'saved',
      'profile.clearLocalCache' => 'cleared',
      _ => throw StateError('Unexpected request ${request.name}'),
    };
    final wire = (fixture[key] as Map).cast<String, Object?>();
    unawaited(
      pair.host.send(
        BridgeEnvelope.fromJson({
          ...wire,
          'correlationId': request.correlationId,
          'sessionGeneration': request.sessionGeneration,
          if (request.name == 'account.getCurrent' &&
              currentDisplayName != null)
            'payload': {
              ...(wire['payload'] as Map),
              'displayName': currentDisplayName,
            },
          if (request.name == 'profile.getSelf' && errorOverride != null)
            'error': errorOverride,
        }),
      ),
    );
  }

  static Future<AccountProfileWireHost> create(String path) async {
    final fixture =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    return fromFixture(fixture);
  }

  static AccountProfileWireHost fromFixture(Map<String, dynamic> fixture) {
    final pair = InMemoryBridgeConnection.createPair();
    return AccountProfileWireHost(
      fixture,
      pair,
      BridgeClientSession(connection: pair.client, sessionGeneration: 7),
    );
  }

  final Map<String, dynamic> fixture;
  final InMemoryBridgePair pair;
  final BridgeClientSession session;
  final names = <String>[];
  bool holdCurrent = false;
  final heldCurrents = <BridgeEnvelope>[];
  late final StreamSubscription<BridgeEnvelope> incoming;
  String phase = 'live';
  String? currentDisplayName;
  Map<String, Object?>? errorOverride;
  AccountModule module() => createAccountModule(BridgeAccountAdapter(session));
  Future<void> releaseCurrent() async {
    holdCurrent = false;
    for (final request in heldCurrents.toList()) {
      reply(request);
    }
    heldCurrents.clear();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
