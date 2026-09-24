import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> workspacePayload({
  String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String query = '',
}) => {
  'schemaVersion': 1,
  'targetRef': target,
  'code': 'ORG_A',
  'name': 'Organization A',
  'description': 'Members only details',
  'tags': '探索 · 调查',
  'language': '中文 / English',
  'activeTime': '20:00–01:00',
  'timeZoneId': 'UTC',
  'websiteUrl': 'https://example.org',
  'hasLogo': false,
  'hasBanner': false,
  'activeSystemIds': ['Stanton'],
  'activityWindows': [
    {
      'days': ['Mon', 'Fri'],
      'startTime': '20:00',
      'endTime': '01:00',
      'endsNextDay': true,
    },
  ],
  'externalContacts': [
    {'platform': 'Discord', 'value': 'organization-contact'},
  ],
  'access': {
    for (final key in [
      'isOwner',
      'canEditProfile',
      'canReviewApplications',
      'canRemoveMembers',
      'canCreateInvite',
      'canManageAnnouncements',
    ])
      key: false,
  },
  'query': query,
  'offset': 0,
  'next': null,
  'totalCount': 1,
  'matchedCount': 1,
  'fetchedAt': '2026-09-07T12:00:00Z',
  'members': [
    {
      'memberRef': 'b' * 32,
      'gameName': 'Visible_Game_Name',
      'callsign': '示例成员',
      'roleTitle': '探索',
      'roleColor': '#F2B84B',
      'isSelf': true,
      'isOwner': false,
      'online': true,
      'hasAvatar': false,
      'liveStatus': 'InGame',
      'ship': 'C2 Hercules',
      'location': '奥里森',
      'locationConfidence': null,
      'serverRegion': 'USA',
      'serverShard': 'must-not-be-rendered',
      'arrivalPendingConfirmation': true,
      'arrivalTargetCode': 'ARRIVAL',
      'lastUpdated': '2026-09-07T12:00:00Z',
      'joinedAt': '2026-09-01T12:00:00Z',
    },
  ],
};

Map<String, Object?> mediaChunk(
  Uint8List bytes,
  int offset, {
  String kind = 'logo',
  String? memberRef,
}) {
  final end = (offset + 192 * 1024).clamp(0, bytes.length);
  return {
    'schemaVersion': 1,
    'kind': kind,
    'memberRef': memberRef,
    'version': sha256.convert(bytes).toString(),
    'mimeType': 'image/png',
    'totalBytes': bytes.length,
    'offset': offset,
    'next': end < bytes.length ? end : null,
    'data': base64Encode(bytes.sublist(offset, end)),
  };
}

class WorkspaceTestPort implements CommunityWorkspacePort {
  final changes = StreamController<void>.broadcast(sync: true);
  Future<CommunityWorkspace> Function(String, String, int)? reader;
  Future<Map<String, Object?>> Function(int, String?)? mediaReader;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async => reader == null
      ? CommunityWorkspace.parse(
          workspacePayload(target: targetRef, query: query),
        )
      : reader!(targetRef, query, offset);
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => mediaReader == null
      ? throw const CommunityFailure('unavailable')
      : mediaReader!(offset, version);
}

void main() {
  test(
    'Removed image is not confused with revoked organization membership',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.media'],
        error: 'communities.notFound',
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readMedia('a' * 32, 'logo', offset: 0),
        throwsA(
          isA<CommunityFailure>().having((e) => e.code, 'code', 'notFound'),
        ),
      );
      final port = WorkspaceTestPort();
      port.reader = (_, _, _) async =>
          CommunityWorkspace.parse(workspacePayload()..['hasLogo'] = true);
      port.mediaReader = (_, _) async =>
          throw const CommunityFailure('notFound');
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      await model.load();
      expect(model.workspace, isNotNull);
      expect(model.error, isNull);
      expect(model.mediaFailed, true);
      expect(model.image('logo'), isNull);
    },
  );
  test(
    'Workspace bridge uses dedicated capability and current account only',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.workspace'],
        responses: {'communities.workspace': workspacePayload()},
      );
      addTearDown(host.close);
      final value = await host.adapter.readWorkspace('a' * 32, '', 0);
      expect(value.members.single.displayName, '示例成员');
      expect(value.access['canEditProfile'], false);
      expect(value.activityWindows.single.endsNextDay, true);
      expect(host.requests.last.name, 'communities.workspace');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'query': '',
        'offset': 0,
      });
      expect(host.requests.last.accountContext?.subject, 'test-subject');
    },
  );

  test(
    'Media bridge passes opaque member reference, no account ID or URL',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.media'],
        responses: {
          'communities.media': mediaChunk(
            Uint8List.fromList([1]),
            0,
            kind: 'avatar',
            memberRef: 'b' * 32,
          ),
        },
      );
      addTearDown(host.close);
      await host.adapter.readMedia(
        'a' * 32,
        'avatar',
        memberRef: 'b' * 32,
        offset: 0,
      );
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'kind': 'avatar',
        'memberRef': 'b' * 32,
        'offset': 0,
      });
    },
  );

  test(
    'Missing workspace capability does not read account or directory fallback',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      await expectLater(
        host.adapter.readWorkspace('a' * 32, '', 0),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );

  for (final code in [
    'notAllowed',
    'refreshRequired',
    'identityUnavailable',
    'dataInvalid',
  ]) {
    test('Workspace maps explicit $code without retry', () async {
      final host = CommunityHarness(
        capabilities: ['communities.workspace'],
        error: 'communities.$code',
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readWorkspace('a' * 32, '', 0),
        throwsA(isA<CommunityFailure>().having((e) => e.code, 'code', code)),
      );
      expect(
        host.requests.where((r) => r.name == 'communities.workspace'),
        hasLength(1),
      );
    });
  }

  for (final entry in <String, void Function(Map<String, Object?>)>{
    'schema': (m) => m['schemaVersion'] = 2,
    'target': (m) => m['targetRef'] = 'other',
    'query': (m) => m['query'] = 'other',
    'count': (m) => m['matchedCount'] = 2,
    'offset': (m) => m['offset'] = 1,
    'access': (m) => (m['access'] as Map).remove('canEditProfile'),
    'color': (m) => ((m['members'] as List).single as Map)['roleColor'] = 'bad',
    'memberRef': (m) =>
        ((m['members'] as List).single as Map)['memberRef'] = 'account:123',
  }.entries) {
    test('Invalid workspace ${entry.key} is rejected', () async {
      final data = workspacePayload();
      entry.value(data);
      final host = CommunityHarness(
        capabilities: ['communities.workspace'],
        responses: {'communities.workspace': data},
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readWorkspace('a' * 32, '', 0),
        throwsA(
          isA<CommunityFailure>().having((e) => e.code, 'code', 'dataInvalid'),
        ),
      );
    });
  }

  test(
    '400 KiB media reassembles three chunks with pinned version and final SHA',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(400 * 1024, (i) => i % 256),
      );
      final offsets = <int>[];
      final actual = await assembleCommunityMedia(
        (offset, version) async {
          offsets.add(offset);
          expect(
            version,
            offset == 0 ? null : sha256.convert(bytes).toString(),
          );
          return mediaChunk(bytes, offset);
        },
        'logo',
        checkCurrent: () {},
      );
      expect(actual, bytes);
      expect(offsets, [0, 192 * 1024, 384 * 1024]);
    },
  );

  for (final entry in <String, Object?>{
    'version': 'f' * 64,
    'offset': 1,
    'next': 1,
    'kind': 'banner',
    'memberRef': 'b' * 32,
    'totalBytes': 524289,
    'data': '%%%',
    'mimeType': 'image/svg+xml',
  }.entries) {
    test('Media rejects corrupt ${entry.key}', () async {
      await expectLater(
        assembleCommunityMedia(
          (_, _) async => {
            ...mediaChunk(Uint8List.fromList([1, 2, 3]), 0),
            entry.key: entry.value,
          },
          'logo',
          checkCurrent: () {},
        ),
        throwsFormatException,
      );
    });
  }

  test('Invalidation during a chunk prevents subsequent reads', () async {
    var current = true, requests = 0;
    await expectLater(
      assembleCommunityMedia(
        (offset, _) async {
          requests++;
          current = false;
          return mediaChunk(Uint8List(400 * 1024), offset);
        },
        'logo',
        checkCurrent: () {
          if (!current) throw const CommunityFailure('identityUnavailable');
        },
      ),
      throwsA(isA<CommunityFailure>()),
    );
    expect(requests, 1);
  });

  test(
    'Applicant avatars retain kind, reference and full hash validation',
    () async {
      final bytes = Uint8List(400 * 1024), reference = 'a' * 32;
      final result = await assembleCommunityMedia(
        (offset, _) async =>
            mediaChunk(bytes, offset, kind: 'applicant', memberRef: reference),
        'applicant',
        memberRef: reference,
        checkCurrent: () {},
      );
      expect(result, bytes);
      await expectLater(
        assembleCommunityMedia(
          (offset, _) async =>
              mediaChunk(bytes, offset, kind: 'avatar', memberRef: reference),
          'applicant',
          memberRef: reference,
          checkCurrent: () {},
        ),
        throwsFormatException,
      );
      await expectLater(
        assembleCommunityMedia(
          (offset, _) async =>
              mediaChunk(bytes, offset, kind: 'applicant', memberRef: 'b' * 32),
          'applicant',
          memberRef: reference,
          checkCurrent: () {},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Account invalidation clears visible private data and rejects a late read',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      await model.load();
      expect(model.workspace, isNotNull);
      final delayed = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => delayed.future;
      final reading = model.load();
      expect(model.workspace, isNotNull);
      port.changes.add(null);
      expect(
        model.workspace,
        isNull,
        reason:
            'Account invalidation must clear even during a background refresh.',
      );
      delayed.complete(CommunityWorkspace.parse(workspacePayload()));
      await reading;
      expect(model.workspace, isNull);
      expect(model.error, 'identityUnavailable');
      expect(model.busy, false);
    },
  );

  test(
    'Latest search wins and rejected refresh cannot retain old contacts',
    () async {
      final port = WorkspaceTestPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      final delayed = Completer<CommunityWorkspace>();
      port.reader = (target, query, _) => query == 'old'
          ? delayed.future
          : Future.value(
              CommunityWorkspace.parse(
                workspacePayload(target: target, query: query),
              ),
            );
      final old = model.load(search: 'old');
      await model.load(search: 'new');
      delayed.complete(
        CommunityWorkspace.parse(workspacePayload(query: 'old')),
      );
      await old;
      expect(model.workspace?.query, 'new');
      port.reader = (_, _, _) async =>
          throw const CommunityFailure('notAllowed');
      await model.load();
      expect(model.workspace, isNull);
      expect(model.error, 'notAllowed');
    },
  );

  test(
    'Permission revocation during image load erases workspace and image cache',
    () async {
      final port = WorkspaceTestPort();
      final data = workspacePayload()..['hasLogo'] = true;
      port.reader = (_, _, _) async => CommunityWorkspace.parse(data);
      port.mediaReader = (_, _) async =>
          throw const CommunityFailure('notAllowed');
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      await model.load();
      expect(model.workspace, isNull);
      expect(model.image('logo'), isNull);
      expect(model.error, 'notAllowed');
    },
  );

  test(
    'Example uses real pagination and retains the other organization on leave',
    () async {
      final example = ExampleCommunities();
      addTearDown(example.close);
      final first = await example.readWorkspace(
        '00000000000000000000000000000002',
        '',
        0,
      );
      expect(first.members, hasLength(20));
      expect(first.next, 20);
      expect(
        (await example.readWorkspace(
          '00000000000000000000000000000002',
          '',
          40,
        )).members,
        hasLength(8),
      );
      await example.execute('leave', '00000000000000000000000000000001');
      await expectLater(
        example.readWorkspace('00000000000000000000000000000001', '', 0),
        throwsA(isA<CommunityFailure>()),
      );
      expect(
        (await example.readWorkspace(
          '00000000000000000000000000000002',
          '',
          0,
        )).totalCount,
        48,
      );
    },
  );
}
