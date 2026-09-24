import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

void main() {
  CommunityAnnouncementIntent intent({
    String action = 'publish',
    String title = ' Title ',
    String content = ' Body\r\ntext ',
  }) => CommunityAnnouncementIntent(
    targetRef: 'a' * 32,
    requestId: 'b' * 32,
    action: action,
    announcementRef: action == 'publish' ? null : 'c' * 32,
    title: action == 'withdraw' ? null : title,
    content: action == 'withdraw' ? null : content,
  );
  Map<String, Object?> receipt({String action = 'publish'}) => {
    'schemaVersion': 1,
    'targetRef': 'a' * 32,
    'requestId': 'b' * 32,
    'action': action,
    'status': 'accepted',
    'error': null,
    'revision': 11,
  };
  for (final action in ['publish', 'edit', 'withdraw']) {
    test(
      '$action uses its scoped intent and dedicated capability exactly once',
      () async {
        final host = CommunityHarness(
          capabilities: ['communities.manageAnnouncements'],
          responses: {
            'communities.manageAnnouncements': receipt(action: action),
          },
        );
        addTearDown(host.close);
        final value = intent(action: action);
        final result = await host.adapter.manageAnnouncement(value);
        expect(result.status, 'accepted');
        expect(result.revision, 11);
        expect(host.requests.last.accountContext?.subject, 'test-subject');
        expect(host.requests.last.payload, {
          'schemaVersion': 1,
          ...value.toPayload(),
        });
        expect(
          host.requests.where(
            (r) => r.name == 'communities.manageAnnouncements',
          ),
          hasLength(1),
        );
        expect(value.toPayload().containsKey('expectedRevision'), isFalse);
        if (action == 'withdraw') {
          expect(value.toPayload().containsKey('title'), isFalse);
          expect(value.toPayload().containsKey('content'), isFalse);
        } else {
          expect(value.title, 'Title');
          expect(value.content, 'Body\ntext');
        }
      },
    );
  }
  test(
    'read or generic capability does not grant announcement writes',
    () async {
      final host = CommunityHarness(
        capabilities: [
          'communities.commands',
          'communities.announcements',
          'communities.announcementDetail',
        ],
      );
      addTearDown(host.close);
      expect(host.adapter.announcementsAvailable, isTrue);
      expect(host.adapter.announcementWritesAvailable, isFalse);
      expect(
        (await host.adapter.manageAnnouncement(intent())).status,
        'rejected',
      );
      expect(host.requests, isEmpty);
    },
  );
  test('intent keeps WPF limits and action-dependent fields', () {
    expect(intent(content: '').content, '');
    for (final title in ['', '   ', 'x' * 49, 'hello\nworld', 'x\u0000y']) {
      expect(() => intent(title: title), throwsFormatException);
    }
    for (final content in ['x' * 1201, 'x\u0000y', 'x\u007fy']) {
      expect(() => intent(content: content), throwsFormatException);
    }
    for (final value in <Map<String, Object?>>[
      {'action': 'delete'},
      {'action': 'edit'},
      {'action': 'withdraw'},
      {'action': 'publish', 'announcementRef': 'c' * 32},
      {'action': 'edit', 'announcementRef': 'bad'},
      {
        'action': 'withdraw',
        'announcementRef': 'c' * 32,
        'title': 'hidden edit',
      },
    ]) {
      expect(
        () => CommunityAnnouncementIntent(
          targetRef: 'a' * 32,
          requestId: 'b' * 32,
          action: value['action'] as String,
          announcementRef: value['announcementRef'] as String?,
          title: value['action'] == 'withdraw'
              ? value['title'] as String?
              : 'Title',
          content: value['action'] == 'withdraw' ? null : '',
        ),
        throwsFormatException,
      );
    }
  });
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('targetRef', 'd' * 32),
    ('requestId', 'd' * 32),
    ('action', 'edit'),
    ('status', 'published'),
    ('revision', null),
    ('revision', 0),
    ('revision', 1.5),
    ('error', 'failure'),
  ]) {
    test('malformed receipt $key remains unknown and is not retried', () async {
      final host = CommunityHarness(
        capabilities: ['communities.manageAnnouncements'],
        responses: {
          'communities.manageAnnouncements': receipt()..[key] = value,
        },
      );
      addTearDown(host.close);
      final result = await host.adapter.manageAnnouncement(intent());
      expect(result.status, 'unknown');
      expect(result.revision, isNull);
      expect(
        host.requests.where((r) => r.name == 'communities.manageAnnouncements'),
        hasLength(1),
      );
    });
  }
  for (final status in ['rejected', 'unknown']) {
    test('$status is not promoted to saved', () async {
      final host = CommunityHarness(
        capabilities: ['communities.manageAnnouncements'],
        responses: {
          'communities.manageAnnouncements': receipt()
            ..['status'] = status
            ..['revision'] = null
            ..['error'] = 'announcementsChanged',
        },
      );
      addTearDown(host.close);
      final result = await host.adapter.manageAnnouncement(intent());
      expect(result.status, status);
      expect(result.error, 'announcementsChanged');
      expect(result.revision, isNull);
    });
  }
  test(
    'account invalidation discards late write receipt without replay',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.manageAnnouncements'],
        holdNames: {'communities.manageAnnouncements'},
        responses: {'communities.manageAnnouncements': receipt()},
      );
      addTearDown(host.close);
      final pending = host.adapter.manageAnnouncement(intent());
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
      expect((await pending).status, 'unknown');
      await host.reply(
        host.requests.firstWhere(
          (r) => r.name == 'communities.manageAnnouncements',
        ),
      );
      expect(
        host.requests.where((r) => r.name == 'communities.manageAnnouncements'),
        hasLength(1),
      );
    },
  );
}
