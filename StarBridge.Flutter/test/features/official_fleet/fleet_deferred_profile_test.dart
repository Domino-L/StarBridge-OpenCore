import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  const path = String.fromEnvironment('STARBRIDGE_FLEET_DEFERRED_WIRE');
  final skip = path.isEmpty
      ? 'Requires synthetic Native Runtime deferred-profile fixture.'
      : false;
  test(
    'identity becomes available while the Native public response remains held',
    () async {
      final host = await DeferredFleetHost.create(path);
      final module = host.module();
      final initial = module.initialize();
      addTearDown(() async {
        module.dispose();
        await host.close();
        await initial;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.available,
      );
      await initial;
      await Future<void>.delayed(Duration.zero);
      expect(host.publicRequests, hasLength(1));
      expect(module.projection.value.fleet?.profile, isNull);
      expect(module.projection.value.isProfileReading, isTrue);
      final identityTime = module.projection.value.observedAtUtc;
      await host.replyProfile(host.publicRequests.single, 'profileSuccess');
      await Future<void>.delayed(Duration.zero);
      expect(
        module.projection.value.fleet?.profile?.rsiDescription,
        'Explore & build',
      );
      expect(module.projection.value.isProfileReading, isFalse);
      expect(module.projection.value.observedAtUtc, identityTime);
      expect(module.projection.value.profileObservedAtUtc, isNotNull);
    },
    skip: skip,
  );
  test('an older Host continues through the original enriched read', () async {
    final host = await DeferredFleetHost.create(path, deferred: false);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    expect(module.projection.value.fleet?.profile, isNotNull);
    expect(host.publicRequests, isEmpty);
    expect(host.names, contains('officialFleet.getCurrent'));
  }, skip: skip);
  test(
    'retiring the profile consumer preserves a shared account read',
    () async {
      final host = await DeferredFleetHost.create(path);
      host.holdAccount = true;
      final adapter = BridgeOfficialFleetAdapter(host.session);
      addTearDown(() async {
        await adapter.close();
        await host.close();
      });
      final peer = host.session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final profile = adapter.readProfile('officialFleet:7');
      await Future<void>.delayed(Duration.zero);
      expect(host.accountRequests, hasLength(1));
      await adapter.cancelProfileRead();
      expect((await profile).discarded, isTrue);
      expect(host.names, isNot(contains('bridge.cancel')));
      await host.replyAccount(host.accountRequests.single);
      expect((await peer).payload['state'], 'signedIn');
      expect(host.publicRequests, isEmpty);
    },
    skip: skip,
  );
  test(
    'a failed fresh account check is not merely a public-field failure',
    () async {
      final host = await DeferredFleetHost.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      module.projection.addListener(() {
        if (module.projection.value.isProfileReading) {
          host.accountFailure = const BridgeErrorBody(
            code: 'bridge.host_error',
            message: 'Synthetic failure',
            retryable: false,
          );
        }
      });
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.unavailable,
      );
      expect(module.projection.value.isProfileReading, isFalse);
      expect(host.publicRequests, isEmpty);
    },
    skip: skip,
  );
  test(
    'same-source refresh keeps public content and its successful time',
    () async {
      final host = await DeferredFleetHost.create(path);
      final module = host.module();
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      await host.replyProfile(host.publicRequests.last, 'profileSuccess');
      await Future<void>.delayed(Duration.zero);
      final loaded = module.projection.value;
      await module.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(module.projection.value.isProfileReading, isTrue);
      expect(module.projection.value.profileRefreshFailed, isFalse);
      expect(
        module.projection.value.fleet?.profile,
        same(loaded.fleet?.profile),
      );
      expect(
        module.projection.value.profileObservedAtUtc,
        loaded.profileObservedAtUtc,
      );
      await host.replyProfile(host.publicRequests.last, 'profileTransient');
      await Future<void>.delayed(Duration.zero);
      expect(module.projection.value.isProfileReading, isFalse);
      expect(module.projection.value.profileRefreshFailed, isTrue);
      expect(
        module.projection.value.fleet?.profile,
        same(loaded.fleet?.profile),
      );
      expect(
        module.projection.value.profileObservedAtUtc,
        loaded.profileObservedAtUtc,
      );
      for (final phase in ['profileForbidden', 'profileInvalid']) {
        await module.refresh();
        await Future<void>.delayed(Duration.zero);
        await host.replyProfile(host.publicRequests.last, phase);
        await Future<void>.delayed(Duration.zero);
        expect(module.projection.value.fleet?.profile, isNull);
        expect(module.projection.value.profileObservedAtUtc, isNull);
        expect(module.projection.value.fleet?.officialRankValue, 4);
        expect(module.projection.value.isProfileReading, isFalse);
      }
    },
    skip: skip,
  );
  test(
    'superseded and disposed profile reads retire only their own work',
    () async {
      final host = await DeferredFleetHost.create(path);
      final module = host.module();
      addTearDown(host.close);
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      final old = host.publicRequests.single;
      await module.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(host.names, contains('bridge.cancel'));
      final fresh = host.publicRequests.last;
      expect(fresh.correlationId, isNot(old.correlationId));
      await host.replyProfile(fresh, 'profileSuccess');
      await host.replyProfile(old, 'profileForbidden');
      await Future<void>.delayed(Duration.zero);
      expect(
        module.projection.value.fleet?.profile?.rsiDescription,
        'Explore & build',
      );
      await module.refresh();
      await Future<void>.delayed(Duration.zero);
      final pending = host.publicRequests.last;
      final cancelled = host.names.where((n) => n == 'bridge.cancel').length;
      module.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(
        host.names.where((n) => n == 'bridge.cancel').length,
        greaterThan(cancelled),
      );
      await host.replyProfile(pending, 'profileSuccess');
      await Future<void>.delayed(Duration.zero);
    },
    skip: skip,
  );
  test('account invalidation cannot restore an old public response', () async {
    final host = await DeferredFleetHost.create(path);
    final module = host.module();
    addTearDown(() async {
      module.dispose();
      await host.close();
    });
    await module.initialize();
    await Future<void>.delayed(Duration.zero);
    final old = host.publicRequests.single;
    await host.pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 2,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(module.contextRevision, 1);
    await host.replyProfile(old, 'profileSuccess');
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.fleet?.profile, isNull);
    expect(module.projection.value.profileObservedAtUtc, isNull);
    expect(host.publicRequests, hasLength(2));
    await host.replyProfile(host.publicRequests.last, 'profileForbidden');
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.isProfileReading, isFalse);
  }, skip: skip);
}

final class DeferredFleetHost {
  DeferredFleetHost(this.fixture, this.pair, this.session, this.deferred) {
    incoming = pair.host.incoming.listen((request) {
      names.add(request.name);
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'account.getCurrent') {
        accountRequests.add(request);
        if (!holdAccount) unawaited(replyAccount(request));
      } else if (request.name == 'officialFleet.getIdentity') {
        unawaited(reply(request, 'identity'));
      } else if (request.name == 'officialFleet.getCurrent' && !deferred) {
        unawaited(reply(request, 'legacy'));
      } else if (request.name == 'officialFleet.getPublicProfile') {
        publicRequests.add(request);
      }
    });
  }
  static Future<DeferredFleetHost> create(
    String path, {
    bool deferred = true,
  }) async => fromFixture(
    jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
    deferred: deferred,
  );
  static DeferredFleetHost fromFixture(
    Map<String, dynamic> fixture, {
    bool deferred = true,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    final identity = BridgeEnvelope.fromJson(
      (fixture['identity'] as Map).cast<String, Object?>(),
    );
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: identity.sessionGeneration,
    );
    if (deferred) {
      session.acceptHostCapabilities(['officialFleet.deferredProfile']);
    }
    return DeferredFleetHost(fixture, pair, session, deferred);
  }

  final Map<String, dynamic> fixture;
  final InMemoryBridgePair pair;
  final BridgeClientSession session;
  final bool deferred;
  final names = <String>[];
  final publicRequests = <BridgeEnvelope>[];
  final accountRequests = <BridgeEnvelope>[];
  bool holdAccount = false;
  BridgeErrorBody? accountFailure;
  late final StreamSubscription<BridgeEnvelope> incoming;
  BridgeAccountContext get owner => BridgeEnvelope.fromJson(
    (fixture['identity'] as Map).cast<String, Object?>(),
  ).accountContext!;
  OfficialFleetModule module() => createOfficialFleetModule(
    BridgeOfficialFleetAdapter(session),
    UnavailableOfficialFleetOverviewAdapter(),
    UnavailableOfficialFleetMembersAdapter(),
    UnavailableOfficialFleetShipsAdapter(),
  );
  Future<void> reply(BridgeEnvelope request, String phase) {
    final envelope = BridgeEnvelope.fromJson(
      (fixture[phase] as Map).cast<String, Object?>(),
    );
    return pair.host.send(
      BridgeEnvelope.fromJson({
        ...envelope.toJson(),
        'correlationId': request.correlationId,
        'sessionGeneration': request.sessionGeneration,
      }),
    );
  }

  Future<void> replyProfile(BridgeEnvelope request, String phase) =>
      reply(request, phase);
  Future<void> replyAccount(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: owner,
      status: accountFailure == null ? 'ok' : 'error',
      error: accountFailure,
      payload: accountFailure == null
          ? const {'schemaVersion': 1, 'state': 'signedIn'}
          : const {},
    ),
  );
  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
