import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

const memberOrg = '00000000000000000000000000000001';
const ownerOrg = '00000000000000000000000000000002';
const otherOrg = '00000000000000000000000000000003';

void main() {
  late ExampleCommunities port;
  var sequence = 0;
  CommunityAnnouncementIntent intent({
    String target = ownerOrg,
    String action = 'publish',
    String? ref,
    String title = '新公告',
    String content = '正文',
    String? request,
  }) => CommunityAnnouncementIntent(
    targetRef: target,
    requestId: request ?? (++sequence).toRadixString(16).padLeft(32, '0'),
    action: action,
    announcementRef: ref,
    title: action == 'withdraw' ? null : title,
    content: action == 'withdraw' ? null : content,
  );
  setUp(() {
    port = ExampleCommunities();
    sequence = 0;
  });
  tearDown(() => port.close());

  test(
    'directory references satisfy formal read and write contracts',
    () async {
      final directory = await port.read(view: 'mine', query: '');
      for (final card in directory.items) {
        expect(card.targetRef, matches(r'^[0-9a-f]{32}$'));
        final page = await port.readAnnouncements(card.targetRef);
        expect(page.current!.title, contains(card.name));
        expect(page.history.map((v) => v.state), ['archived', 'withdrawn']);
        final detail = await assembleCommunityAnnouncementDetail(
          port,
          card.targetRef,
          page.current!,
          checkCurrent: () {},
        );
        expect(detail.authorAvatarImageData, isNull);
        expect(detail.canManage, card.targetRef == ownerOrg);
      }
    },
  );

  test(
    'publish edit withdraw preserve metadata and independent timelines',
    () async {
      final original = (await port.readAnnouncements(ownerOrg)).current!;
      final other = await port.readAnnouncements(memberOrg);
      expect((await port.manageAnnouncement(intent())).status, 'accepted');
      var page = await port.readAnnouncements(ownerOrg);
      expect(page.history.first.announcementRef, original.announcementRef);
      expect(page.history.first.state, 'archived');
      final published = page.current!;
      expect(
        (await port.manageAnnouncement(
          intent(action: 'edit', ref: published.announcementRef, title: '修改后'),
        )).status,
        'accepted',
      );
      page = await port.readAnnouncements(ownerOrg);
      final edited = page.current!;
      expect(edited.title, '修改后');
      expect(edited.publishedAt, published.publishedAt);
      expect(edited.author.memberRef, published.author.memberRef);
      expect(edited.revision, published.revision + 1);
      expect(edited.announcementRef, isNot(published.announcementRef));
      expect(
        (await port.manageAnnouncement(
          intent(action: 'withdraw', ref: edited.announcementRef),
        )).status,
        'accepted',
      );
      page = await port.readAnnouncements(ownerOrg);
      expect(page.current, isNull);
      expect(page.history.first.state, 'withdrawn');
      expect(page.history.first.withdrawnAt, isNotNull);
      expect(
        (await port.readAnnouncements(memberOrg)).revision,
        other.revision,
      );
      expect(
        (await port.readAnnouncements(memberOrg)).current!.announcementRef,
        other.current!.announcementRef,
      );
    },
  );

  test('member nonmember and foreign record writes are rejected', () async {
    expect(
      (await port.manageAnnouncement(intent(target: memberOrg))).error,
      'notAllowed',
    );
    expect(
      (await port.manageAnnouncement(intent(target: otherOrg))).error,
      'notAllowed',
    );
    final other = (await port.readAnnouncements(memberOrg)).current!;
    expect(
      (await port.manageAnnouncement(
        intent(action: 'edit', ref: other.announcementRef),
      )).error,
      'announcementsChanged',
    );
    await expectLater(
      port.readAnnouncementDetail(ownerOrg, other.announcementRef, 0, null),
      throwsA(isA<CommunityFailure>()),
    );
  });

  test(
    'same intent is idempotent and changed intent cannot reuse receipt',
    () async {
      final write = intent();
      final results = await Future.wait([
        port.manageAnnouncement(write),
        port.manageAnnouncement(write),
      ]);
      expect(results.map((r) => r.revision).toSet(), hasLength(1));
      expect((await port.readAnnouncements(ownerOrg)).history, hasLength(3));
      expect(
        (await port.manageAnnouncement(
          intent(request: write.requestId, title: '不同'),
        )).error,
        'intentConflict',
      );
    },
  );

  test('history is bounded paged and refuses a changed timeline', () async {
    for (var i = 0; i < 105; i++) {
      await port.manageAnnouncement(intent(title: '公告 $i'));
    }
    final first = await port.readAnnouncements(ownerOrg);
    expect(first.totalHistoryCount, 99);
    expect(first.history, hasLength(20));
    final all = [...first.history];
    var next = first.next;
    while (next != null) {
      final page = await port.readAnnouncements(
        ownerOrg,
        offset: next,
        expectedRevision: first.revision,
      );
      all.addAll(page.history);
      next = page.next;
    }
    expect(all, hasLength(99));
    expect(all.map((v) => v.announcementRef).toSet(), hasLength(99));
    await port.manageAnnouncement(intent());
    await expectLater(
      port.readAnnouncements(
        ownerOrg,
        offset: 20,
        expectedRevision: first.revision,
      ),
      throwsA(isA<CommunityFailure>()),
    );
  });

  test('newly created organization begins empty and can publish', () async {
    final result = await port.createCommunity('example-create', {
      'code': 'NEWTAG',
      'name': '新建示例',
      'description': '',
      'tagIds': <String>[],
      'activeSystemIds': <String>[],
      'activeFrom': '18:00',
      'activeTo': '20:00',
      'timeZoneId': 'UTC',
      'joinPolicy': 'Open',
    });
    final target = result.organization!.targetRef;
    expect(target, matches(r'^[0-9a-f]{32}$'));
    final empty = await port.readAnnouncements(target);
    expect(empty.current, isNull);
    expect(empty.history, isEmpty);
    expect(empty.canManage, isTrue);
    expect(
      (await port.manageAnnouncement(intent(target: target))).status,
      'accepted',
    );
    expect((await port.readAnnouncements(target)).current!.title, '新公告');
  });

  test('stale draft cannot edit a replaced current announcement', () async {
    final model = CommunityAnnouncementsController(port, ownerOrg);
    addTearDown(model.dispose);
    await model.refresh();
    model.startEditing(create: false);
    model.updateDraft('本地草稿', '保留正文');
    await port.manageAnnouncement(intent());
    await model.refresh();
    expect(model.title, '本地草稿');
    expect(model.staleDraft, isTrue);
    await model.save();
    expect((await port.readAnnouncements(ownerOrg)).current!.title, '新公告');
  });

  test('leave revokes read detail and replay access', () async {
    final write = intent();
    await port.manageAnnouncement(write);
    final page = await port.readAnnouncements(ownerOrg);
    await port.execute('leave', ownerOrg);
    await expectLater(
      port.readAnnouncements(ownerOrg),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      port.readAnnouncementDetail(
        ownerOrg,
        page.current!.announcementRef,
        0,
        null,
      ),
      throwsA(isA<CommunityFailure>()),
    );
    expect((await port.manageAnnouncement(write)).error, 'notAllowed');
    expect((await port.readAnnouncements(memberOrg)).current, isNotNull);
  });

  test(
    'closing example invalidates open model and new session restores seed',
    () async {
      final model = CommunityAnnouncementsController(port, ownerOrg);
      addTearDown(model.dispose);
      await model.refresh();
      model.startEditing();
      model.updateDraft('私有草稿', '内容');
      await port.close();
      expect(model.invalidated, isTrue);
      expect(model.title, isEmpty);
      expect(model.page, isNull);
      expect(port.announcementsAvailable, isFalse);
      await expectLater(
        port.readAnnouncements(ownerOrg),
        throwsA(isA<CommunityFailure>()),
      );
      final fresh = ExampleCommunities();
      addTearDown(fresh.close);
      expect((await fresh.readAnnouncements(ownerOrg)).history, hasLength(2));
    },
  );
}
