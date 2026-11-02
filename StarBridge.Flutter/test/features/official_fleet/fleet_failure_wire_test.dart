import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  const path = String.fromEnvironment('STARBRIDGE_FLEET_FAILURE_WIRE');
  final skip = path.isEmpty
      ? 'Requires the explicitly generated synthetic Native fleet wire fixture.'
      : false;
  for (final physicalDisconnect in [false, true]) {
    test(
      'Native fleet baseline retains display after ${physicalDisconnect ? 'actual connection close' : 'actual transient response'}',
      () async {
        final host = await _Harness.create(path);
        final module = createOfficialFleetModule(
          BridgeOfficialFleetAdapter(host.session),
          InMemoryOfficialFleetOverviewAdapter.forReview(),
          InMemoryOfficialFleetMembersAdapter.forReview(),
          InMemoryOfficialFleetShipsAdapter.forReview(),
        );
        addTearDown(() async {
          module.dispose();
          await host.close();
        });
        await module.initialize();
        await Future<void>.delayed(Duration.zero);
        final loaded = module.projection.value;
        expect(loaded.availability, OfficialFleetAvailability.available);
        host.phase = 'Transient';
        host.disconnect = physicalDisconnect;
        await module.refresh();
        expect(
          module.projection.value.availability,
          OfficialFleetAvailability.available,
        );
        expect(module.projection.value.fleet, same(loaded.fleet));
        expect(module.projection.value.observedAtUtc, loaded.observedAtUtc);
        expect(module.projection.value.refreshFailed, isTrue);
        expect(module.communication.readOnly, isTrue);
        expect(module.members.projection.value.members, isNotEmpty);
        expect(module.overview.projection.value.metrics, isNotNull);
      },
      skip: skip,
    );
  }
  for (final code in [
    'official_fleet.read_unavailable',
    'official_fleet.read_forbidden',
    'official_fleet.data_invalid',
    'account.reauthorization_required',
    'bridge.host_error',
    'bridge.disconnected',
  ]) {
    test('remote $code never gains retention from retryable alone', () async {
      final host = await _Harness.create(path);
      final module = createOfficialFleetModule(
        BridgeOfficialFleetAdapter(host.session),
        InMemoryOfficialFleetOverviewAdapter.forReview(),
        InMemoryOfficialFleetMembersAdapter.forReview(),
        InMemoryOfficialFleetShipsAdapter.forReview(),
      );
      addTearDown(() async {
        module.dispose();
        await host.close();
      });
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      host.phase = 'Transient';
      host.overrideCode = code;
      await module.refresh();
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.unavailable,
      );
      expect(module.projection.value.refreshFailed, isFalse);
      expect(module.members.projection.value.members, isEmpty);
      expect(module.overview.projection.value.metrics, isNull);
    }, skip: skip);
  }
  test(
    'Native member adapter distinguishes actual transient from denied read',
    () async {
      final host = await _Harness.create(path);
      final adapter = BridgeOfficialFleetMembersAdapter(host.session);
      addTearDown(() async {
        await adapter.close();
        await host.close();
      });
      const query = OfficialFleetMemberDirectoryQuery(
        sourceRef: 'officialFleet:7',
        search: 'Pilot & Wing',
      );
      expect((await adapter.read(query)).members, isNotEmpty);
      host.phase = 'Transient';
      expect(
        (await adapter.read(query)).failureKey,
        'officialFleet.members.error.transient',
      );
      host.phase = 'Forbidden';
      expect(
        (await adapter.read(query)).failureKey,
        'officialFleet.error.forbidden',
      );
    },
    skip: skip,
  );
}

final class _Harness {
  _Harness(this.fixture, this.pair, this.session) {
    incoming = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'account.getCurrent') {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              accountContext: owner,
              status: 'ok',
              payload: const {'schemaVersion': 1, 'state': 'signedIn'},
            ),
          ),
        );
        return;
      }
      if (disconnect) {
        unawaited(pair.client.close());
        return;
      }
      final key =
          '${request.name == 'officialFleet.getCurrent' ? 'identity' : 'members'}$phase';
      final captured = BridgeEnvelope.fromJson(
        (fixture[key] as Map).cast<String, Object?>(),
      );
      unawaited(
        pair.host.send(
          BridgeEnvelope.fromJson({
            ...captured.toJson(),
            'correlationId': request.correlationId,
            if (overrideCode != null)
              'error': {
                'code': overrideCode,
                'message': 'Synthetic older or unknown error.',
                'retryable': true,
              },
          }),
        ),
      );
    });
  }
  static Future<_Harness> create(String path) async {
    final fixture =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final success = BridgeEnvelope.fromJson(
      (fixture['identitySuccess'] as Map).cast<String, Object?>(),
    );
    final pair = InMemoryBridgeConnection.createPair();
    return _Harness(
      fixture,
      pair,
      BridgeClientSession(
        connection: pair.client,
        sessionGeneration: success.sessionGeneration,
      ),
    );
  }

  final Map<String, dynamic> fixture;
  final InMemoryBridgePair pair;
  final BridgeClientSession session;
  BridgeAccountContext get owner => BridgeEnvelope.fromJson(
    (fixture['identitySuccess'] as Map).cast<String, Object?>(),
  ).accountContext!;
  late final StreamSubscription<BridgeEnvelope> incoming;
  String phase = 'Success';
  bool disconnect = false;
  String? overrideCode;
  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
