import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  for (final size in [120 * 1024, 512 * 1024, 512 * 1024 + 1]) {
    test(
      'affiliation preserves the directory image byte budget: $size',
      () async {
        final harness = _PersonalProfileHostHarness();
        addTearDown(harness.close);
        final image =
            'data:image/png;base64,${base64Encode(List.filled(size, 0))}';
        harness.profileOverrides = {
          'fleetAffiliation': {
            'fleetName': 'Fixture',
            'fleetCode': 'TEST',
            'kind': 'community',
            'logoImageData': image,
          },
        };
        final snapshot = await harness.adapter.read();
        expect(
          snapshot.affiliations.single.logoImageData,
          size <= 512 * 1024 ? image : isNull,
        );
      },
    );
  }
  test(
    'legacy favorite uses catalog model across differing Idris names',
    () async {
      final h = _PersonalProfileHostHarness()..legacy = true;
      addTearDown(h.close);
      final profile = _profilePayload['profile']! as Map<String, Object?>;
      h.profileOverrides = {
        'content': {
          ...(profile['content']! as Map<String, Object?>),
          'favoriteShipCodes': ['AEGS_Idris_P'],
        },
        'hangar': {
          'ships': [
            {
              'code': 'AEGS_Idris_P',
              'displayName': 'Idris-P',
              'presentation': {
                'title': 'Idris-P',
                'catalogId': 'catalog-idrisp',
              },
            },
          ],
        },
      };
      final remote = await h.adapter.read();
      PersonalProfileSnapshot project(List<LocalHangarShip> owned) =>
          projectLocalProfile(
            remote,
            null,
            LocalHangarSnapshot(revision: 1, ships: owned),
            null,
          );
      const current = LocalHangarShip(
        id: 'new-instance',
        title: 'Idris-P Frigate',
        catalogId: 'catalog-idrisp',
      );
      expect(project([current]).favoriteShips.single.formerlyOwned, isFalse);
      expect(project([]).favoriteShips.single.formerlyOwned, isTrue);
      expect(project([current]).favoriteShips.single.formerlyOwned, isFalse);
      expect(
        project([
          const LocalHangarShip(
            id: 'different-variant',
            title: 'Idris-P',
            catalogId: 'catalog-idrism',
          ),
        ]).favoriteShips.single.formerlyOwned,
        isTrue,
      );
    },
  );
  test(
    'catalog combat and utility keep distinct profile category colors',
    () async {
      final h = _PersonalProfileHostHarness()..legacy = true;
      addTearDown(h.close);
      h.profileOverrides = {
        'hangar': {
          'ships': [
            for (final role in ['combat', 'utility'])
              {
                'code': role,
                'displayName': role,
                'importedAt': '2026-01-01T00:00:00Z',
                'roleCategory': role,
              },
          ],
        },
      };
      final summary = (await h.adapter.read()).hangarSummary;
      expect(summary.categories.map((slice) => slice.category).toSet(), {
        PersonalProfileTagCategory.airCombat,
        PersonalProfileTagCategory.ship,
      });
    },
  );
  test(
    'legacy profile ship media and reference prices use Host catalog facts',
    () async {
      final h = _PersonalProfileHostHarness()..legacy = true;
      addTearDown(h.close);
      final profile = _profilePayload['profile']! as Map<String, Object?>;
      h.profileOverrides = {
        'content': {
          ...(profile['content']! as Map<String, Object?>),
          'favoriteShipCodes': ['carrack'],
        },
        'hangar': {
          'ships': [
            for (var i = 0; i < 2; i++)
              {
                'code': 'carrack',
                'displayName': 'Carrack',
                'importedAt': '2026-01-01T00:00:00Z',
                'customImageMediaId': 'old-custom-image',
                'roleCategory': 'exploration',
                'presentation': {
                  'title': 'Anvil Carrack',
                  'cn': '卡拉克',
                  'category': 'exploration',
                  'sizeClass': 'large',
                  'priceUsd': 600,
                  'imageAsset': 'assets/ships/catalog-carrack.jpg',
                  'thumbnailAsset': 'assets/ships/catalog-square-carrack.png',
                },
              },
          ],
        },
        'fleetAffiliation': {
          'fleetName': 'Organization',
          'fleetCode': 'ORG',
          'positionTitle': '成员',
          'kind': 'community',
        },
      };
      final snapshot = await h.adapter.read();
      expect(snapshot.hangarSummary.shipCount, 2);
      expect(snapshot.hangarSummary.estimatedValueLabel, r'$1,200 USD');
      expect(
        snapshot.favoriteShips.single.imageAsset,
        'assets/ships/catalog-carrack.jpg',
      );
      expect(
        snapshot.affiliations.single.kind,
        PersonalProfileAffiliationKind.featuredCommunity,
      );
    },
  );
  test(
    'S2 legacy reads the own-profile contract but cannot write remotely',
    () async {
      final harness = _PersonalProfileHostHarness()..legacy = true;
      addTearDown(harness.close);
      final profile = await harness.adapter.read();
      expect(profile.availability, PersonalProfileAvailability.available);
      expect(harness.requestNames, [
        'account.getCurrent',
        'personalProfile.getSelf',
      ]);
      final result = await harness.adapter.save(_edit);
      expect(result.outcome, PersonalProfileActionOutcome.rejected);
      expect(harness.lastUpdatePayload, isNull);
    },
  );
  test(
    'remote exact weekdays and all WPF rhythms are not generalized',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      final profile = _profilePayload['profile']! as Map<String, Object?>;
      for (final rhythm in {
        '周末为主': PersonalProfileActivityRhythm.weekends,
        '不固定': PersonalProfileActivityRhythm.irregular,
      }.entries) {
        harness.profileOverrides = {
          'content': {
            ...(profile['content']! as Map<String, Object?>),
            'activityRhythm': rhythm.key,
            'availabilityWindows': [
              {
                'days': [1, 3],
                'startTime': '23:30',
                'endTime': '02:15',
              },
              {
                'days': [0],
                'startTime': '08:07',
                'endTime': '10:00',
              },
            ],
          },
        };
        final snapshot = await harness.adapter.read();
        expect(snapshot.availabilityWindows.map((w) => w.days), [
          [1, 3],
          [0],
        ]);
        expect(snapshot.availabilityWindows.first.endsNextDay, isTrue);
        expect(snapshot.activityRhythm, rhythm.value);
        expect(snapshot.timeZoneLabel, 'Asia/Shanghai');
      }
    },
  );
  testWidgets(
    'a stalled profile read remains bounded and discards a late result',
    (tester) async {
      final harness = _PersonalProfileHostHarness(
        delayedRequest: 'personalProfile.getSelf',
        responseDelay: const Duration(seconds: 61),
      );
      addTearDown(harness.close);
      final pending = harness.adapter.read();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      final snapshot = await pending;
      expect(snapshot.availability, PersonalProfileAvailability.unavailable);
      expect(snapshot.allowEditing, isFalse);
      await tester.pump(const Duration(seconds: 2));
      final saved = await harness.adapter.save(_edit);
      expect(saved.outcome, PersonalProfileActionOutcome.rejected);
      expect(harness.lastUpdatePayload, isNull);
    },
  );

  for (final requestName in ['account.getCurrent', 'personalProfile.getSelf']) {
    testWidgets('$requestName allows a bounded queued profile read', (
      tester,
    ) async {
      final harness = _PersonalProfileHostHarness(
        delayedRequest: requestName,
        responseDelay: const Duration(seconds: 20),
      );
      addTearDown(harness.close);
      final pending = harness.adapter.read();
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      final snapshot = await pending;
      expect(snapshot.availability, PersonalProfileAvailability.available);
      expect(snapshot.allowEditing, isTrue);
      expect(harness.requestNames, [
        'account.getCurrent',
        'personalProfile.getSelf',
      ]);
    });
  }

  test('old role codes are localized by the real profile adapter without rewriting user labels', () async {
    final harness = _PersonalProfileHostHarness();
    addTearDown(harness.close);
    final profile = _profilePayload['profile']! as Map<String, Object?>;
    harness.profileOverrides = {
      'content': {
        ...(profile['content']! as Map<String, Object?>),
        'skilledRoles': ['fleet-command', 'assault-trooper', '自定义岗位'],
      },
    };
    final snapshot = await harness.adapter.read();
    expect(snapshot.roles[0].labelKey, 'profile.legacyRole.fleet-command');
    expect(snapshot.roles[1].category, PersonalProfileTagCategory.groundCombat);
    expect(snapshot.roles[2].displayLabel, '自定义岗位');
  });

  test(
    'uses affiliation logo data already present in the profile projection',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      harness.profileOverrides = {
        'fleetAffiliation': {
          'fleetName': "Aster's Wing",
          'fleetCode': 'ASTER',
          'positionTitle': '舰队成员',
          'logoUrl': 'https://cdn.example.test/aster.png',
          'logoImageData':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
              'CAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        },
      };

      final snapshot = await harness.adapter.read();

      expect(
        snapshot.affiliations.single.logoUrl,
        'https://cdn.example.test/aster.png',
      );
      expect(
        snapshot.affiliations.single.logoImageData,
        startsWith('data:image/png;base64,'),
      );
      expect(harness.requestNames, [
        'account.getCurrent',
        'personalProfile.getSelf',
      ]);
    },
  );

  test(
    'rejects unsafe affiliation logo sources without losing affiliation',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      harness.profileOverrides = {
        'fleetAffiliation': {
          'fleetName': "Aster's Wing",
          'fleetCode': 'ASTER',
          'positionTitle': '舰队成员',
          'logoUrl': 'http://example.test/aster.png',
          'logoImageData': 'data:image/svg+xml;base64,PHN2Zy8+',
        },
      };

      final snapshot = await harness.adapter.read();

      expect(snapshot.affiliations.single.name, "Aster's Wing");
      expect(snapshot.affiliations.single.logoUrl, isNull);
      expect(snapshot.affiliations.single.logoImageData, isNull);
    },
  );

  test(
    'missing hangar stays unknown and retains unresolved favorite selections',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      harness.profileOverrides = {'hangar': null};
      final snapshot = await harness.adapter.read();
      expect(snapshot.hangarSummary.isAvailable, isFalse);
      expect(snapshot.hangarSummary.unresolvedFavoriteCount, 1);
      expect(snapshot.favoriteShips, isEmpty);
    },
  );

  test(
    'an explicitly empty hangar is different from unavailable data',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      harness.profileOverrides = {
        'hangar': {'ships': <Object?>[]},
      };
      final snapshot = await harness.adapter.read();
      expect(snapshot.hangarSummary.isAvailable, isTrue);
      expect(snapshot.hangarSummary.shipCount, 0);
    },
  );

  test('reads the owner profile through the Native Host projection', () async {
    final harness = _PersonalProfileHostHarness();

    final snapshot = await harness.adapter.read();

    expect(snapshot.availability, PersonalProfileAvailability.available);
    expect(snapshot.allowEditing, isTrue);
    expect(snapshot.callSign, 'Aster Lin');
    expect(snapshot.gameHandle, 'Aster-Lin');
    expect(snapshot.visibility, PersonalProfileVisibility.everyone);
    expect(snapshot.roles.single.displayLabel, '舰队指挥');
    expect(snapshot.favoriteShips.single.identity.runtimeId, 'ANVL_Carrack');
    expect(snapshot.hangarSummary.shipCount, 1);
    expect(snapshot.gameplayMinutes, 90);
    expect(harness.requestNames, [
      'account.getCurrent',
      'personalProfile.getSelf',
    ]);
    await harness.close();
  });

  test('saves presentation fields through the Native Host', () async {
    final harness = _PersonalProfileHostHarness();
    await harness.adapter.read();

    final result = await harness.adapter.save(
      const PersonalProfileEdit(
        callSign: 'Domino',
        about: '远征与协作。',
        avatarStyle: 2,
        wallpaperId: 'stanton-orbit',
        visibility: PersonalProfileVisibility.friendsOnly,
        moduleLayout: <PersonalProfileModuleLayoutItem>[
          PersonalProfileModuleLayoutItem(
            moduleId: 'favorite-ships',
            size: PersonalProfileModuleSize.three,
            isVisible: true,
            position: 0,
          ),
        ],
      ),
    );

    expect(result.outcome, PersonalProfileActionOutcome.completed);
    expect(harness.requestNames, [
      'account.getCurrent',
      'personalProfile.getSelf',
      'account.getCurrent',
      'personalProfile.updateSelf',
    ]);
    final patch = harness.lastUpdatePayload!['patch']! as Map<String, Object?>;
    expect(patch['expectedRevision'], 4);
    expect(patch['visibility'], 'friendsOnly');
    expect(patch['wallpaperId'], 'stanton-orbit');
    await harness.close();
  });

  test(
    'accepts the expanded profile visibility contract when present',
    () async {
      final harness = _PersonalProfileHostHarness(
        visibility: 'friendsAndMainFleet',
      );

      final snapshot = await harness.adapter.read();

      expect(
        snapshot.visibility,
        PersonalProfileVisibility.friendsAndMainFleet,
      );
      await harness.close();
    },
  );

  test('distinguishes signed out from legacy profile unavailability', () async {
    final signedOut = _PersonalProfileHostHarness(signedIn: false);
    final signedOutSnapshot = await signedOut.adapter.read();
    expect(
      signedOutSnapshot.availability,
      PersonalProfileAvailability.signedOut,
    );
    await signedOut.close();

    final unavailable = _PersonalProfileHostHarness(profileAvailable: false);
    final unavailableSnapshot = await unavailable.adapter.read();
    expect(
      unavailableSnapshot.availability,
      PersonalProfileAvailability.unavailable,
    );
    expect(unavailableSnapshot.failureKey, 'profile.error.unavailable');
    await unavailable.close();
  });

  test('save requires a successfully read editable profile', () async {
    final harness = _PersonalProfileHostHarness();
    addTearDown(harness.close);

    final result = await harness.adapter.save(_edit);

    expect(result.outcome, PersonalProfileActionOutcome.rejected);
    expect(harness.lastUpdatePayload, isNull);
  });

  test('account switch rejects the old page edit without writing', () async {
    final harness = _PersonalProfileHostHarness();
    addTearDown(harness.close);
    await harness.adapter.read();
    harness.subject = 'another-synthetic-subject';

    final result = await harness.adapter.save(_edit);

    expect(result.outcome, PersonalProfileActionOutcome.rejected);
    expect(harness.lastUpdatePayload, isNull);
  });

  test(
    'same account new generation requires reading its profile again',
    () async {
      final harness = _PersonalProfileHostHarness();
      addTearDown(harness.close);
      await harness.adapter.read();
      final invalidated = harness.adapter.invalidations.first;
      await harness.sendAccountChanged();
      await invalidated;

      final rejected = await harness.adapter.save(_edit);
      expect(rejected.outcome, PersonalProfileActionOutcome.rejected);
      expect(harness.lastUpdatePayload, isNull);

      await harness.adapter.read();
      final saved = await harness.adapter.save(_edit);
      expect(saved.outcome, PersonalProfileActionOutcome.completed);
    },
  );

  test('publishes account changes as profile invalidations', () async {
    final harness = _PersonalProfileHostHarness();
    final invalidated = harness.adapter.invalidations.first;

    await harness.sendAccountChanged();

    await invalidated.timeout(const Duration(seconds: 1));
    await harness.close();
  });
}

final class _PersonalProfileHostHarness {
  _PersonalProfileHostHarness({
    this.signedIn = true,
    this.profileAvailable = true,
    this.visibility,
    this.delayedRequest,
    this.responseDelay = Duration.zero,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    _host = pair.host;
    _session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
      requestTimeout: const Duration(seconds: 15),
    );
    adapter = BridgePersonalProfileAdapter(_session);
    _subscription = _host.incoming.listen(_respond);
  }

  final bool signedIn;
  bool legacy = false;
  final bool profileAvailable;
  final String? visibility;
  final String? delayedRequest;
  final Duration responseDelay;
  late final BridgeConnection _host;
  late final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgePersonalProfileAdapter adapter;
  final List<BridgeEnvelope> requests = [];
  Map<String, Object?>? lastUpdatePayload;
  Map<String, Object?> profileOverrides = {};
  String subject = 'synthetic-subject';

  List<String> get requestNames => requests.map((item) => item.name).toList();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    if (request.name == 'bridge.cancel') return;
    if (request.name == delayedRequest) {
      await Future<void>.delayed(responseDelay);
    }
    final context = BridgeAccountContext(
      environment: 'development',
      authority: 'scm-development',
      subject: subject,
    );
    if (request.name == 'account.getCurrent') {
      await _send(request, <String, Object?>{
        'schemaVersion': 1,
        'state': signedIn
            ? (legacy ? 'legacySignedIn' : 'signedIn')
            : 'signedOut',
        'displayName': signedIn ? 'Aster Lin' : null,
        'avatarUrl': null,
      }, context: signedIn ? context : null);
      return;
    }
    if (request.name == 'personalProfile.updateSelf') {
      lastUpdatePayload = request.payload;
      await _send(request, <String, Object?>{
        ..._profilePayload,
        'profile': <String, Object?>{
          ...(_profilePayload['profile']! as Map<String, Object?>),
          'revision': 5,
        },
      }, context: context);
      return;
    }
    if (request.name != 'personalProfile.getSelf') {
      throw StateError('Unexpected request ${request.name}');
    }
    expectSync(request.accountContext?.subject, subject);
    if (!profileAvailable) {
      await _host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: context,
          payload: const <String, Object?>{},
          status: 'error',
          error: const BridgeErrorBody(
            code: 'personal_profile.read_unavailable',
            message: 'Unavailable.',
            retryable: true,
          ),
        ),
      );
      return;
    }
    final basePayload = visibility == null
        ? _profilePayload
        : <String, Object?>{
            ..._profilePayload,
            'profile': <String, Object?>{
              ...(_profilePayload['profile']! as Map<String, Object?>),
              'visibility': visibility,
            },
          };
    final payload = <String, Object?>{
      ...basePayload,
      'profile': <String, Object?>{
        ...(basePayload['profile']! as Map<String, Object?>),
        ...profileOverrides,
      },
    };
    await _send(request, payload, context: context);
  }

  Future<void> sendAccountChanged() => _host.send(
    const BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 5,
      sequence: 1,
      payload: <String, Object?>{'schemaVersion': 1},
    ),
  );

  Future<void> _send(
    BridgeEnvelope request,
    Map<String, Object?> payload, {
    BridgeAccountContext? context,
  }) => _host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: context,
      payload: payload,
      status: 'ok',
    ),
  );

  Future<void> close() async {
    await adapter.close();
    await _subscription.cancel();
    await _session.close();
    await _host.close();
  }
}

const _edit = PersonalProfileEdit(
  callSign: 'Edited Citizen',
  about: 'Synthetic profile edit.',
  avatarStyle: 0,
  wallpaperId: 'none',
  visibility: PersonalProfileVisibility.friendsOnly,
  moduleLayout: [],
);

const _profilePayload = <String, Object?>{
  'schemaVersion': 1,
  'editable': true,
  'profile': <String, Object?>{
    'isPublic': true,
    'revision': 4,
    'avatarStyle': 1,
    'wallpaperId': 'none',
    'identity': <String, Object?>{
      'callSign': 'Aster Lin',
      'gameHandle': 'Aster-Lin',
      'avatarAssetId': null,
    },
    'content': <String, Object?>{
      'showOnlineTime': true,
      'onlineTimeStart': '19:00',
      'onlineTimeEnd': '22:00',
      'activityRhythm': '稳定活跃',
      'introduction': '远征与多人协作。',
      'skilledRoles': <String>['舰队指挥'],
      'supportCapabilities': <String>['驾驶员'],
      'participationInterests': <String>['PVE'],
      'shipWishlist': <String>[],
      'favoriteShipCodes': <String>['ANVL_Carrack'],
      'modules': <Object?>[
        <String, Object?>{
          'id': 'favorite-ships',
          'span': 1,
          'isVisible': true,
          'order': 0,
          'position': 0,
        },
      ],
      'availabilityTimeZoneId': 'Asia/Shanghai',
      'availabilityWindows': <Object?>[
        <String, Object?>{
          'days': <int>[1, 2, 3, 4, 5],
          'startTime': '19:00',
          'endTime': '22:00',
        },
      ],
      'presenceIntent': 'available-support',
    },
    'fleetAffiliation': null,
    'hangar': <String, Object?>{
      'ships': <Object?>[
        <String, Object?>{
          'code': 'ANVL_Carrack',
          'displayName': '克拉克',
          'importedAt': '2026-08-31T12:00:00Z',
          'syncedAt': '2026-09-01T12:00:00Z',
          'roleCategory': '远征',
        },
      ],
    },
    'gameplayStatistics': <String, Object?>{'playTimeSeconds': 5400},
    'isGameplayStatisticsPublic': true,
  },
};
