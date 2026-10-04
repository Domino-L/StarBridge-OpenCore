import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import '../../features/communities/community_announcements_controller_test.dart'
    show AnnouncementsFake;
import '../../features/communities/community_announcements_test.dart'
    show target, itemRef, memberRef;
import '../../features/communities/community_workspace_test.dart'
    show workspacePayload;

class SessionPort extends HeldDetails
    implements CommunitiesPort, CommunityWorkspacePort {
  Completer<void>? listGate, directoryGate;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    await directoryGate?.future;
    return CommunityDirectory(view, query, const [
      CommunityCard(
        targetRef: target,
        name: 'Test organization',
        relationship: 'member',
      ),
    ]);
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String ref,
    String query,
    int offset,
  ) async => CommunityWorkspace.parse(workspacePayload());
  @override
  Future<Map<String, Object?>> readMedia(
    String ref,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => throw const CommunityFailure('unavailable');
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String ref, {
    int offset = 0,
    int? expectedRevision,
  }) async {
    await listGate?.future;
    return super.readAnnouncements(
      ref,
      offset: offset,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<String> execute(String action, String ref) async =>
      throw StateError('No writes permitted');
  @override
  Future<void> close() => changes.close();
}

class HeldDetails extends AnnouncementsFake {
  Completer<Map<String, Object?>>? gate;
  final targets = <String>[];
  @override
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String reference,
    int offset,
    String? version,
  ) {
    targets.add(targetRef);
    return gate?.future ??
        super.readAnnouncementDetail(targetRef, reference, offset, version);
  }
}

class Harness {
  Harness(this.port) {
    helper = MenuAnnouncementDetailsSession(
      grant: (run) {
        final key = 'a${++serial}';
        actions[key] = run;
        return {'key': key, 'label': '详情', 'limit': 128};
      },
      changed: () => changes++,
      denied: () => denials++,
      isCurrent: (source) => active && source == selected,
    );
    sync();
  }
  final HeldDetails port;
  late MenuAnnouncementDetailsSession helper;
  late CommunityAnnouncement item;
  int serial = 0, changes = 0, denials = 0;
  bool active = true;
  String selected = target;
  final actions = <String, Future<void> Function()>{};
  void sync() {
    item = CommunityAnnouncement.parse(port.current!);
    helper.sync(port, selected, [item]);
  }

  Map<String, Object?> get frame => helper.project({
    'rows': [
      {'title': item.title, 'detail': item.content},
    ],
    'organization': {
      'tab': 'announcements',
      'rows': [
        {'announcement': helper.binding(item)},
      ],
    },
  });
  Map<String, Object?> get detail => Map<String, Object?>.from(
    (((frame['organization'] as Map)['rows'] as List).single
            as Map)['announcement']
        as Map,
  );
  String get action =>
      ((((frame['rows'] as List).single as Map)['buttons'] as List).single
              as Map)['key']
          as String;
  Future<void> open() => actions[action]!();
  Future<void> close() async {
    helper.clear();
    await port.changes.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
  }

  Future<MenuFeatureView> announcements(
    WidgetTester tester,
    MenuOrganizationsSession session,
  ) async {
    session.show(true);
    await flush(tester);
    final members = MenuFeatureView.parse(session.currentView);
    session.act(members.organization!.sections['announcements']!, '');
    await flush(tester);
    final result = MenuFeatureView.parse(session.currentView);
    expect(result.organization!.tab, 'announcements');
    return result;
  }

  testWidgets(
    'session accepts detail during a slow background announcement refresh',
    (tester) async {
      final port = SessionPort();
      final session = MenuOrganizationsSession(port, (_) {});
      final ready = await announcements(tester, session);
      port.listGate = Completer<void>();
      final refresh = session.refresh(silent: true);
      await flush(tester);
      session.act(ready.rows.first.buttons.single.key, '');
      await flush(tester);
      expect(port.detailReads, 1);
      expect(
        MenuFeatureView.parse(session.currentView).organization!.tab,
        'announcements',
      );
      port.listGate!.complete();
      await refresh;
      expect(MenuFeatureView.parse(session.currentView).state, 'ready');
      session.dispose();
    },
  );

  testWidgets(
    'denied detail clears cached text while a background read is pending and recovers',
    (tester) async {
      final port = SessionPort()..detailFailure = 'notAllowed';
      final session = MenuOrganizationsSession(port, (_) {});
      final ready = await announcements(tester, session);
      port.listGate = Completer<void>();
      final oldRead = session.refresh(silent: true);
      await flush(tester);
      port.directoryGate = Completer<void>();
      session.act(ready.rows.first.buttons.single.key, '');
      await flush(tester);
      expect(jsonEncode(session.currentView), isNot(contains('远航准备通知')));
      port.listGate!.complete();
      await oldRead;
      expect(jsonEncode(session.currentView), isNot(contains('远航准备通知')));
      port.directoryGate!.complete();
      await flush(tester);
      expect(MenuFeatureView.parse(session.currentView).state, 'ready');
      await session.refresh();
      expect(MenuFeatureView.parse(session.currentView).state, 'ready');
      session.dispose();
    },
  );

  test(
    'details project display fields only and reuse completed media reads',
    () async {
      final h = Harness(HeldDetails());
      addTearDown(h.close);
      final before = h.detail['key'];
      await h.open();
      final encoded = jsonEncode(h.frame);
      for (final secret in [
        target,
        itemRef,
        memberRef,
        'canManage',
        'memberRef',
        'announcementRef',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      final view = MenuAnnouncementDetailsView.parse(h.detail)!;
      expect(view.entry.title, h.item.title);
      expect(view.entry.author.memberRef, isNull);
      expect(view.loading, false);
      expect(view.failed, false);
      expect(h.port.detailReads, 1);
      h.sync();
      expect(h.detail['key'], before);
      await h.open();
      expect(h.port.detailReads, 1);
      expect(h.port.writes, isEmpty);
    },
  );

  test(
    'changed metadata retires the old action and display identity',
    () async {
      final h = Harness(HeldDetails());
      addTearDown(h.close);
      final oldAction = h.actions[h.action]!, key = h.detail['key'];
      h.port.current!['revision'] = 3;
      h.port.current!['content'] = 'Changed announcement';
      h.sync();
      await oldAction();
      expect(h.port.targets, isEmpty);
      expect(h.detail['key'], isNot(key));
      await h.open();
      expect(h.port.detailReads, 1);
    },
  );

  for (final code in [
    'notAllowed',
    'identityUnavailable',
    'notFound',
    'refreshRequired',
  ]) {
    test(
      'permission failure $code retires detail and notifies owner',
      () async {
        final h = Harness(HeldDetails()..detailFailure = code);
        addTearDown(h.close);
        final oldAction = h.actions[h.action]!;
        await h.open();
        expect(h.denials, 1);
        final changed = h.changes;
        await oldAction();
        expect(h.changes, changed);
        expect(h.denials, 1);
        expect(h.port.writes, isEmpty);
      },
    );
  }

  test('transient read error is retryable without write uncertainty', () async {
    final h = Harness(HeldDetails()..detailFailure = 'unavailable');
    addTearDown(h.close);
    await h.open();
    expect(h.detail['failed'], true);
    expect(h.detail['loading'], false);
    expect(h.denials, 0);
    h.port.detailFailure = null;
    await h.open();
    expect(h.detail['failed'], false);
    expect(h.port.writes, isEmpty);
  });

  test(
    'recent detail media is bounded and evicted entries can load again',
    () async {
      final h = Harness(HeldDetails());
      addTearDown(h.close);
      final items = [
        h.item,
        for (var i = 1; i <= 6; i++)
          CommunityAnnouncement.parse({
            ...h.port.current!,
            'announcementRef': i.toRadixString(16).padLeft(32, '0'),
          }),
      ];
      h.helper.sync(h.port, target, items);
      String key(CommunityAnnouncement item) {
        final view = h.helper.project({
          'rows': [
            {'title': item.title},
          ],
          'organization': {
            'tab': 'announcements',
            'rows': [
              {'announcement': h.helper.binding(item)},
            ],
          },
        });
        return ((((view['rows'] as List).single as Map)['buttons'] as List)
                    .single
                as Map)['key']
            as String;
      }

      for (final item in items) {
        await h.actions[key(item)]!();
      }
      expect(h.port.detailReads, 7);
      await h.actions[key(items.last)]!();
      expect(h.port.detailReads, 7);
      await h.actions[key(items.first)]!();
      expect(h.port.detailReads, 8);
    },
  );

  test(
    'retirement strips detail and actions from an already projected frame',
    () async {
      final h = Harness(HeldDetails());
      addTearDown(h.close);
      await h.open();
      final old = h.frame;
      h.helper.clear();
      final retired = h.helper.project(old);
      final row =
          ((retired['organization'] as Map)['rows'] as List).single as Map;
      expect(row['announcement'], isNull);
      final actions = ((retired['rows'] as List).single as Map)['buttons'];
      expect(actions == null || (actions as List).isEmpty, true);
    },
  );

  testWidgets(
    'renewed organization target rejects the previous in-flight read',
    (tester) async {
      final port = HeldDetails()..gate = Completer<Map<String, Object?>>();
      final h = Harness(port);
      addTearDown(h.close);
      final oldAction = h.actions[h.action]!;
      final work = h.open();
      h.selected = 'dddddddddddddddddddddddddddddddd';
      h.sync();
      final nextAction = h.action;
      final changes = h.changes;
      port.gate!.complete({});
      await work;
      await oldAction();
      expect(h.action, nextAction);
      expect(h.changes, changes);
      port.gate = null;
      await h.open();
      expect(port.targets, [target, h.selected]);
      expect(h.detail['failed'], false);
    },
  );

  testWidgets('timeout retires chunk reader before a late first chunk arrives', (
    tester,
  ) async {
    final port = HeldDetails()..gate = Completer<Map<String, Object?>>();
    final h = Harness(port);
    addTearDown(h.close);
    final work = h.open();
    await tester.pump(const Duration(seconds: 7));
    await work;
    expect(h.detail['failed'], true);
    expect(h.detail['loading'], false);
    final changes = h.changes;
    final bytes = utf8.encode(
      '${jsonEncode({'authorAvatarImageData': null, 'editorAvatarImageData': null})}${' ' * 250000}',
    );
    port.gate!.complete({
      'schemaVersion': 1,
      'targetRef': target,
      'announcementRef': itemRef,
      'offset': 0,
      'next': 192 * 1024,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes.take(192 * 1024).toList()),
      'canManage': false,
    });
    await tester.pump();
    expect(port.targets, hasLength(1));
    expect(h.changes, changes);
    port.gate = null;
    await h.open();
    expect(h.detail['failed'], false);
  });

  testWidgets('scope retirement discards late results and old actions', (
    tester,
  ) async {
    final port = HeldDetails()..gate = Completer<Map<String, Object?>>();
    final h = Harness(port);
    addTearDown(h.close);
    final oldAction = h.actions[h.action]!;
    final work = h.open();
    h.active = false;
    h.helper.clear();
    final changed = h.changes;
    port.gate!.complete({});
    await work;
    await oldAction();
    expect(h.changes, changed);
    expect(h.denials, 0);
    expect(port.targets, hasLength(1));
  });

  test('renderer rejects authority fields and oversized image data', () async {
    final h = Harness(HeldDetails());
    addTearDown(h.close);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (m) => m['targetRef'] = target,
      (m) => (m['entry'] as Map)['announcementRef'] = itemRef,
      (m) => ((m['entry'] as Map)['author'] as Map)['memberRef'] = memberRef,
      (m) => m['authorAvatar'] = 'data:image/png;base64,${'A' * 28000}',
      (m) => m['editorAvatar'] = 'https://example.invalid/image.png',
      (m) => m['key'] = itemRef,
    ]) {
      final raw = Map<String, Object?>.from(
        jsonDecode(jsonEncode(h.detail)) as Map,
      );
      mutate(raw);
      expect(
        () => MenuAnnouncementDetailsView.parse(raw),
        throwsFormatException,
      );
    }
  });
}
