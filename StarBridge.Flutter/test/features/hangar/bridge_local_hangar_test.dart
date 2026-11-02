import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  test(
    'removal pages stay on one revision and send only chosen local IDs',
    () async {
      final connection = LocalConnection()..removalPages = true;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      )..acceptHostCapabilities(['hangar.localReconciliation']);
      addTearDown(session.close);
      final port = BridgeLocalHangar(session);
      await port.read();
      final groups = await port.previewRemovals('scan', 1);
      expect(groups, hasLength(1));
      expect(groups.single.shipIds, hasLength(201));
      expect(groups.single.requiredCount, 200);
      await port.saveResolved(
        'scan',
        1,
        removedShipIds: groups.single.shipIds.skip(1).toList(),
      );
      final request = connection.requests.lastWhere(
        (r) => r.name == 'hangarReader.save',
      );
      expect(request.payload['removedShipIds'], hasLength(200));
      expect(request.payload.containsKey('ships'), isFalse);
      connection.badRemovalRevision = true;
      await expectLater(
        port.previewRemovals('scan', 1),
        throwsA(isA<LocalHangarFailure>()),
      );
      expect(
        BridgeLocalHangar.offline(session, 2).reconciliationAvailable,
        isFalse,
      );
    },
  );
  for (final mode in ['online', 'offline', 'retained']) {
    test(
      'separate inventory timestamp survives $mode projection and legacy fallback',
      () async {
        final connection = LocalConnection()
          ..history = true
          ..inventoryTime = '2026-10-14T10:00:00Z';
        final session = BridgeClientSession(
          connection: connection,
          sessionGeneration: 7,
        );
        addTearDown(session.close);
        final port = mode == 'offline'
            ? BridgeLocalHangar.offline(session, 22)
            : mode == 'retained'
            ? BridgeLocalHangar.retained(
                session,
                '1234567890abcdef1234567890abcdef',
                isCurrent: () => true,
              )
            : BridgeLocalHangar(session);
        final result = await port.read();
        expect(result.savedAt, DateTime.utc(2026, 10, 16, 15));
        expect(result.inventoryReadSavedAt, DateTime.utc(2026, 10, 14, 10));
        connection.inventoryTime = null;
        final legacy = await port.read();
        expect(legacy.inventorySavedAt, isNull);
        expect(legacy.inventoryReadSavedAt, legacy.savedAt);
      },
    );
  }

  test('network outage inventory reads own retained pages without binding or writes', () async {
    final connection = LocalConnection()..history = true;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    var current = true;
    final port = BridgeLocalHangar.retained(
      session,
      '1234567890abcdef1234567890abcdef',
      isCurrent: () => current,
    );
    final result = await port.read();
    expect(result.ships, hasLength(201));
    expect(result.formerShips, hasLength(201));
    expect(port.favoritesAvailable, isFalse);
    expect(connection.requests, hasLength(4));
    expect(
      connection.requests.every(
        (r) =>
            r.name == 'account.offlineData.read' &&
            r.accountContext == null &&
            r.payload['kind'] == 'hangar',
      ),
      isTrue,
    );
    final count = connection.requests.length;
    await expectLater(
      port.save('forbidden', 1),
      throwsA(isA<LocalHangarFailure>()),
    );
    current = false;
    await expectLater(port.read(), throwsA(isA<LocalHangarFailure>()));
    expect(connection.requests.length, count);
  });
  test('offline inventory reads original pages without login, sharing or write authority', () async {
    final connection = LocalConnection()..history = true;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    final port = BridgeLocalHangar.offline(session, 22);
    final result = await port.read();
    expect(result.ships, hasLength(201));
    expect(result.formerShips, hasLength(201));
    expect(port.favoritesAvailable, isFalse);
    expect(port.imageFor('ship-0', 1), isNull);
    expect(connection.requests, hasLength(4));
    expect(
      connection.requests.every(
        (r) =>
            r.name == 'onboarding.mode.hangar' &&
            r.accountContext == null &&
            r.payload['revision'] == 22,
      ),
      isTrue,
    );
    final count = connection.requests.length;
    await expectLater(
      port.save('not-allowed', 1),
      throwsA(isA<LocalHangarFailure>()),
    );
    expect(connection.requests.length, count);
  });
  test(
    'history pages use the same revision and retain removal timestamps',
    () async {
      final connection = LocalConnection()..history = true;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      final inventory = await BridgeLocalHangar(session).read();
      expect(inventory.ships.length, 201);
      expect(inventory.formerShips.length, 201);
      expect(inventory.formerShips.first.removedAt, DateTime.utc(2026, 9, 20));
      expect(inventory.formerInstances.length, 201);
      expect(
        connection.requests.where((r) => r.payload['former'] == true).length,
        2,
      );
    },
  );
  test('legacy hangar displays own synced inventory without saving or merging duplicate ships', () async {
    final connection = LocalConnection()
      ..legacy = true
      ..emptyRevision = 0;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    final port = BridgeLocalHangar(session);
    final inventory = await port.read();
    expect(inventory.revision, 0);
    expect(inventory.fromLegacyProfile, isTrue);
    expect(inventory.ships.length, 2);
    expect(inventory.ships.map((s) => s.id).toSet().length, 2);
    expect(connection.requests.map((r) => r.name), [
      'account.getCurrent',
      'hangarReader.inventory',
      'personalProfile.getSelf',
    ]);
    connection.requests.clear();
    connection.emptyRevision = 1;
    expect((await port.read()).ships, isEmpty);
    expect(
      connection.requests.any((r) => r.name == 'personalProfile.getSelf'),
      isFalse,
    );
  });
  test('SCM missing hangar does not read the old profile', () async {
    final connection = LocalConnection()..emptyRevision = 0;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    expect(
      (await BridgeLocalHangar(session).read()).fromLegacyProfile,
      isFalse,
    );
    expect(
      connection.requests.any((r) => r.name == 'personalProfile.getSelf'),
      isFalse,
    );
  });
  test('optional legacy projection does not turn an unsaved local hangar into a read failure', () async {
    final connection = LocalConnection()
      ..legacy = true
      ..emptyRevision = 0
      ..profileHasHangar = false;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    final snapshot = await BridgeLocalHangar(session).read();
    expect(snapshot.revision, 0);
    expect(snapshot.fromLegacyProfile, isFalse);
    expect(snapshot.ships, isEmpty);
    expect(snapshot.savedAt, isNull);
    expect(snapshot.operationId, isNull);
    expect(connection.requests.map((r) => r.name), [
      'account.getCurrent',
      'hangarReader.inventory',
      'personalProfile.getSelf',
    ]);
  });
  test(
    'reads every page with decoded account values and sends no ship payload',
    () async {
      final connection = LocalConnection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      final port = BridgeLocalHangar(session);
      final inventory = await port.read();
      expect(inventory.ships.length, 201);
      expect(inventory.ships.first.priceUsd, 600);
      expect(inventory.ships.first.category, 'exploration');
      expect(inventory.ships.first.sizeClass, 'large');
      expect(inventory.ships.first.size, isNull);
      expect(
        inventory.ships.first.imageAsset,
        'assets/ships/catalog-carrack.jpg',
      );
      expect((await port.read()).ships.length, 201);
      expect(
        inventory.ships.first.thumbnailAsset,
        'assets/ships/catalog-square-carrack.png',
      );
      final saved = await port.save('scan', 1);
      expect(saved.operationId, 'scan');
      final request = connection.requests.singleWhere(
        (r) => r.name == 'hangarReader.save',
      );
      expect(request.payload.keys.toSet(), {
        'schemaVersion',
        'operationId',
        'expectedRevision',
        'confirmEmpty',
      });
      session.advanceGeneration(8);
      await expectLater(
        port.save('scan', 2),
        throwsA(isA<LocalHangarFailure>()),
      );
      await session.close();
    },
  );

  for (final profile in <Map<String, Object?>>[
    {},
    {'hangar': null},
  ]) {
    test(
      'omitted or null optional profile hangar preserves unsaved local state: $profile',
      () async {
        final connection = LocalConnection()
          ..legacy = true
          ..emptyRevision = 0
          ..profilePayload = {'schemaVersion': 1, 'profile': profile};
        final session = BridgeClientSession(
          connection: connection,
          sessionGeneration: 7,
        );
        addTearDown(session.close);
        final snapshot = await BridgeLocalHangar(session).read();
        expect(snapshot.revision, 0);
        expect(snapshot.ships, isEmpty);
        expect(snapshot.savedAt, isNull);
        expect(snapshot.operationId, isNull);
        expect(snapshot.fromLegacyProfile, isFalse);
        expect(connection.requests.map((r) => r.name), [
          'account.getCurrent',
          'hangarReader.inventory',
          'personalProfile.getSelf',
        ]);
      },
    );
  }

  final invalidProfiles = <String, Map<String, Object?>>{
    'missing profile': {'schemaVersion': 1},
    'null profile': {'schemaVersion': 1, 'profile': null},
    'wrong profile type': {'schemaVersion': 1, 'profile': []},
    for (final hangar in <Object>[
      'invalid',
      {},
      {'ships': null},
      {'ships': 'invalid'},
    ])
      'invalid hangar $hangar': {
        'schemaVersion': 1,
        'profile': {'hangar': hangar},
      },
    'oversized projection': {
      'schemaVersion': 1,
      'profile': {
        'hangar': {'ships': List.filled(20001, {})},
      },
    },
    'invalid ship': {
      'schemaVersion': 1,
      'profile': {
        'hangar': {
          'ships': [
            {'code': ''},
          ],
        },
      },
    },
  };
  for (final fixture in invalidProfiles.entries) {
    test(
      '${fixture.key} still fails instead of becoming unsaved inventory',
      () async {
        final connection = LocalConnection()
          ..legacy = true
          ..emptyRevision = 0
          ..profilePayload = fixture.value;
        final session = BridgeClientSession(
          connection: connection,
          sessionGeneration: 7,
        );
        addTearDown(session.close);
        await expectLater(
          BridgeLocalHangar(session).read(),
          throwsA(isA<LocalHangarFailure>()),
        );
        expect(connection.requests, hasLength(3));
      },
    );
  }

  test(
    'optional profile display does not bypass account ownership checks',
    () async {
      final connection = LocalConnection()
        ..legacy = true
        ..emptyRevision = 0
        ..profileHasHangar = false
        ..profileSubject = 'different-owner';
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeLocalHangar(session).read(),
        throwsA(
          isA<LocalHangarFailure>().having(
            (e) => e.code,
            'code',
            'hangar.account_changed',
          ),
        ),
      );
    },
  );

  test(
    'failed profile read is not hidden as optional display absence',
    () async {
      final connection = LocalConnection()
        ..legacy = true
        ..emptyRevision = 0
        ..profileErrorCode = 'account.session_expired';
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeLocalHangar(session).read(),
        throwsA(
          isA<BridgeRemoteException>().having(
            (e) => e.code,
            'code',
            'account.session_expired',
          ),
        ),
      );
      expect(connection.requests, hasLength(3));
    },
  );

  test('local inventory failure never reads the optional profile', () async {
    final connection = LocalConnection()
      ..legacy = true
      ..emptyRevision = 0
      ..profileHasHangar = false
      ..inventoryErrorCode = 'hangar.unavailable';
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    await expectLater(
      BridgeLocalHangar(session).read(),
      throwsA(
        isA<LocalHangarFailure>().having(
          (e) => e.code,
          'code',
          'hangar.unavailable',
        ),
      ),
    );
    expect(connection.requests.map((r) => r.name), [
      'account.getCurrent',
      'hangarReader.inventory',
    ]);
  });

  test('generation change rejects a late optional projection without returning old inventory', () async {
    final release = Completer<void>(), started = Completer<void>();
    final connection = LocalConnection()
      ..legacy = true
      ..emptyRevision = 0
      ..profileHasHangar = false
      ..profileStarted = started
      ..profileDelay = release.future;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    final rejected = expectLater(
      BridgeLocalHangar(session).read(),
      throwsA(isA<BridgeStaleGenerationException>()),
    );
    await started.future;
    session.advanceGeneration(8);
    release.complete();
    await rejected;
    await connection.profileReplied.future;
    expect(session.activeGeneration, 8);
    expect(connection.requests, hasLength(3));
  });

  test('wrong schema is not interpreted as optional display absence', () async {
    final connection = LocalConnection()
      ..legacy = true
      ..emptyRevision = 0
      ..profilePayload = {'schemaVersion': 2, 'profile': <String, Object?>{}};
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    );
    addTearDown(session.close);
    await expectLater(
      BridgeLocalHangar(session).read(),
      throwsA(
        isA<LocalHangarFailure>().having(
          (e) => e.code,
          'code',
          'hangar.account_changed',
        ),
      ),
    );
  });
}

class LocalConnection implements BridgeConnection {
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  String? operation;
  String? inventoryTime;
  String? nickname, notes;
  bool legacy = false, profileHasHangar = true;
  bool history = false;
  bool removalPages = false, badRemovalRevision = false;
  int? emptyRevision;
  Map<String, Object?>? profilePayload;
  String profileSubject = 'owner';
  String? profileErrorCode;
  String? inventoryErrorCode;
  Future<void>? profileDelay;
  Completer<void>? profileStarted;
  final profileReplied = Completer<void>();
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    requests.add(request);
    final offset = request.payload['offset'] as int? ?? 0;
    final former = request.payload['former'] == true;
    if (request.name == 'hangarReader.save') operation = 'scan';
    if (request.name == 'hangarReader.personalData') {
      operation = request.payload['operationId'] as String;
      nickname = request.payload['nickname'] as String?;
      notes = request.payload['notes'] as String?;
    }
    var payload = request.name == 'account.getCurrent'
        ? <String, Object?>{
            'schemaVersion': 1,
            'state': legacy ? 'legacySignedIn' : 'signedIn',
          }
        : <String, Object?>{
            'schemaVersion': 1,
            'revision': operation == null ? 1 : 2,
            'savedAt': '2026-10-16T15:00:00Z',
            if (inventoryTime != null) 'inventorySavedAt': inventoryTime,
            'total': 201,
            if (history) 'formerTotal': 201,
            if (history) 'former': former,
            'partial': false,
            'operationId': operation,
            'nextOffset': offset == 0 ? 200 : null,
            'ships': List.generate(
              offset == 0 ? 200 : 1,
              (i) => {
                'id': '${former ? 'former' : 'ship'}-${offset + i}',
                if (former) 'removedAt': '2026-09-20T00:00:00Z',
                'title': 'Ship ${offset + i}',
                if (nickname != null) 'nickname': nickname,
                if (notes != null) 'notes': notes,
                'names': {'zhHans': '舰船 ${offset + i}'},
                'catalogId': former ? 'catalog-former' : 'catalog-carrack',
                'category': 'exploration',
                'sizeClass': 'large',
                'deliveryStatus': 'flyable',
                'priceUsd': 600,
                'imageAsset': 'assets/ships/catalog-carrack.jpg',
                'thumbnailAsset': 'assets/ships/catalog-square-carrack.png',
              },
            ),
          };
    if (request.name == 'hangarReader.inventory' && emptyRevision != null) {
      payload = {
        'schemaVersion': 1,
        'revision': emptyRevision,
        'total': 0,
        'ships': <Object>[],
        'nextOffset': null,
      };
    }
    if (request.name == 'hangarReader.removals' && removalPages) {
      payload = {
        'schemaVersion': 1,
        'operationId': 'scan',
        'revision': badRemovalRevision && offset == 200 ? 2 : 1,
        'total': 201,
        'nextOffset': offset == 0 ? 200 : null,
        'rows': List.generate(
          offset == 0 ? 200 : 1,
          (i) => {
            'groupId': 'ship-0',
            'requiredCount': 200,
            'groupSize': 201,
            'shipId': 'ship-${offset + i}',
          },
        ),
      };
    }
    if (request.name == 'personalProfile.getSelf') {
      profileStarted?.complete();
      if (profileDelay != null) await profileDelay;
      payload =
          profilePayload ??
          {
            'schemaVersion': 1,
            'profile': {
              'hangar': profileHasHangar
                  ? {
                      'ships': [
                        for (var i = 0; i < 2; i++)
                          {
                            'code': 'ship',
                            'displayName': 'Same ship',
                            'importedAt': '2026-01-01T00:00:00Z',
                          },
                      ],
                    }
                  : null,
            },
          };
    }
    final errorCode = request.name == 'personalProfile.getSelf'
        ? profileErrorCode
        : request.name == 'hangarReader.inventory'
        ? inventoryErrorCode
        : null;
    // The actual transport creates a distinct context object for each response.
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': 7,
        'status': errorCode != null ? 'error' : 'ok',
        if (errorCode != null)
          'error': {
            'code': errorCode,
            'message': 'Synthetic failure',
            'retryable': false,
          },
        if (request.name != 'onboarding.mode.hangar' &&
            request.name != 'account.offlineData.read')
          'accountContext': {
            'environment': 'test',
            'authority': legacy ? 'starbridge-relay-test' : 'issuer',
            'subject': request.name == 'personalProfile.getSelf'
                ? profileSubject
                : 'owner',
          },
        'payload': payload,
      }),
    );
    if (request.name == 'personalProfile.getSelf' &&
        !profileReplied.isCompleted) {
      profileReplied.complete();
    }
  }
}
