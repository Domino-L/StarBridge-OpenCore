import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';

import 'community_announcements_test.dart'
    show announcementRow, announcementAuthor, target;

class AnnouncementsFake
    implements CommunityAnnouncementsPort, CommunityAnnouncementWritePort {
  final changes = StreamController<void>.broadcast();
  final writes = <CommunityAnnouncementIntent>[];
  final reads = <(int, int?)>[];
  int revision = 30;
  int detailReads = 0;
  bool allowed = true;
  String? failure, detailFailure;
  CommunityAnnouncementOutcome? outcome;
  Completer<CommunityAnnouncementOutcome>? heldWrite;
  Completer<CommunityAnnouncementsPage>? heldRead;
  Map<String, Object?>? current = announcementRow()
    ..['title'] = '远航准备通知'
    ..['content'] = '出发前请检查补给，并在组织聊天中确认分工。'
    ..['author'] = announcementAuthor(hasAvatar: false)
    ..['editor'] = announcementAuthor(hasAvatar: false);
  final history = <Map<String, Object?>>[];
  @override
  bool get announcementsAvailable => true;
  @override
  bool get announcementWritesAvailable => true;
  @override
  Stream<void> get invalidations => changes.stream;
  Map<String, Object?> payload({int offset = 0}) => {
    'schemaVersion': 1,
    'targetRef': target,
    'revision': revision,
    'canManage': allowed,
    'current': current,
    'history': history.skip(offset).take(20).toList(),
    'offset': offset,
    'next': offset + 20 < history.length ? offset + 20 : null,
    'totalHistoryCount': history.length,
    'refreshedAt': '2026-09-08T00:00:00Z',
  };
  void addHistory(int count) {
    history.addAll(
      List.generate(
        count,
        (i) => {
          ...announcementRow(),
          'announcementRef': (i + 100).toRadixString(16).padLeft(32, '0'),
          'title': '历史公告 ${i + 1}',
          'content': '这条公告保留原始发布与编辑记录。',
          'state': i.isEven ? 'archived' : 'withdrawn',
          'author': announcementAuthor(hasAvatar: false),
          'editor': announcementAuthor(hasAvatar: false),
        },
      ),
    );
  }

  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  }) async {
    reads.add((offset, expectedRevision));
    if (failure != null) throw CommunityFailure(failure!);
    if (heldRead != null) return heldRead!.future;
    return CommunityAnnouncementsPage.parse(payload(offset: offset));
  }

  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  ) async {
    if (detailFailure != null) throw CommunityFailure(detailFailure!);
    detailReads++;
    final bytes = utf8.encode(
      jsonEncode({
        'authorAvatarImageData': null,
        'editorAvatarImageData': null,
      }),
    );
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'announcementRef': announcementRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'data': base64Encode(bytes),
      'version': sha256.convert(bytes).toString(),
      'canManage': allowed,
    };
  }

  @override
  Future<CommunityAnnouncementOutcome> manageAnnouncement(
    CommunityAnnouncementIntent intent,
  ) async {
    writes.add(intent);
    if (heldWrite != null) return heldWrite!.future;
    if (outcome != null) return outcome!;
    revision++;
    final old = current;
    if (intent.action == 'withdraw') {
      if (old != null) {
        history.insert(0, {
          ...old,
          'state': 'withdrawn',
          'withdrawnAt': '2026-09-08T00:01:00Z',
        });
      }
      current = null;
    } else {
      if (intent.action == 'publish' && old != null) {
        history.insert(0, {...old, 'state': 'archived'});
      }
      current = {
        ...?old,
        ...announcementRow(),
        'announcementRef': revision.toRadixString(16).padLeft(32, '0'),
        'revision': intent.action == 'edit' ? (old!['revision'] as int) + 1 : 1,
        'title': intent.title,
        'content': intent.content,
        'author': announcementAuthor(hasAvatar: false),
        'editor': announcementAuthor(hasAvatar: false),
      };
    }
    return CommunityAnnouncementOutcome('accepted', revision: revision);
  }
}

void main() {
  late AnnouncementsFake port;
  late CommunityAnnouncementsController model;
  setUp(() {
    port = AnnouncementsFake();
    model = CommunityAnnouncementsController(port, target);
  });
  tearDown(() async {
    model.dispose();
    await port.changes.close();
  });
  test('paged history uses one timeline and current record', () async {
    port.addHistory(21);
    await model.refresh();
    expect(model.history, hasLength(20));
    await model.loadMore();
    expect(model.history, hasLength(21));
    expect(port.reads, [(0, null), (20, 30)]);
    expect(model.page!.current!.title, '远航准备通知');
  });
  test(
    'automatic readback never releases or retries an unknown write',
    () async {
      await model.refresh();
      model.startEditing();
      model.updateDraft('待核对', '正文');
      port.outcome = const CommunityAnnouncementOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
      await model.save();
      await model.refresh(background: true);
      await model.refresh(background: true);
      expect(port.writes, hasLength(1));
      expect(model.uncertain, isTrue);
      expect(model.canReviewUnknown, isTrue);
      expect(model.title, '待核对');
    },
  );
  test(
    'background read retains paged history detail cache and draft',
    () async {
      port.addHistory(45);
      await model.refresh();
      await model.loadMore();
      final original = model.page!.current!;
      await model.detail(original);
      model.startEditing(create: false);
      model.updateDraft('本地内容', '草稿');
      await model.refresh(background: true);
      expect(model.history, hasLength(40));
      expect(model.page!.next, 40);
      expect(model.title, '本地内容');
      await model.detail(original);
      expect(port.detailReads, 1);
      await model.loadMore();
      expect(model.history, hasLength(45));
    },
  );
  test('background timeline change resets paging but not draft', () async {
    port.addHistory(45);
    await model.refresh();
    await model.loadMore();
    model.startEditing(create: false);
    model.updateDraft('本地内容', '草稿');
    port.revision++;
    port.current!['announcementRef'] = 'c' * 32;
    await model.refresh(background: true);
    expect(model.history, hasLength(20));
    expect(model.page!.next, 20);
    expect(model.staleDraft, isTrue);
    expect(model.title, '本地内容');
    expect(port.writes, isEmpty);
  });
  test(
    'background denial clears private history and disables management',
    () async {
      await model.refresh();
      port.failure = 'notAllowed';
      await model.refresh(background: true);
      expect(model.page, isNull);
      expect(model.history, isEmpty);
      expect(model.canManage, isFalse);
    },
  );
  test('revision change refuses mixed history and keeps draft', () async {
    port.addHistory(21);
    await model.refresh();
    model.startEditing(create: false);
    model.updateDraft('未保存', '正文');
    port.revision++;
    await model.loadMore();
    expect(model.history, hasLength(20));
    expect(model.error, 'dataInvalid');
    expect(model.title, '未保存');
    expect(model.writable, isFalse);
  });
  test(
    'publish archives old current and requires confirmed readback',
    () async {
      await model.refresh();
      model.startEditing();
      model.updateDraft('新公告', '');
      await model.save();
      expect(port.writes.single.action, 'publish');
      expect(model.title, isEmpty);
      expect(model.editing, isFalse);
      expect(model.page!.current!.title, '新公告');
      expect(model.history, hasLength(1));
      expect(model.success, 'published');
    },
  );
  test('edit pins old reference and refresh never overwrites draft', () async {
    await model.refresh();
    final original = model.page!.current!.announcementRef;
    model.startEditing(create: false);
    model.updateDraft('改名', '正文');
    await model.refresh();
    expect(model.title, '改名');
    await model.save();
    expect(port.writes.single.announcementRef, original);
    expect(model.page!.current!.title, '改名');
    expect(model.success, 'saved');
  });
  test(
    'changed current cannot be edited or withdrawn through old confirmation',
    () async {
      await model.refresh();
      final original = model.page!.current!;
      model.startEditing(create: false);
      model.updateDraft('改名', '正文');
      port.current!['announcementRef'] = 'd' * 32;
      port.revision++;
      await model.refresh();
      await model.save();
      expect(model.staleDraft, isTrue);
      expect(model.title, '改名');
      expect(port.writes, isEmpty);
      model.discardDraft();
      await model.withdraw(original);
      expect(port.writes, isEmpty);
    },
  );
  test(
    'withdraw clears current only after confirmed save and retains history',
    () async {
      await model.refresh();
      await model.withdraw(model.page!.current!);
      expect(port.writes.single.action, 'withdraw');
      expect(model.page!.current, isNull);
      expect(model.history.single.state, 'withdrawn');
      expect(model.success, 'withdrawnSuccess');
    },
  );
  test('double save is gated and draft cannot change during write', () async {
    await model.refresh();
    model.startEditing();
    model.updateDraft('新公告', '正文');
    port.heldWrite = Completer();
    final first = model.save();
    await Future<void>.delayed(Duration.zero);
    model.updateDraft('意外覆盖', '');
    await model.save();
    expect(model.title, '新公告');
    expect(port.writes, hasLength(1));
    port.heldWrite!.complete(
      const CommunityAnnouncementOutcome('rejected', error: 'busy'),
    );
    await first;
    expect(model.dirty, isTrue);
  });
  test('known rejection preserves draft; unknown blocks resend until reviewed after refresh', () async {
    await model.refresh();
    model.startEditing();
    model.updateDraft('新公告', '正文');
    port.outcome = const CommunityAnnouncementOutcome(
      'rejected',
      error: 'busy',
    );
    await model.save();
    expect(model.uncertain, isFalse);
    expect(model.title, '新公告');
    port.outcome = const CommunityAnnouncementOutcome(
      'unknown',
      error: 'outcomeUnknown',
    );
    await model.save();
    await model.save();
    expect(port.writes, hasLength(2));
    expect(model.uncertain, isTrue);
    model.reviewedUnknown();
    expect(model.uncertain, isTrue);
    await model.refresh();
    expect(model.canReviewUnknown, isTrue);
    model.reviewedUnknown();
    expect(model.uncertain, isFalse);
    expect(port.writes, hasLength(2));
  });
  test('successful receipt plus failed read does not present old current or unsaved draft', () async {
    await model.refresh();
    model.startEditing();
    model.updateDraft('新公告', '正文');
    port.failure = 'unavailable';
    await model.save();
    expect(model.success, 'published');
    expect(model.page, isNull);
    expect(model.title, isEmpty);
    expect(model.error, 'unavailable');
  });
  test(
    'late lower version after save cannot overwrite acknowledged timeline',
    () async {
      await model.refresh();
      model.startEditing();
      model.updateDraft('新公告', '正文');
      port.outcome = const CommunityAnnouncementOutcome(
        'accepted',
        revision: 31,
      );
      await model.save();
      expect(model.page, isNull);
      expect(model.error, 'dataInvalid');
    },
  );
  test(
    'permission loss disables writes while preserving authored draft',
    () async {
      await model.refresh();
      model.startEditing();
      model.updateDraft('新公告', '正文');
      port.allowed = false;
      await model.refresh();
      await model.save();
      expect(port.writes, isEmpty);
      expect(model.title, '新公告');
      expect(model.writable, isFalse);
    },
  );
  test('details retain permission downgrade and clear inaccessible private metadata', () async {
    await model.refresh();
    final item = model.page!.current!;
    port.allowed = false;
    await model.detail(item);
    expect(model.canManage, isFalse);
    port.detailFailure = 'notAllowed';
    await model.refresh();
    await expectLater(
      model.detail(model.page!.current!),
      throwsA(isA<CommunityFailure>()),
    );
    expect(model.page, isNull);
    expect(model.history, isEmpty);
  });
  test('account invalidation clears draft and ignores late write', () async {
    await model.refresh();
    model.startEditing();
    model.updateDraft('私人草稿', '内容');
    port.heldWrite = Completer();
    final pending = model.save();
    await Future<void>.delayed(Duration.zero);
    model.invalidate();
    port.heldWrite!.complete(
      const CommunityAnnouncementOutcome('accepted', revision: 31),
    );
    await pending;
    expect(model.title, isEmpty);
    expect(model.page, isNull);
    expect(model.success, isNull);
  });
  test('account invalidation ignores late read', () async {
    port.heldRead = Completer();
    final pending = model.refresh();
    model.invalidate();
    port.heldRead!.complete(CommunityAnnouncementsPage.parse(port.payload()));
    await pending;
    expect(model.page, isNull);
    expect(model.invalidated, isTrue);
  });
}
