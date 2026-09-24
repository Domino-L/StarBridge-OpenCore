import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  test('visibility saves only audience and rejects a lease after account invalidation', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.read();
    final state = await h.port.readVisibility();
    final result = await h.port.saveVisibility(state, PersonalProfileVisibility.friendsFleetAndOrganizations);
    expect(result.visibility, PersonalProfileVisibility.friendsFleetAndOrganizations);
    expect(h.connection.content, isNull);
    expect(h.remote.writes, 0);
    final save = h.connection.requests.last;
    expect(save.name, 'personalProfile.saveVisibility');
    expect(save.payload.keys.toSet(), {'schemaVersion', 'expectedRevision', 'visibility'});
    h.connection.stream.add(BridgeEnvelope.fromJson({
      'protocolVersion': 1, 'messageType': 'event', 'name': 'personalProfile.changed',
      'sessionGeneration': 7, 'sequence': 1, 'payload': {'schemaVersion': 1}}));
    await Future<void>.delayed(Duration.zero);
    await h.port.read();
    final count = h.connection.requests.length;
    await expectLater(h.port.saveVisibility(result, PersonalProfileVisibility.everyone), throwsStateError);
    expect(h.connection.requests.length, count);
  });
  test('former ownership is model-based while favorites retain instance references', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.port.save(edit(await h.port.read(), ids: [shipA]));
    final before = h.hangar.snapshot.ships;
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 2,
      ships: [before[1]],
      formerShips: [before[0]],
    );
    var profile = await h.port.read();
    expect(profile.favoriteShips.single.formerlyOwned, isFalse);
    expect(profile.local!.choices.length, 1);
    expect(profile.hangarSummary.shipCount, 1);
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 3,
      ships: [],
      formerShips: before,
    );
    profile = await h.port.read();
    expect(profile.favoriteShips.single.identity.runtimeId, shipA);
    expect(profile.favoriteShips.single.formerlyOwned, isTrue);
    expect(profile.local!.choices.length, 1);
    expect(profile.local!.choices.single.formerlyOwned, isTrue);
    expect(profile.hangarSummary.shipCount, 0);
    expect(profile.hangarSummary.unresolvedFavoriteCount, 0);
    h.hangar.snapshot = LocalHangarSnapshot(
      revision: 4,
      ships: [before[1]],
      formerShips: [before[0]],
    );
    expect((await h.port.read()).favoriteShips.single.formerlyOwned, isFalse);
  });
  test('S2 empty defaults inherit old data without overwriting edits or explicit clears', () async {
    final remote = await InMemoryPersonalProfileAdapter.forReview(
      signedIn: true,
    ).read();
    final content = <String, Object?>{
      'callSign': 'Local name',
      'introduction': '',
      'avatarStyle': 1,
      'wallpaperId': 'local-wallpaper',
      'favoriteShipIds': <String>[],
      'modules': [
        {
          'id': 'favorite-ships',
          'span': 3,
          'isVisible': true,
          'position': 0,
          'favoriteShipIds': <String>[],
        },
      ],
    };
    final inherited = projectLocalProfile(
      remote,
      content,
      null,
      null,
      legacyAccount: true,
    );
    expect(inherited.about, remote.about);
    expect(inherited.favoriteShips.length, remote.favoriteShips.length);
    expect(inherited.callSign, 'Local name');
    expect(inherited.wallpaperId, 'local-wallpaper');
    expect(content['introduction'], '');
    final edited = projectLocalProfile(
      remote,
      {...content, 'introduction': 'My edit'},
      null,
      null,
      legacyAccount: true,
    );
    expect(edited.about, 'My edit');
    final cleared = projectLocalProfile(
      remote,
      {...content, 'preserveEmptyFields': true},
      null,
      null,
      legacyAccount: true,
    );
    expect(cleared.about, '');
    expect(cleared.favoriteShips, isEmpty);
  });
  test(
    'S2 local save remains available while the optional Relay read fails',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.connection.displayName = 'Legacy Commander';
      h.connection.avatarImageData = 'data:image/png;base64,account-photo';
      h.remote.readError = StateError('Relay unavailable');
      await h.port.save(edit(await h.port.read(), ids: [shipA]));
      final profile = await h.port.read();
      expect(profile.favoriteShips.length, 1);
      expect(profile.avatarImageData, h.connection.avatarImageData);
      expect(h.connection.content!.containsKey('avatarImageData'), isFalse);
      expect(h.connection.revision, 1);
      expect(h.remote.reads, 2);
      expect(h.remote.writes, 0);
    },
  );
  test(
    'S2 profile retains remote data when the new local hangar is absent',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.state = 'legacySignedIn';
      h.connection.authority = 'starbridge-relay-test';
      h.hangar.snapshot = const LocalHangarSnapshot(revision: 0, ships: []);
      final expected = await h.remote.source.read();
      final actual = await h.port.read();
      expect(actual.about, expected.about);
      expect(actual.gameplayMinutes, expected.gameplayMinutes);
      expect(actual.affiliations.length, expected.affiliations.length);
      expect(actual.hangarSummary.shipCount, expected.hangarSummary.shipCount);
      expect(
        actual.hangarSummary.isAvailable,
        expected.hangarSummary.isAvailable,
      );
      expect(actual.favoriteShips.length, expected.favoriteShips.length);
      expect(h.connection.revision, 0);
      expect(h.remote.writes, 0);
      h.hangar.snapshot = const LocalHangarSnapshot(revision: 1, ships: []);
      final cleared = await h.port.read();
      expect(cleared.hangarSummary.shipCount, 0);
      expect(cleared.hangarSummary.isAvailable, isTrue);
    },
  );
  test(
    'hangar and personal page use identical catalog facts and instance totals',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.hangar.snapshot = const LocalHangarSnapshot(
        revision: 2,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            catalogId: 'catalog-carrack',
            category: 'exploration',
            sizeClass: 'large',
            deliveryStatus: 'flyable',
            priceUsd: 600,
            imageAsset: 'assets/ships/catalog-carrack.jpg',
            thumbnailAsset: 'assets/ships/catalog-square-carrack.png',
          ),
          LocalHangarShip(
            id: shipB,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            catalogId: 'catalog-carrack',
            category: 'exploration',
            sizeClass: 'large',
            deliveryStatus: 'flyable',
            priceUsd: 600,
            imageAsset: 'assets/ships/catalog-carrack.jpg',
          ),
          LocalHangarShip(
            id: 'unknown',
            title: 'Unlisted',
            imageAsset: 'C:/private/a.jpg',
            thumbnailAsset: 'C:/private/a.jpg',
          ),
        ],
      );
      await h.port.save(edit(await h.port.read(), ids: [shipA, shipB]));
      final profile = await h.port.read();
      final totals = LocalHangarTotals(
        h.hangar.snapshot.ships.map(LocalHangarPresentation.fromSaved),
      );
      expect(profile.hangarSummary.shipCount, totals.count);
      expect(profile.hangarSummary.unpricedCount, totals.unpricedCount);
      expect(profile.hangarSummary.estimatedValueLabel, r'$1,200 USD');
      expect(profile.hangarSummary.categories.map((c) => c.count), [2, 1]);
      expect(profile.favoriteShips.length, 2);
      expect(
        profile.favoriteShips.first.imageAsset,
        'assets/ships/catalog-carrack.jpg',
      );
      expect(
        profile.favoriteShips.first.roleKey,
        'profile.local.category.exploration',
      );
      expect(profile.favoriteShips.first.sizeKey, 'profile.local.size.large');
      expect(profile.favoriteShips.first.valueLabel, r'$600 USD');
      expect(profile.local!.choices.last.imageAsset, isEmpty);
      expect(
        profile.favoriteShips.first.thumbnailAsset,
        'assets/ships/catalog-square-carrack.png',
      );
      expect(profile.favoriteShips.last.thumbnailAsset, isEmpty);
      expect(profile.local!.choices.last.thumbnailAsset, isEmpty);
      expect(h.remote.writes, 0);
    },
  );

  testWidgets(
    'local catalog values and unknown count fit the real profile page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      h.hangar.snapshot = const LocalHangarSnapshot(
        revision: 2,
        ships: [
          LocalHangarShip(
            id: shipA,
            title: 'Carrack',
            cn: '克拉克',
            liner: 'Anvil',
            category: 'exploration',
            sizeClass: 'large',
            priceUsd: 600,
            imageAsset: 'assets/ships/carrack.png',
          ),
          LocalHangarShip(id: shipB, title: 'Unlisted'),
        ],
      );
      await tester.runAsync(
        () async => h.port.save(edit(await h.port.read(), ids: [shipA])),
      );
      await tester.pumpWidget(
        StarBridgeApp(
          composition: AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            accountPort: InMemoryAccountAdapter.forReview(
              AccountReviewState.signedIn,
            ),
            personalProfilePort: h.port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('profile-hangar-value-panel')),
      );
      expect(find.text('已知估值'), findsOneWidget);
      expect(find.text('1 艘未计价'), findsOneWidget);
      expect(find.textContaining('未知用途'), findsWidgets);
      expect(find.textContaining('profile.local.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.session.close);
    },
  );
  test('local edit survives reopen without a remote write or read-side file creation', () async {
    final h = Harness();
    addTearDown(h.close);
    final before = await h.port.read();
    expect(before.local!.choices.length, 2);
    expect(before.hangarSummary.shipCount, 2);
    expect(h.connection.content, isNull);
    expect(
      (await h.port.save(edit(before, ids: [shipA]))).outcome,
      PersonalProfileActionOutcome.completed,
    );
    expect(h.remote.writes, 0);
    expect(h.connection.content!['favoriteShipIds'], [shipA]);
    final after = await h.port.read();
    expect(after.callSign, 'Local call sign');
    expect(after.favoriteShips.single.identity.runtimeId, shipA);
    expect(after.favoriteShips.single.identity.simplifiedChineseName, '克拉克');
    await h.port.close();
    h.port = BridgeLocalPersonalProfile(
      h.session,
      remote: h.remote,
      hangar: () => h.hangar,
    );
    expect((await h.port.read()).about, 'Local introduction');
    expect(
      h.connection.requests.where(
        (r) => r.name == 'personalProfile.updateSelf',
      ),
      isEmpty,
    );
  });

  test(
    'failed save retries same operation and does not report success',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final before = await h.port.read();
      h.connection.failSave = true;
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.failed,
      );
      expect(h.connection.content, isNull);
      h.connection.failSave = false;
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      final saves = h.connection.requests
          .where((r) => r.name == 'personalProfile.localSave')
          .toList();
      expect(saves[0].payload['operationId'], saves[1].payload['operationId']);
      expect(saves[1].payload.containsKey('visibility'), isFalse);
      final confirmed = await h.port.read();
      h.connection.failSave = true;
      h.connection.commitOnFailure = true;
      expect(
        (await h.port.save(edit(confirmed))).outcome,
        PersonalProfileActionOutcome.failed,
      );
      final lostOperation = h.connection.operation;
      final recovered = await h.port.read();
      h.connection.failSave = false;
      expect(
        (await h.port.save(edit(recovered))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.connection.operation, isNot(lostOperation));
      expect(h.connection.revision, 3);
    },
  );

  test(
    'account generation change rejects old edits and clears choices',
    () async {
      final h = Harness();
      addTearDown(h.close);
      final before = await h.port.read();
      h.session.advanceGeneration(8);
      h.connection.generation = 8;
      h.connection.state = 'signedOut';
      expect(
        (await h.port.save(edit(before))).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(h.connection.content, isNull);
      expect(
        (await h.port.read()).availability,
        PersonalProfileAvailability.signedOut,
      );
    },
  );

  test(
    'saved local page remains usable when remote read is unavailable',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.port.save(edit(await h.port.read(), ids: [shipA]));
      h.remote.available = false;
      final local = await h.port.read();
      expect(local.availability, PersonalProfileAvailability.available);
      expect(local.local!.remoteAvailable, isFalse);
      expect(local.gameHandle, isEmpty);
      expect(local.callSign, 'Local call sign');
      expect(local.favoriteShips.single.identity.runtimeId, shipA);
      expect(
        (await h.port.save(edit(local))).outcome,
        PersonalProfileActionOutcome.completed,
      );
    },
  );

  test(
    'missing hangar differs from saved empty and keeps unresolved favorite IDs',
    () async {
      final remote = await InMemoryPersonalProfileAdapter.forReview(
        signedIn: true,
      ).read();
      final content = <String, Object?>{
        'callSign': 'Saved',
        'introduction': '',
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'modules': <Object?>[],
        'favoriteShipIds': [shipA],
      };
      final missing = projectLocalProfile(
        const PersonalProfileSnapshot.unavailable(),
        content,
        null,
        null,
      );
      expect(missing.hangarSummary.isAvailable, isFalse);
      expect(missing.local!.favoriteShipIds, [shipA]);
      expect(missing.hangarSummary.unresolvedFavoriteCount, 1);
      final empty = projectLocalProfile(
        remote,
        content,
        const LocalHangarSnapshot(revision: 1, ships: []),
        null,
      );
      expect(empty.hangarSummary.isAvailable, isTrue);
      expect(empty.hangarSummary.shipCount, 0);
      final unsaved = projectLocalProfile(
        const PersonalProfileSnapshot.unavailable(),
        content,
        const LocalHangarSnapshot(revision: 0, ships: []),
        null,
      );
      expect(unsaved.hangarSummary.isAvailable, isFalse);
    },
  );

  test('hangar save event refreshes the module without copying ships into profile storage', () async {
    final h = Harness();
    final module = createPersonalProfileModule(h.port);
    addTearDown(() async {
      module.dispose();
      await h.session.close();
    });
    await module.initialize();
    expect(module.projection.value.hangarSummary.shipCount, 2);
    h.hangar.snapshot = const LocalHangarSnapshot(revision: 2, ships: []);
    h.connection.stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'hangarReader.changed',
        'sessionGeneration': 7,
        'sequence': 1,
        'payload': {'schemaVersion': 1},
      }),
    );
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(module.projection.value.hangarSummary.shipCount, 0);
    expect(module.projection.value.hangarSummary.isAvailable, isTrue);
    expect(h.connection.content, isNull);
  });

  testWidgets(
    'local editor saves favorites, keeps failed draft and hides publish controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = Harness();
      await tester.pumpWidget(
        StarBridgeApp(
          composition: AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            accountPort: InMemoryAccountAdapter.forReview(
              AccountReviewState.signedIn,
            ),
            personalProfilePort: h.port,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-preview')), findsNothing);
      await tester.tap(find.byKey(const Key('profile-edit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('profile-visibility-selector')),
        findsNothing,
      );
      expect(find.text('保存到本机'), findsOneWidget);
      final picker = find.byKey(
        const Key('profile-module-edit-favorite-ships'),
      );
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-favorite-$shipA')));
      await tester.tap(find.byKey(const Key('profile-favorites-apply')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('profile-call-sign-field')),
      );
      await tester.enterText(
        find.byKey(const Key('profile-call-sign-field')),
        'Local draft',
      );
      h.connection.failSave = true;
      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
      expect(find.text('Local draft'), findsOneWidget);
      h.connection.failSave = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(h.connection.content!['callSign'], 'Local draft');
      expect(h.connection.content!['favoriteShipIds'], [shipA]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.session.close);
    },
  );
}

const shipA = '11111111111111111111111111111111';
const shipB = '22222222222222222222222222222222';
PersonalProfileEdit edit(
  PersonalProfileSnapshot profile, {
  List<String>? ids,
  PersonalProfilePlayStyle? playStyle,
  PersonalProfileSchedule? schedule,
}) => PersonalProfileEdit(
  callSign: 'Local call sign',
  about: 'Local introduction',
  avatarStyle: 1,
  wallpaperId: 'none',
  visibility: profile.visibility,
  moduleLayout: profile.moduleLayout,
  favoriteShipIds: ids,
  playStyle: playStyle,
  schedule: schedule,
);

class Harness {
  Harness() {
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    port = BridgeLocalPersonalProfile(
      session,
      remote: remote,
      hangar: () => hangar,
    );
  }
  final connection = LocalProfileConnection();
  final remote = RemoteProfile();
  final hangar = SavedHangar();
  late final BridgeClientSession session;
  late BridgeLocalPersonalProfile port;
  Future<void> close() async {
    await port.close();
    await session.close();
  }
}

class RemoteProfile implements PersonalProfilePort {
  final source = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  bool available = true;
  Object? readError;
  Completer<PersonalProfileSnapshot>? pendingRead;
  int writes = 0;
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<PersonalProfileSnapshot> read() async {
    reads++;
    if (readError case final error?) throw error;
    if (pendingRead case final pending?) return pending.future;
    return available
        ? source.read()
        : const PersonalProfileSnapshot.unavailable();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    writes++;
    throw StateError('Local flow must not write remotely.');
  }

  @override
  Future<void> close() async {}
}

class SavedHangar implements LocalHangarPort {
  LocalHangarSnapshot snapshot = const LocalHangarSnapshot(
    revision: 1,
    ships: [
      LocalHangarShip(
        id: shipA,
        title: 'Carrack',
        cn: '克拉克',
        tw: '克拉克',
        liner: 'Anvil',
      ),
      LocalHangarShip(
        id: shipB,
        title: 'Carrack',
        cn: '克拉克',
        tw: '克拉克',
        liner: 'Anvil',
      ),
    ],
  );
  @override
  Future<LocalHangarSnapshot> read() async => snapshot;
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw UnimplementedError();
}

class LocalProfileConnection implements BridgeConnection {
  int visibilityRevision = 1;
  String visibility = 'private';
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  Map<String, Object?>? content;
  int revision = 0;
  String? operation;
  bool failSave = false;
  bool commitOnFailure = false;
  int generation = 7;
  String state = 'signedIn';
  String authority = 'issuer';
  String? displayName;
  String? avatarImageData;
  String? localReadError;
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.messageType != 'request') return;
    requests.add(request);
    if (request.name == 'personalProfile.saveVisibility') {
      visibility = request.payload['visibility'] as String;
      visibilityRevision++;
    }
    final save = request.name == 'personalProfile.localSave';
    final errorCode = save && failSave
        ? 'profile_local.write_failed'
        : request.name == 'personalProfile.localRead'
        ? localReadError
        : null;
    if (save && (!failSave || commitOnFailure)) {
      content = (request.payload['content'] as Map).cast<String, Object?>();
      revision++;
      operation = request.payload['operationId'] as String;
    }
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': generation,
        'status': errorCode != null ? 'error' : 'ok',
        if (errorCode != null)
          'error': {'code': errorCode, 'message': 'fixture', 'retryable': true},
        'accountContext': {
          'environment': 'test',
          'authority': authority,
          'subject': 'owner',
        },
        'payload': request.name == 'account.getCurrent'
            ? {
                'schemaVersion': 1,
                'state': state,
                'displayName': displayName,
                'avatarImageData': avatarImageData,
              }
            : request.name.endsWith('Visibility') ? {
                'schemaVersion': 1, 'revision': visibilityRevision, 'visibility': visibility,
              } : {
                'schemaVersion': 1,
                'revision': revision,
                'operationId': operation,
                'content': content,
                'savedAt': revision == 0 ? null : '2026-01-01T00:00:00Z',
                'timeZones': [
                  {'id': 'UTC', 'label': 'UTC'},
                  {'id': 'America/Regina', 'label': '(UTC-06:00) Regina'},
                ],
              },
      }),
    );
  }
}
