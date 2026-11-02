import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';

import 'official_fleet_hangar_sharing_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_shared_ships.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

String ref(int n) => n.toRadixString(16).padLeft(32, '0');
String hash(int n) => n.toRadixString(16).padLeft(64, '0');
Map<String, Object?> ship({bool restricted = false}) => {
  'shipRef': ref(1),
  'code': 'Arrow',
  'displayName': 'Arrow',
  'ownerMemberRef': ref(2),
  'ownerGameName': '',
  'ownerCallsign': restricted ? '' : 'Bridge Pilot',
  'ownerOnline': false,
  'ownerLiveStatus': 'Unknown',
  'ownerIsSelf': false,
  'ownerHasAvatar': false,
  'ownerAvatarVersion': null,
  'sharedAt': null,
  'hangarImportedAt': null,
  'catalogStatus': 'Flyable',
  'catalogPriceUsd': null,
  'hasCustomImage': false,
  'customImageCropFocusX': .5,
  'customImageCropFocusY': .5,
  'customImageCropZoom': 1.0,
};
Map<String, Object?> projection(
  Map<String, Object?> request, {
  bool restricted = false,
}) => {
  'schemaVersion': 1,
  'sourceRef': request['sourceRef'],
  'targetRef': request['targetRef'],
  'revision': hash(3),
  'offset': request['offset'],
  'next': null,
  'totalCount': 1,
  'matchedCount': 1,
  'queryVersion': 2,
  'query': request['query'],
  'ships': [ship(restricted: restricted)],
  'owners': [
    {
      'ownerMemberRef': ref(2),
      'profileReference': restricted ? null : hash(4),
      'avatarImageData': null,
      'avatarVersion': null,
    },
  ],
};

class Harness {
  Harness() {
    final pair = InMemoryBridgeConnection.createPair();
    wire = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(const ['officialFleet.ships']);
    adapter = BridgeOfficialFleetSharedShips(
      session,
      sourceRef: () => source.value,
      sourceChanges: source,
    );
    subscription = wire.incoming.listen((request) async {
      requests.add(request);
      if (request.name == 'officialFleet.ships' && hold != null) {
        await hold!.future;
      }
      final value = request.name == 'account.getCurrent'
          ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
          : mutate?.call(projection(request.payload, restricted: restricted)) ??
                projection(request.payload, restricted: restricted);
      await wire.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: account,
          status: error == null || request.name == 'account.getCurrent'
              ? 'ok'
              : 'error',
          error: error == null || request.name == 'account.getCurrent'
              ? null
              : BridgeErrorBody(
                  retryable: false,
                  code: error!,
                  message: 'Synthetic failure',
                ),
          payload: value,
        ),
      );
    });
  }
  final source = ValueNotifier<String?>('officialFleet:7');
  late final BridgeConnection wire;
  late final BridgeClientSession session;
  late final BridgeOfficialFleetSharedShips adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final account = const BridgeAccountContext(
    environment: 'synthetic',
    authority: 'scm',
    subject: 'fixture-only',
  );
  bool restricted = false;
  String? error;
  Completer<void>? hold;
  Map<String, Object?> Function(Map<String, Object?>)? mutate;
  Future<void> close() async {
    await adapter.close();
    await session.close();
    await subscription.cancel();
    await wire.close();
    source.dispose();
  }
}

void main() {
  setUpAll(loadFonts);
  test('official catalog page reuses strict community page and typed holder target', () async {
    final h = Harness();
    addTearDown(h.close);
    final value = await h.adapter.readShips(
      ref(9),
      query: CommunityShipQuery(text: 'Bridge Pilot'),
    );
    expect(value.ships.single.catalogPriceUsd, isNull);
    expect(value.ships.single.ownerOnline, isFalse);
    final target = h.adapter.ownerTarget(ref(9), value.ships.single)!;
    expect(target.source, 'officialFleet');
    expect(target.reference, hash(4));
    expect(target.contextRef, 'officialFleet:7');
    expect(h.requests.map((r) => r.name), [
      'account.getCurrent',
      'officialFleet.ships',
    ]);
    expect(
      h.requests.last.payload['query'],
      CommunityShipQuery(text: 'Bridge Pilot').toPayload(),
    );
    expect(h.requests.last.payload['sourceRef'], 'officialFleet:7');
    expect(value.ships.single.shipRef.length, 32);
    expect(value.ships.single.ownerMemberRef.length, 32);
  });
  test('restricted owner remains anonymous without SCM or community profile fallback', () async {
    final h = Harness()..restricted = true;
    addTearDown(h.close);
    final value = await h.adapter.readShips(ref(9));
    expect(value.ships.single.ownerCallsign, '');
    expect(value.ships.single.ownerHasAvatar, false);
    expect(h.adapter.ownerTarget(ref(9), value.ships.single), isNull);
    expect(h.adapter.avatarAccess.read, isNotNull);
    await expectLater(
      h.adapter.avatarAccess.read!(ref(9), ref(2), offset: 0),
      throwsA(isA<CommunityFailure>()),
    );
    expect(h.requests.any((r) => r.name.startsWith('communities.')), false);
  });
  test(
    'malformed and mismatched owner sidecars clear former targets and rows',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final model = CommunityShipsController(h.adapter, ref(9));
      addTearDown(model.dispose);
      await model.load();
      final old = model.page!.ships.single;
      expect(h.adapter.ownerTarget(ref(9), old), isNotNull);
      h.mutate = (p) => {
        ...p,
        'owners': [
          {
            'ownerMemberRef': ref(2),
            'profileReference': ref(4),
            'avatarImageData': null,
            'avatarVersion': null,
          },
        ],
      };
      await model.load();
      expect(model.page, isNull);
      expect(model.error, 'dataInvalid');
      expect(h.adapter.ownerTarget(ref(9), old), isNull);
    },
  );
  test('unknown permission failure clears old identity rather than keeping stale holder', () async {
    final h = Harness();
    addTearDown(h.close);
    final model = CommunityShipsController(h.adapter, ref(9));
    addTearDown(model.dispose);
    await model.load();
    final old = model.page!.ships.single;
    h.error = 'official_fleet.identity_unavailable';
    await model.refreshVisible();
    expect(model.page, isNull);
    expect(model.invalidated, true);
    expect(h.adapter.ownerTarget(ref(9), old), isNull);
  });
  test(
    'source replacement cancels late page and clears existing target',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final old = (await h.adapter.readShips(ref(9))).ships.single;
      h.hold = Completer<void>();
      final pending = h.adapter.readShips(ref(9));
      final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
      await Future<void>.delayed(Duration.zero);
      h.source.value = 'officialFleet:8';
      h.hold!.complete();
      await rejected;
      expect(h.adapter.ownerTarget(ref(9), old), isNull);
    },
  );
  test('raw or duplicate owner refs and accidental custom image advertisement fail closed', () async {
    final h = Harness();
    addTearDown(h.close);
    for (final change in <Map<String, Object?> Function(Map<String, Object?>)>[
      (p) => {...p, 'sourceRef': 'officialFleet:8'},
      (p) => {
        ...p,
        'owners': [...(p['owners'] as List), ...(p['owners'] as List)],
      },
      (p) => {
        ...p,
        'ships': [
          {...ship(), 'hasCustomImage': true},
        ],
      },
      (p) => {
        ...p,
        'ships': [
          {...ship(), 'ownerMemberRef': hash(2)},
        ],
      },
    ]) {
      h.mutate = change;
      await expectLater(
        h.adapter.readShips(ref(9)),
        throwsA(isA<CommunityFailure>()),
      );
    }
  });
  test('inline G1 avatar reuses strict chunk assembly and restriction removes access', () async {
    final h = Harness();
    addTearDown(h.close);
    const encoded =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=';
    final bytes = base64Decode(encoded),
        version = sha256.convert(base64Decode(encoded)).toString();
    h.mutate = (p) => {
      ...p,
      'ships': [
        {...ship(), 'ownerHasAvatar': true, 'ownerAvatarVersion': version},
      ],
      'owners': [
        {
          'ownerMemberRef': ref(2),
          'profileReference': hash(4),
          'avatarImageData': 'data:image/png;base64,$encoded',
          'avatarVersion': version,
        },
      ],
    };
    await h.adapter.readShips(ref(9));
    final actual = await assembleCommunityMedia(
      (offset, version) => h.adapter.avatarAccess.read!(
        ref(9),
        ref(2),
        offset: offset,
        version: version,
      ),
      'avatar',
      memberRef: ref(2),
      checkCurrent: () {},
    );
    expect(actual, bytes);
    h.mutate = null;
    h.restricted = true;
    await h.adapter.readShips(ref(9));
    await expectLater(
      h.adapter.avatarAccess.read!(ref(9), ref(2), offset: 0),
      throwsA(isA<CommunityFailure>()),
    );
  });
  test('statistics beyond10000 are explicitly unavailable without reading a partial total', () async {
    final h = Harness();
    addTearDown(h.close);
    h.mutate = (p) => {
      ...p,
      'totalCount': 10001,
      'matchedCount': 10001,
      'next': 20,
      'ships': [
        for (var i = 0; i < 20; i++) {...ship(), 'shipRef': ref(i + 10)},
      ],
    };
    await expectLater(
      readCommunityShipStatistics(
        h.adapter,
        ref(9),
        'zh-CN',
        checkCurrent: () {},
      ),
      throwsA(
        isA<CommunityFailure>().having(
          (e) => e.code,
          'code',
          'statisticsUnavailable',
        ),
      ),
    );
    expect(h.requests.where((r) => r.name == 'officialFleet.ships').length, 1);
  });
  test(
    'generation advance retires displayed targets and pending reads',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final old = (await h.adapter.readShips(ref(9))).ships.single;
      h.hold = Completer<void>();
      final pending = h.adapter.readShips(ref(9));
      final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
      for (
        var i = 0;
        i < 20 &&
            h.requests.where((r) => r.name == 'officialFleet.ships').length < 2;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        h.requests.where((r) => r.name == 'officialFleet.ships').length,
        2,
      );
      h.session.advanceGeneration(2);
      expect(h.adapter.ownerTarget(ref(9), old), isNull);
      h.hold!.complete();
      await rejected;
    },
  );
  testWidgets(
    'explicit scope retry revalidates first then makes one fresh read',
    (tester) async {
      final h = Harness()..error = 'official_fleet.identity_unavailable';
      addTearDown(h.close);
      final gate = Completer<void>();
      var revalidated = false;
      await tester.pumpWidget(
        host(
          CommunityShipsPanel(
            port: h.adapter,
            targetRef: ref(9),
            name: 'Fleet',
            onBack: () {},
            retryInvalidatedScope: true,
            ownerTargetFactory: h.adapter.ownerTarget,
            avatarAccess: h.adapter.avatarAccess,
            hangarSharingSourceRef: 'officialFleet:7',
            includeSocialActions: false,
            onRefreshMembership: () async {
              await gate.future;
              h.error = null;
              revalidated = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bridge Pilot'), findsNothing);
      final before = h.requests
          .where((r) => r.name == 'officialFleet.ships')
          .length;
      await tester.tap(find.byKey(const Key('community-ships-retry')));
      await tester.pump();
      expect(
        h.requests.where((r) => r.name == 'officialFleet.ships').length,
        before,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(revalidated, true);
      expect(find.text('Bridge Pilot'), findsWidgets);
      expect(
        h.requests.where((r) => r.name == 'officialFleet.ships').length,
        before + 1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'generation retirement while revalidating never starts a replacement read',
    (tester) async {
      final h = Harness()..error = 'official_fleet.identity_unavailable';
      addTearDown(h.close);
      final gate = Completer<void>();
      await tester.pumpWidget(
        host(
          CommunityShipsPanel(
            port: h.adapter,
            targetRef: ref(9),
            name: 'Fleet',
            onBack: () {},
            retryInvalidatedScope: true,
            hangarSharingSourceRef: 'officialFleet:7',
            onRefreshMembership: () async {
              await gate.future;
              h.error = null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('community-ships-retry')));
      await tester.pump();
      final before = h.requests
          .where((r) => r.name == 'officialFleet.ships')
          .length;
      h.session.advanceGeneration(2);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.name == 'officialFleet.ships').length,
        before,
      );
      expect(find.text('Bridge Pilot'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'source replacement during explicit revalidation retires old retry',
    (tester) async {
      final h = Harness()..error = 'official_fleet.identity_unavailable';
      addTearDown(h.close);
      final gate = Completer<void>();
      await tester.pumpWidget(
        host(
          ValueListenableBuilder<String?>(
            valueListenable: h.source,
            builder: (_, source, _) => CommunityShipsPanel(
              port: h.adapter,
              targetRef: source == 'officialFleet:7' ? ref(9) : ref(10),
              name: 'Fleet',
              onBack: () {},
              retryInvalidatedScope: true,
              hangarSharingSourceRef: source,
              onRefreshMembership: () async {
                await gate.future;
                h.error = null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('community-ships-retry')));
      await tester.pump();
      h.source.value = 'officialFleet:8';
      await tester.pumpAndSettle();
      final before = h.requests
          .where((r) => r.name == 'officialFleet.ships')
          .length;
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.name == 'officialFleet.ships').length,
        before,
      );
      expect(find.text('Bridge Pilot'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed explicit scope verification never restarts a read', (
    tester,
  ) async {
    final h = Harness()..error = 'official_fleet.identity_unavailable';
    addTearDown(h.close);
    await tester.pumpWidget(
      host(
        CommunityShipsPanel(
          port: h.adapter,
          targetRef: ref(9),
          name: 'Fleet',
          onBack: () {},
          retryInvalidatedScope: true,
          hangarSharingSourceRef: 'officialFleet:7',
          onRefreshMembership: () async {
            throw const CommunityFailure('unavailable');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = h.requests
        .where((r) => r.name == 'officialFleet.ships')
        .length;
    await tester.tap(find.byKey(const Key('community-ships-retry')));
    await tester.pumpAndSettle();
    expect(
      h.requests.where((r) => r.name == 'officialFleet.ships').length,
      before,
    );
    expect(find.text('Bridge Pilot'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
