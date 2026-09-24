import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_local_privacy.dart';
import 'package:starbridge_flutter/features/settings/community_member_override.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  test(
    'publication keeps bounded Host error codes for recovery feedback',
    () async {
      final h = Harness(publication: true);
      addTearDown(h.close);
      await h.adapter.read();
      h.connection.publicationState = 'failed';
      h.connection.publicationError = 'privacy_publication.forbidden';
      expect(
        (await h.adapter.publication('status')).errorCode,
        'privacy_publication.forbidden',
      );
      h.connection.publicationError = 42;
      await expectLater(h.adapter.publication('status'), throwsFormatException);
      h.connection.publicationError = 'x' * 129;
      await expectLater(h.adapter.publication('status'), throwsFormatException);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'privacy.applyPublication',
        ),
        isEmpty,
      );
    },
  );
  test('member directory bridge preserves membership precision and local save lease', () async {
    final h = Harness(communities: true, members: true);
    addTearDown(h.close);
    await h.adapter.read();
    final scope = (await h.adapter.readCommunityTargets()).communities.single
        .choice(fields: 15);
    final page = await h.adapter.readCommunityMembers(scope);
    expect(page.members.single.joinedAt, scope.joinedAt);
    final changed = scope.copyWith(
      memberOverrides: [
        CommunityMemberOverride(
          accountId: page.members.single.accountId,
          joinedAt: page.members.single.joinedAt,
          fields: 0,
        ),
      ],
    );
    final result = await h.adapter.save(
      LocalPrivacySettings.editorDefaults.copyWith(communities: [changed]),
    );
    expect(
      result.settings!.communities!.single.memberOverrides!.single.fields,
      0,
    );
    expect(
      h.connection.requests
          .where((r) => r.name == 'privacy.communityMembers')
          .single
          .payload,
      {
        'schemaVersion': 3,
        'scope': scope.toJson(),
        'offset': 0,
        'revision': null,
      },
    );
    expect(
      h.connection.requests.where((r) => r.name == 'privacy.applyPublication'),
      isEmpty,
    );
  });
  test('member directory does not cross account invalidation', () async {
    final h = Harness(communities: true, members: true);
    addTearDown(h.close);
    final scope = (await h.adapter.readCommunityTargets()).communities.single
        .choice();
    h.connection.holdMembers = Completer<void>();
    final pending = h.adapter.readCommunityMembers(scope);
    final result = expectLater(
      pending,
      throwsA(code('privacy_local.account_changed')),
    );
    await h.connection.membersStarted.future;
    h.connection.invalidate();
    await Future<void>.delayed(Duration.zero);
    h.connection.holdMembers!.complete();
    await result;
  });
  test(
    'member scopes require their own capability, not just organization scopes',
    () async {
      final h = Harness(communities: true);
      addTearDown(h.close);
      final scope = (await h.adapter.readCommunityTargets()).communities.single
          .choice();
      await expectLater(
        h.adapter.readCommunityMembers(scope),
        throwsA(code('host.capability_missing')),
      );
      expect(
        h.connection.requests.where(
          (r) => r.name == 'privacy.communityMembers',
        ),
        isEmpty,
      );
    },
  );
  test(
    'membership reads preserve the edit lease and scope timestamps',
    () async {
      final h = Harness(communities: true);
      addTearDown(h.close);
      await h.adapter.read();
      final targets = await h.adapter.readCommunityTargets();
      expect(
        targets.communities.single.joinedAt,
        '2026-09-12T12:34:56.1234567+00:00',
      );
      final settings = LocalPrivacySettings.editorDefaults.copyWith(
        communities: [targets.communities.single.choice(fields: 1)],
      );
      expect(
        (await h.adapter.save(settings)).settings!.communities!.single.fields,
        1,
      );
      expect(
        h.connection.requests.where(
          (r) => r.name == 'privacy.applyPublication',
        ),
        isEmpty,
      );
    },
  );
  test('older Host does not receive an unsupported scoped request', () async {
    final h = Harness();
    addTearDown(h.close);
    await expectLater(
      h.adapter.readCommunityTargets(),
      throwsA(code('host.capability_missing')),
    );
    expect(h.connection.requests, isEmpty);
  });
  test(
    'first-use metadata is explicit, typed and compatible with older Hosts',
    () async {
      final h = Harness(publication: true);
      addTearDown(h.close);
      await h.adapter.read();
      expect((await h.adapter.publication('status')).firstUseRequired, isNull);
      h.connection.firstUseRequired = true;
      expect((await h.adapter.publication('status')).firstUseRequired, true);
      h.connection.firstUseRequired = false;
      expect((await h.adapter.publication('status')).firstUseRequired, false);
      h.connection.firstUseRequired = 'true';
      await expectLater(h.adapter.publication('status'), throwsFormatException);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'privacy.applyPublication',
        ),
        isEmpty,
      );
    },
  );
  test('automatic reconnect status is read without replaying apply', () async {
    final h = Harness(publication: true);
    addTearDown(h.close);
    await h.adapter.read();
    h.connection.publicationState = 'reconnecting';
    expect((await h.adapter.publication('status')).state, 'reconnecting');
    expect(
      h.connection.requests.where((r) => r.name == 'privacy.applyPublication'),
      isEmpty,
    );
  });
  test(
    'publication is separately gated and sends only an explicit saved revision',
    () async {
      final h = Harness(publication: true);
      addTearDown(h.close);
      await h.adapter.read();
      await h.adapter.save(LocalPrivacySettings.editorDefaults);
      expect(
        h.connection.requests.where(
          (r) => r.name == 'privacy.applyPublication',
        ),
        isEmpty,
      );
      expect((await h.adapter.publication('status')).state, 'inactive');
      await expectLater(
        h.adapter.publication('apply', revision: 0),
        throwsA(code('privacy_local.refresh_required')),
      );
      expect(
        (await h.adapter.publication('apply', revision: 1)).state,
        'applied',
      );
      expect(h.connection.requests.last.payload, {
        'schemaVersion': 1,
        'expectedRevision': 1,
      });
      expect((await h.adapter.publication('stop')).state, 'withdrawn');
      h.connection.subject = 'other';
      await expectLater(
        h.adapter.publication('apply', revision: 1),
        throwsA(code('privacy_local.account_changed')),
      );
      expect(
        h.connection.requests
            .where((r) => r.name == 'privacy.applyPublication')
            .length,
        1,
      );
    },
  );
  test('older Host never receives a publication command', () async {
    final h = Harness();
    addTearDown(h.close);
    await h.adapter.read();
    await expectLater(
      h.adapter.publication('status'),
      throwsA(code('host.capability_missing')),
    );
    expect(
      h.connection.requests.where((r) => r.name == 'privacy.publicationStatus'),
      isEmpty,
    );
  });
  test(
    'WPF fields round trip without retired room groups or friends defaults',
    () {
      final settings = LocalPrivacySettings(
        publicationEnabled: false,
        fleetFields: 9,
        fleetAdministratorsCanView: true,
        fleetAllMembersCanView: false,
        fleetVisibilityGroupIds: ['group-1'],
        roomFields: 20,
        roomAllMembersCanView: true,
      );
      expect(
        LocalPrivacySettings.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
      expect(
        () => settings.fleetVisibilityGroupIds.add('new'),
        throwsUnsupportedError,
      );
      final malformed = settings.toJson();
      (malformed['room'] as Map)['visibilityGroupIds'] = ['retired'];
      expect(
        () => LocalPrivacySettings.fromJson(malformed),
        throwsFormatException,
      );
      final invalid = settings.toJson();
      (invalid['fleet'] as Map)['fields'] = 64;
      expect(
        () => LocalPrivacySettings.fromJson(invalid),
        throwsFormatException,
      );
    },
  );

  test('missing capability performs no requests', () async {
    final h = Harness(capability: false);
    addTearDown(h.close);
    await expectLater(
      h.adapter.read(),
      throwsA(code('host.capability_missing')),
    );
    expect(h.connection.requests, isEmpty);
  });
  test(
    'missing record is not consent, explicit save reopens only local choices',
    () async {
      final h = Harness();
      addTearDown(h.close);
      expect((await h.adapter.read()).settings, isNull);
      final snapshot = await h.adapter.save(
        LocalPrivacySettings.editorDefaults,
      );
      expect(snapshot.revision, 1);
      expect(
        (await h.adapter.read()).settings!.toJson(),
        LocalPrivacySettings.editorDefaults.toJson(),
      );
      expect(
        h.connection.requests.every(
          (r) => const {
            'account.getCurrent',
            'privacy.localRead',
            'privacy.localSave',
          }.contains(r.name),
        ),
        isTrue,
      );
      expect(
        h.connection.requests
            .where((r) => r.name.startsWith('privacy.'))
            .every((r) => r.accountContext?.subject == 'owner'),
        isTrue,
      );
    },
  );
  test('cannot save without reading or after the account changes', () async {
    final h = Harness();
    addTearDown(h.close);
    await expectLater(
      h.adapter.save(LocalPrivacySettings.editorDefaults),
      throwsA(code('privacy_local.refresh_required')),
    );
    await h.adapter.read();
    h.connection.subject = 'different';
    await expectLater(
      h.adapter.save(LocalPrivacySettings.editorDefaults),
      throwsA(code('privacy_local.account_changed')),
    );
    expect(h.connection.saves, isEmpty);
  });
  test('signed out read does not open the local record', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.state = 'signedOut';
    await expectLater(
      h.adapter.read(),
      throwsA(code('privacy_local.account_changed')),
    );
    expect(h.connection.requests.map((r) => r.name), ['account.getCurrent']);
  });
  test(
    'a lost save response retries the same operation and revision',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.adapter.read();
      h.connection.failAfterCommit = true;
      await expectLater(
        h.adapter.save(LocalPrivacySettings.editorDefaults),
        throwsA(code('bridge.timeout')),
      );
      h.connection.failAfterCommit = false;
      expect(
        (await h.adapter.save(LocalPrivacySettings.editorDefaults)).revision,
        1,
      );
      expect(
        h.connection.saves.map((r) => r.payload['operationId']).toSet().length,
        1,
      );
      expect(h.connection.saves.map((r) => r.payload['expectedRevision']), [
        0,
        0,
      ]);
    },
  );
  test(
    'conflict requires a new read instead of retrying a stale lease',
    () async {
      final h = Harness();
      addTearDown(h.close);
      await h.adapter.read();
      h.connection.saveError = 'privacy_local.conflict';
      await expectLater(
        h.adapter.save(LocalPrivacySettings.editorDefaults),
        throwsA(code('privacy_local.conflict')),
      );
      await expectLater(
        h.adapter.save(LocalPrivacySettings.editorDefaults),
        throwsA(code('privacy_local.refresh_required')),
      );
      expect(h.connection.saves.length, 1);
    },
  );
  test('an invalidation prevents late reads from enabling a save', () async {
    final h = Harness();
    addTearDown(h.close);
    h.connection.holdRead = Completer<void>();
    final pending = h.adapter.read();
    final result = expectLater(
      pending,
      throwsA(code('privacy_local.account_changed')),
    );
    await h.connection.readStarted.future;
    h.connection.invalidate();
    await Future<void>.delayed(Duration.zero);
    h.connection.holdRead!.complete();
    await result;
    await expectLater(
      h.adapter.save(LocalPrivacySettings.editorDefaults),
      throwsA(code('privacy_local.refresh_required')),
    );
    expect(h.connection.saves, isEmpty);
  });
  test(
    'a response cannot turn a local save into claimed remote publication',
    () async {
      final h = Harness();
      addTearDown(h.close);
      h.connection.publicationAvailable = true;
      await expectLater(h.adapter.read(), throwsFormatException);
      await expectLater(
        h.adapter.save(LocalPrivacySettings.editorDefaults),
        throwsA(code('privacy_local.refresh_required')),
      );
    },
  );
}

Matcher code(String value) =>
    isA<BridgeClientException>().having((e) => e.code, 'code', value);

class Harness {
  Harness({
    bool capability = true,
    bool publication = false,
    bool communities = false,
    bool members = false,
  }) {
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    session.acceptHostCapabilities(
      capability
          ? [
              'privacy.local',
              if (publication) 'privacy.publication',
              if (communities) 'privacy.communityScopes',
              if (members) 'privacy.communityMemberScopes',
            ]
          : [],
    );
    adapter = BridgeLocalPrivacy(session);
  }
  final connection = PrivacyConnection();
  late final BridgeClientSession session;
  late final BridgeLocalPrivacy adapter;
  Future<void> close() async {
    await adapter.close();
    await session.close();
  }
}

class PrivacyConnection implements BridgeConnection {
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  Iterable<BridgeEnvelope> get saves =>
      requests.where((r) => r.name == 'privacy.localSave');
  Map<String, Object?>? settings;
  int revision = 0;
  String? operation;
  String subject = 'owner';
  String state = 'signedIn';
  String publicationState = 'inactive';
  Object? publicationError;
  Object? firstUseRequired;
  bool failAfterCommit = false;
  bool publicationAvailable = false;
  String? saveError;
  Completer<void>? holdRead;
  final readStarted = Completer<void>();
  Completer<void>? holdMembers;
  final membersStarted = Completer<void>();
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  void invalidate() => stream.add(
    BridgeEnvelope.fromJson({
      'protocolVersion': 1,
      'messageType': 'event',
      'name': 'account.changed',
      'sessionGeneration': 7,
      'sequence': 1,
      'payload': <String, Object?>{},
    }),
  );
  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.messageType != 'request') return;
    requests.add(request);
    if (request.name == 'privacy.communityMembers' && holdMembers != null) {
      membersStarted.complete();
      await holdMembers!.future;
    }
    if (request.name == 'privacy.localRead' && holdRead != null) {
      readStarted.complete();
      await holdRead!.future;
    }
    final save = request.name == 'privacy.localSave';
    if (save &&
        saveError == null &&
        operation != request.payload['operationId']) {
      settings = (request.payload['settings'] as Map).cast<String, Object?>();
      operation = request.payload['operationId'] as String;
      revision++;
    }
    final error = save
        ? saveError ?? (failAfterCommit ? 'bridge.timeout' : null)
        : null;
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': 7,
        'status': error == null ? 'ok' : 'error',
        if (error != null)
          'error': {'code': error, 'message': 'fixture', 'retryable': true},
        'accountContext': {
          'environment': 'test',
          'authority': 'issuer',
          'subject': subject,
        },
        'payload': request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': state}
            : request.name == 'privacy.communityTargets'
            ? {
                'schemaVersion': 2,
                'primaryFleetCode': 'A',
                'communities': [
                  {
                    'code': 'A',
                    'name': 'Organization A',
                    'joinedAt': '2026-09-12T12:34:56.1234567+00:00',
                  },
                ],
              }
            : request.name == 'privacy.communityMembers'
            ? {
                'schemaVersion': 3,
                'code': 'A',
                'joinedAt': '2026-09-12T12:34:56.1234567+00:00',
                'revision': 'A' * 64,
                'offset': 0,
                'total': 1,
                'members': [
                  {
                    'accountId': 'fixture-member',
                    'joinedAt': '2026-09-12T12:34:56.1234567+00:00',
                    'name': 'Member',
                    'handle': 'Member_Handle',
                    'defaultCanView': true,
                    'isSelf': false,
                    'legacyGroupFields': 0,
                  },
                ],
              }
            : request.name == 'privacy.publicationStatus' ||
                  request.name == 'privacy.applyPublication' ||
                  request.name == 'privacy.stopPublication'
            ? {
                'schemaVersion': 1,
                'supportedFields': 15,
                'state': switch (request.name) {
                  'privacy.applyPublication' => 'applied',
                  'privacy.stopPublication' => 'withdrawn',
                  _ => publicationState,
                },
                'appliedRevision': revision,
                'errorCode': publicationError,
                if (firstUseRequired != null)
                  'firstUseRequired': firstUseRequired,
              }
            : {
                'schemaVersion': 1,
                'revision': revision,
                'settings': settings,
                'operationId': operation,
                'savedAt': revision == 0 ? null : '2026-01-01T00:00:00Z',
                'publicationAvailable': publicationAvailable,
              },
      }),
    );
  }
}
