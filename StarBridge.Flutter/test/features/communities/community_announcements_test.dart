import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

const target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const itemRef = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const memberRef = 'cccccccccccccccccccccccccccccccc';
const caps = ['communities.announcements', 'communities.announcementDetail'];
Map<String, Object?> announcementAuthor({bool hasAvatar = true}) => {
  'memberRef': memberRef,
  'callsign': 'Author',
  'gameId': 'Pilot',
  'roleTitle': '成员',
  'roleColor': '#47AAEE',
  'hasAvatar': hasAvatar,
};
Map<String, Object?> announcementRow() => {
  'announcementRef': itemRef,
  'title': 'Announcement',
  'content': '',
  'state': 'published',
  'revision': 2,
  'publishedAt': '2026-09-07T00:00:00Z',
  'updatedAt': '2026-09-08T00:00:00Z',
  'archivedAt': null,
  'withdrawnAt': null,
  'author': announcementAuthor(),
  'editor': announcementAuthor(),
};
Map<String, Object?> announcementPage() => {
  'schemaVersion': 1,
  'targetRef': target,
  'revision': 30,
  'canManage': true,
  'current': announcementRow(),
  'history': <Object?>[],
  'offset': 0,
  'next': null,
  'totalHistoryCount': 0,
  'refreshedAt': '2026-09-08T00:00:00Z',
};

final class _Details implements CommunityAnnouncementsPort {
  _Details() {
    final image = List<int>.filled(400 * 1024, 0)
      ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
    avatar = 'data:image/png;base64,${base64Encode(image)}';
    bytes = utf8.encode(
      jsonEncode({
        'authorAvatarImageData': avatar,
        'editorAvatarImageData': avatar,
      }),
    );
  }
  late String avatar;
  late List<int> bytes;
  String? failure;
  void Function()? onRead;
  int calls = 0;
  @override
  bool get announcementsAvailable => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) async => CommunityAnnouncementsPage.parse(announcementPage());
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String reference,
    int offset,
    String? version,
  ) async {
    calls++;
    onRead?.call();
    final length = (bytes.length - offset).clamp(0, 192 * 1024);
    final result = <String, Object?>{
      'schemaVersion': 1,
      'targetRef': targetRef,
      'announcementRef': reference,
      'offset': offset,
      'next': offset + length < bytes.length ? offset + length : null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes.sublist(offset, offset + length)),
      'canManage': calls != 2,
    };
    switch (failure) {
      case 'wrong-target':
        result['targetRef'] = memberRef;
      case 'wrong-item':
        result['announcementRef'] = memberRef;
      case 'wrong-offset':
        result['offset'] = offset + 1;
      case 'wrong-next':
        result['next'] = null;
      case 'wrong-hash':
        result['version'] = '0' * 64;
      case 'big':
        result['totalBytes'] = 1700 * 1024;
      case 'permission':
        result['canManage'] = 'false';
      case 'changed-version':
        if (calls > 1) result['version'] = '0' * 64;
      case 'short-chunk':
        result['data'] = base64Encode([1, 2, 3]);
    }
    return result;
  }
}

void main() {
  test('production adapter needs exact capabilities and sends current account context', () async {
    final host = CommunityHarness(
      capabilities: caps,
      responses: {'communities.announcements': announcementPage()},
    );
    addTearDown(host.close);
    expect(host.adapter.announcementsAvailable, true);
    final page = await host.adapter.readAnnouncements(target);
    expect(page.current!.content, '');
    expect(page.current!.author.memberRef, memberRef);
    expect(page.current!.publishedAt, DateTime.utc(2026, 9, 7));
    expect(host.requests.first.name, 'account.getCurrent');
    expect(host.requests.last.name, 'communities.announcements');
    expect(host.requests.last.accountContext, isNotNull);
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'targetRef': target,
      'offset': 0,
      'expectedRevision': null,
    });
    expect(() => page.history.clear(), throwsUnsupportedError);
  });
  test('generic commands do not grant announcement capability', () async {
    final host = CommunityHarness();
    addTearDown(host.close);
    expect(host.adapter.announcementsAvailable, false);
    await expectLater(
      host.adapter.readAnnouncements(target),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test('invalid next-page request is rejected without transport', () async {
    final host = CommunityHarness(capabilities: caps);
    addTearDown(host.close);
    await expectLater(
      host.adapter.readAnnouncements(target, offset: 20),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      host.adapter.readAnnouncements('unscoped'),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test(
    'next page stays bound to requested target, offset and version',
    () async {
      for (final field in ['targetRef', 'offset', 'revision']) {
        final payload = announcementPage()..['offset'] = 0;
        payload[field] = field == 'targetRef' ? memberRef : 1;
        final host = CommunityHarness(
          capabilities: caps,
          responses: {'communities.announcements': payload},
        );
        addTearDown(host.close);
        await expectLater(
          host.adapter.readAnnouncements(target, expectedRevision: 30),
          throwsA(isA<CommunityFailure>()),
        );
      }
    },
  );
  test('confirmed empty differs from unreadable or inconsistent content', () {
    final empty = announcementPage()
      ..['current'] = null
      ..['revision'] = 0;
    expect(CommunityAnnouncementsPage.parse(empty).current, isNull);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (p) => p['schemaVersion'] = 2,
      (p) => p['canManage'] = 'yes',
      (p) => p['revision'] = 1,
      (p) => p['totalHistoryCount'] = 1,
      (p) => p['next'] = 20,
      (p) => (p['current'] as Map)['state'] = 'archived',
      (p) => (p['current'] as Map)['title'] = ' ' * 49,
      (p) => (p['current'] as Map)['updatedAt'] = 'not-a-time',
      (p) => ((p['current'] as Map)['author'] as Map)['roleColor'] = 'red',
      (p) => ((p['current'] as Map)['author'] as Map)['memberRef'] = 'raw-id',
    ]) {
      final page = announcementPage();
      mutate(page);
      expect(
        () => CommunityAnnouncementsPage.parse(page),
        throwsFormatException,
      );
    }
  });
  test(
    'history retains withdrawn status without inventing a current announcement',
    () {
      final old = announcementRow()
        ..['state'] = 'withdrawn'
        ..['withdrawnAt'] = '2026-09-08T00:00:00Z';
      final page = announcementPage()
        ..['current'] = null
        ..['history'] = [old]
        ..['totalHistoryCount'] = 1;
      final parsed = CommunityAnnouncementsPage.parse(page);
      expect(parsed.current, isNull);
      expect(parsed.history.single.state, 'withdrawn');
      expect(parsed.history.single.withdrawnAt, DateTime.utc(2026, 9, 8));
    },
  );
  test(
    'announcements changed is a stable error without upstream details',
    () async {
      final host = CommunityHarness(
        capabilities: caps,
        error: 'communities.announcementsChanged',
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readAnnouncements(target),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.code,
            'code',
            'announcementsChanged',
          ),
        ),
      );
    },
  );
  test('account switch cancels a held announcement page and ignores its late reply', () async {
    final host = CommunityHarness(
      capabilities: caps,
      holdNames: {'communities.announcements'},
      responses: {'communities.announcements': announcementPage()},
    );
    addTearDown(host.close);
    final pending = host.adapter.readAnnouncements(target);
    final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final invalidated = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await invalidated;
    await rejected;
    await host.reply(
      host.requests.firstWhere((r) => r.name == 'communities.announcements'),
    );
  });
  test('original avatars assemble with integrity checks and conservative permission', () async {
    final port = _Details();
    final details = await assembleCommunityAnnouncementDetail(
      port,
      target,
      CommunityAnnouncement.parse(announcementRow()),
      checkCurrent: () {},
    );
    expect(port.calls, greaterThan(1));
    expect(details.authorAvatarImageData, port.avatar);
    expect(details.editorAvatarImageData, port.avatar);
    expect(details.canManage, false);
  });
  test(
    'wrong chunk identity, ordering, hash, budget or permissions are rejected',
    () async {
      for (final failure in [
        'wrong-target',
        'wrong-item',
        'wrong-offset',
        'wrong-next',
        'wrong-hash',
        'big',
        'permission',
        'changed-version',
        'short-chunk',
      ]) {
        final port = _Details()..failure = failure;
        await expectLater(
          assembleCommunityAnnouncementDetail(
            port,
            target,
            CommunityAnnouncement.parse(announcementRow()),
            checkCurrent: () {},
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('cancelled scope stops loading before another chunk', () async {
    var stale = false;
    final port = _Details()..onRead = () => stale = true;
    await expectLater(
      assembleCommunityAnnouncementDetail(
        port,
        target,
        CommunityAnnouncement.parse(announcementRow()),
        checkCurrent: () {
          if (stale) throw StateError('stale');
        },
      ),
      throwsStateError,
    );
    expect(port.calls, 1);
  });
  test('detail must match previously advertised avatar presence', () async {
    final port = _Details();
    final row = announcementRow()
      ..['author'] = announcementAuthor(hasAvatar: false);
    await expectLater(
      assembleCommunityAnnouncementDetail(
        port,
        target,
        CommunityAnnouncement.parse(row),
        checkCurrent: () {},
      ),
      throwsFormatException,
    );
  });
}
