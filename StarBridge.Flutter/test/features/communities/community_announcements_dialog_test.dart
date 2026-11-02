import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_session.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_outcomes_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';

import '../common/organization_announcement_management_session_test.dart'
    show FixtureManagementPort;
import 'community_announcements_test.dart'
    show announcementRow, announcementAuthor;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_copy.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_announcements_controller_test.dart' show AnnouncementsFake;
import 'community_announcements_test.dart' show target;
import 'community_workspace_view_test.dart' show host;
import 'community_workspace_test.dart' show workspacePayload;
import '../friends/social_layout_test.dart' show loadFonts;

class AnnouncementsWorkspaceFake extends AnnouncementsFake
    implements CommunityWorkspacePort {
  @override
  Future<CommunityWorkspace> readWorkspace(
    String ref,
    String query,
    int offset,
  ) async => CommunityWorkspace.parse(workspacePayload());
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => throw const FormatException();
}

Future<void> openAnnouncements(
  WidgetTester tester,
  CommunityAnnouncementsPort port, {
  String targetRef = target,
  CommunityAnnouncementsController? controller,
  Locale locale = const Locale('zh', 'CN'),
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      builder: (_, child) => RepaintBoundary(
        key: const ValueKey('announcement-capture'),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: CommunityAnnouncementEntry(
            port: port,
            targetRef: targetRef,
            controller: controller,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('community-announcement-entry')));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('announcement-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/test-artifacts/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'official typed editor uses the original form for publish edit withdraw',
    (tester) async {
      final reads = AnnouncementsFake()
        ..allowed = false
        ..revision = 0
        ..current = null;
      final port = OfficialAnnouncementFormFixture(reads);
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      final model = CommunityAnnouncementsController(
        reads,
        target,
        management: session,
      );
      addTearDown(model.dispose);
      addTearDown(session.dispose);
      addTearDown(outcomes.dispose);
      addTearDown(port.close);
      addTearDown(reads.changes.close);
      await openAnnouncements(tester, reads, controller: model);
      expect(model.page!.canManage, isFalse);
      await tester.tap(find.byKey(const Key('announcement-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement-title')),
        'Original form title',
      );
      await tester.enterText(
        find.byKey(const Key('announcement-content')),
        'Original form body',
      );
      await tester.ensureVisible(find.byKey(const Key('announcement-save')));
      await tester.tap(find.byKey(const Key('announcement-save')));
      await tester.pumpAndSettle();
      expect(port.managed.single.action, 'publish');
      expect(port.managed.single.title, 'Original form title');
      await tester.tap(find.byKey(const Key('announcement-refresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('announcement-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement-title')),
        'Edited in same form',
      );
      await tester.ensureVisible(find.byKey(const Key('announcement-save')));
      await tester.tap(find.byKey(const Key('announcement-save')));
      await tester.pumpAndSettle();
      expect(port.managed.last.action, 'edit');
      expect(port.managed.last.announcementRef, 'f' * 32);
      expect(
        port.managed.last.announcementRef,
        isNot(model.page!.current!.announcementRef),
      );
      await tester.tap(find.byKey(const Key('announcement-refresh')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('announcement-withdraw')),
      );
      await tester.tap(find.byKey(const Key('announcement-withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('announcement-confirm-accept')));
      await tester.pumpAndSettle();
      expect(port.managed.map((v) => v.action), [
        'publish',
        'edit',
        'withdraw',
      ]);
      expect(
        reads.writes,
        isEmpty,
        reason: 'Official writes never use the community write port',
      );
      expect(model.page!.current, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'official unknown refresh and query preserve one immutable operation',
    (tester) async {
      final reads = AnnouncementsFake()
        ..allowed = false
        ..revision = 0
        ..current = null;
      final port = OfficialAnnouncementFormFixture(reads)..failManage = true;
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      final model = CommunityAnnouncementsController(
        reads,
        target,
        management: session,
      );
      addTearDown(model.dispose);
      addTearDown(session.dispose);
      addTearDown(outcomes.dispose);
      addTearDown(port.close);
      addTearDown(reads.changes.close);
      await openAnnouncements(tester, reads, controller: model);
      await tester.tap(find.byKey(const Key('announcement-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement-title')),
        'Unconfirmed form',
      );
      await tester.ensureVisible(find.byKey(const Key('announcement-save')));
      await tester.tap(find.byKey(const Key('announcement-save')));
      await tester.pumpAndSettle();
      final original = port.managed.single;
      await tester.tap(find.byKey(const Key('announcement-refresh')));
      await tester.pumpAndSettle();
      expect(model.uncertain, isTrue);
      expect(
        find.byKey(const Key('announcement-review-unknown')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('announcement-query-original')));
      await tester.pumpAndSettle();
      expect(model.uncertain, isTrue);
      expect(session.originalIntent, same(original));
      expect(port.managed, hasLength(1));
      await tester.ensureVisible(find.byKey(const Key('announcement-discard')));
      await tester.tap(find.byKey(const Key('announcement-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('announcement-confirm-accept')));
      await tester.pumpAndSettle();
      expect(model.editing, isFalse);
      final originalQueryRetained = find
          .byKey(const Key('announcement-query-original'))
          .evaluate()
          .isNotEmpty;
      await tester.tap(find.byKey(const Key('announcement-own-outcomes')));
      await tester.pumpAndSettle();
      final ownQuery = find.byKey(
        ValueKey('announcement-query-${original.requestId}'),
      );
      await tester.tap(ownQuery);
      await tester.pumpAndSettle();
      expect(outcomes.results[original.requestId]?.status, 'unknown');
      expect(session.unresolved, isTrue);
      expect(
        model.writable,
        isFalse,
        reason: 'notFound cannot restore editing authority',
      );
      expect(port.managed, hasLength(1));
      final editorsBeforeKnownResult = port.editorReads;
      port.queryAccepted = true;
      await tester.tap(ownQuery);
      await tester.pumpAndSettle();
      expect(outcomes.results[original.requestId]?.status, 'accepted');
      expect(
        port.editorReads,
        editorsBeforeKnownResult,
        reason: 'Own receipt queries do not renew an editor',
      );
      await tester.tap(find.byKey(const Key('announcement-outcomes-close')));
      await tester.pumpAndSettle();
      expect(
        session.unresolved,
        isFalse,
        reason:
            'A terminal own result must release the matching current session',
      );
      expect(
        originalQueryRetained,
        isTrue,
        reason: 'Discarding a draft must retain the original unknown operation entry',
      );
      expect(session.editor, isNull);
      await tester.tap(find.byKey(const Key('announcement-refresh')));
      await tester.pumpAndSettle();
      expect(port.editorReads, editorsBeforeKnownResult + 1);
      expect(model.uncertain, isFalse);
      expect(model.success, 'published');
      expect(session.editor, isNotNull);
      await tester.tap(find.text('编辑当前公告'));
      await tester.pumpAndSettle();
      expect(model.editing, isTrue);
      expect(find.text('Unconfirmed form'), findsOneWidget);
      expect(port.queries.every((v) => v.$1 == original.requestId), isTrue);
      expect(
        port.managed,
        hasLength(1),
        reason: 'No new operation or automatic re-POST',
      );
      expect(reads.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('current announcement route polls once and retains the draft', (
    tester,
  ) async {
    final port = AnnouncementsFake();
    addTearDown(port.changes.close);
    await openAnnouncements(tester, port);
    await tester.tap(find.text('编辑当前公告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('announcement-title')),
      '保留草稿',
    );
    final before = port.reads.length;
    port.revision++;
    port.current!['announcementRef'] = 'c' * 32;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(port.reads.length, before + 1);
    expect(find.text('保留草稿'), findsOneWidget);
    expect(port.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('background app does not poll and disposed entry stops polling', (
    tester,
  ) async {
    final port = AnnouncementsFake();
    addTearDown(port.changes.close);
    await openAnnouncements(tester, port);
    final before = port.reads.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(port.reads.length, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(port.reads.length, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final stopped = port.reads.length;
    await tester.pump(const Duration(seconds: 20));
    expect(port.reads.length, stopped);
    expect(tester.takeException(), isNull);
  });
  testWidgets('actual example publishes edits withdraws and restores entry', (
    tester,
  ) async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    const organization = '00000000000000000000000000000002';
    await openAnnouncements(tester, port, targetRef: organization);
    expect(find.text('示例 · 探索交流 · 本周安排'), findsOneWidget);
    await tester.tap(find.text('发布新公告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('announcement-title')),
      '示例新安排',
    );
    await tester.enterText(
      find.byKey(const ValueKey('announcement-content')),
      '请在聊天中确认',
    );
    await tester.tap(find.widgetWithText(FilledButton, '发布公告'));
    await tester.pumpAndSettle();
    expect(
      (await port.readAnnouncements(organization)).current!.title,
      '示例新安排',
    );
    await tester.tap(find.text('编辑当前公告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('announcement-title')),
      '示例调整后安排',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存修订'));
    await tester.pumpAndSettle();
    expect(
      (await port.readAnnouncements(organization)).current!.title,
      '示例调整后安排',
    );
    await capture(tester, 'community-announcements-example');
    await tester.tap(find.text('撤下公告'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '撤下公告'));
    await tester.pumpAndSettle();
    expect(find.text('暂无当前公告'), findsOneWidget);
    expect(
      (await port.readAnnouncements(organization)).history.first.title,
      '示例调整后安排',
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('leaving actual example clears an open center and draft', (
    tester,
  ) async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    await openAnnouncements(
      tester,
      port,
      targetRef: '00000000000000000000000000000002',
    );
    await tester.tap(find.text('发布新公告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('announcement-title')),
      '示例未保存',
    );
    await port.close();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
    expect(find.text('示例未保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final (locale, width, index) in [
    (const Locale('zh', 'CN'), 420.0, 0),
    (const Locale('zh', 'TW'), 850.0, 1),
    (const Locale('en'), 1100.0, 2),
  ]) {
    testWidgets(
      'announcement center editor and draft guard fit $locale $width',
      (tester) async {
        final port = AnnouncementsFake()..addHistory(2);
        addTearDown(port.changes.close);
        await openAnnouncements(tester, port, locale: locale, width: width);
        String t(String key) {
          final row = communityAnnouncementsCopy[key]!;
          return [row.$1, row.$2, row.$3][index];
        }

        expect(find.text('远航准备通知'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t('create')));
        await tester.pumpAndSettle();
        final input = tester.widget<TextField>(
          find.byKey(const ValueKey('announcement-title')),
        );
        if (locale.languageCode == 'zh') {
          expect(
            input.style?.fontFamilyFallback,
            contains(
              FutureRestraintStyle.resolve(AppearanceMode.dark).typography
                  .fallbacksFor(locale)
                  .first,
            ),
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('announcement-title')),
          '新公告',
        );
        await tester.enterText(
          find.byKey(const ValueKey('announcement-content')),
          '未保存正文',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t('close')));
        await tester.pumpAndSettle();
        expect(find.text(t('leaveTitle')), findsOneWidget);
        expect(port.writes, isEmpty);
        await tester.tap(find.text(t('cancel')).last);
        await tester.pumpAndSettle();
        expect(find.text('未保存正文'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, t('publish')),
        );
        await tester.tap(find.widgetWithText(FilledButton, t('publish')));
        await tester.pumpAndSettle();
        expect(port.writes, hasLength(1));
        expect(port.writes.single.title, '新公告');
        expect(find.byKey(const ValueKey('announcement-title')), findsNothing);
        expect(find.text('新公告'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'current details contain original authors times and avatar menus',
    (tester) async {
      final port = AnnouncementsFake()..addHistory(3);
      addTearDown(port.changes.close);
      await openAnnouncements(tester, port);
      await capture(tester, 'community-announcements-center');
      await tester.tap(find.text('查看详情').first);
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatarMenu), findsNWidgets(2));
      expect(find.text('Author (Pilot)'), findsNWidgets(2));
      expect(find.textContaining('发布时间 · '), findsOneWidget);
      expect(find.textContaining('更新时间 · '), findsOneWidget);
      expect(find.text('发布者'), findsOneWidget);
      await tester.tap(find.byType(UserAvatarMenu).first);
      await tester.pumpAndSettle();
      expect(find.byType(StarBridgeMenuAnchor), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(30, 30));
      await tester.pumpAndSettle();
      await capture(tester, 'community-announcements-details');
    },
  );
  testWidgets(
    'withdraw requires explicit confirmation within announcement center',
    (tester) async {
      final port = AnnouncementsFake();
      addTearDown(port.changes.close);
      await openAnnouncements(tester, port);
      await tester.tap(find.text('撤下公告'));
      await tester.pumpAndSettle();
      expect(
        find.text('撤下后不再显示为当前公告，历史记录仍会保留。', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('历史记录仍会保留。'), findsOneWidget);
      expect(port.writes, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, '撤下公告'));
      await tester.pumpAndSettle();
      expect(port.writes.single.action, 'withdraw');
      expect(find.text('暂无当前公告'), findsOneWidget);
      expect(find.text('已撤下'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown save retains draft and close requires explicit discard',
    (tester) async {
      final port = AnnouncementsFake()
        ..outcome = const CommunityAnnouncementOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      addTearDown(port.changes.close);
      await openAnnouncements(tester, port, width: 420);
      await tester.tap(find.text('发布新公告'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('announcement-title')),
        '待核对草稿',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, '发布公告'));
      await tester.tap(find.widgetWithText(FilledButton, '发布公告'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未确认是否保存成功'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'community-announcements-unknown-narrow');
      await tester.tap(find.text('刷新公告'));
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(1));
      expect(find.text('待核对草稿'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '丢弃草稿'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
      expect(port.writes, hasLength(1));
    },
  );
  testWidgets('ordinary members cannot publish edit or withdraw', (
    tester,
  ) async {
    final port = AnnouncementsFake()..allowed = false;
    addTearDown(port.changes.close);
    await openAnnouncements(tester, port);
    expect(find.text('发布新公告'), findsNothing);
    expect(find.text('编辑当前公告'), findsNothing);
    expect(find.text('撤下公告'), findsNothing);
  });
  testWidgets(
    'account invalidation closes confirmation and clears the private draft',
    (tester) async {
      final port = AnnouncementsFake();
      addTearDown(port.changes.close);
      await openAnnouncements(tester, port);
      await tester.tap(find.text('发布新公告'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('announcement-title')),
        '私有草稿',
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('私有草稿'), findsNothing);
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'production workspace renders announcement entry and opens center',
    (tester) async {
      final port = AnnouncementsWorkspaceFake();
      addTearDown(port.changes.close);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('community-announcement-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAnnouncementsDialog), findsOneWidget);
      expect(find.text('远航准备通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('removing the source entry closes its center and confirmation', (
    tester,
  ) async {
    final port = AnnouncementsFake();
    addTearDown(port.changes.close);
    late StateSetter change;
    var visible = true;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('zh', 'CN'),
        ),
        home: StatefulBuilder(
          builder: (_, update) {
            change = update;
            return Scaffold(
              body: visible
                  ? CommunityAnnouncementEntry(port: port, targetRef: target)
                  : const SizedBox(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('community-announcement-entry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布新公告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('announcement-title')),
      '原组织草稿',
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    change(() => visible = false);
    await tester.pumpAndSettle();
    expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('原组织草稿'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// Explicit synthetic typed UI authority; no real Owner, service or durable IO.
class OfficialAnnouncementFormFixture extends FixtureManagementPort {
  OfficialAnnouncementFormFixture(this.reads);
  final AnnouncementsFake reads;
  OrganizationAnnouncementIntent? unknown;
  @override
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef) async {
    editorReads++;
    return OrganizationAnnouncementEditor.parse({
      'schemaVersion': 1,
      'state': 'available',
      'sourceRef': sourceRef,
      'editRef': 'e' * 32,
      'revision': reads.revision,
      'allowedActions': reads.current == null
          ? ['publish']
          : ['publish', 'edit', 'withdraw'],
      'current': reads.current == null
          ? null
          : {
              'announcementRef': 'f' * 32,
              'title': reads.current!['title'],
              'content': reads.current!['content'],
            },
    }, sourceRef);
  }

  void _commit(OrganizationAnnouncementIntent intent) {
    reads.revision++;
    reads.current = intent.action == 'withdraw'
        ? null
        : {
            ...announcementRow(),
            'title': intent.title!,
            'content': intent.content!,
            'revision': reads.revision,
            'author': announcementAuthor(hasAvatar: false),
            'editor': announcementAuthor(hasAvatar: false),
          };
  }

  @override
  Future<OrganizationAnnouncementOutcome> manage(
    OrganizationAnnouncementIntent intent,
  ) async {
    managed.add(intent);
    if (failManage) {
      unknown = intent;
      pending = {
        'schemaVersion': 1,
        'kind': 'pending',
        'offset': 0,
        'totalCount': 1,
        'items': [
          {
            'requestId': intent.requestId,
            'sourceRef': intent.sourceRef,
            'action': intent.action,
            'requestedAt': '2026-10-17T00:00:00Z',
            'status': 'unknown',
          },
        ],
      };
      return OrganizationAnnouncementOutcome.unknown(intent);
    }
    _commit(intent);
    return OrganizationAnnouncementOutcome.parseManage(
      {...intent.toPayload(), 'status': 'accepted', 'revision': reads.revision}
        ..remove('title')
        ..remove('content')
        ..remove('announcementRef'),
      intent,
    );
  }

  @override
  Future<OrganizationAnnouncementOutcome> query(
    String requestId, {
    String? expectedSourceRef,
    String? expectedAction,
  }) async {
    queries.add((requestId, expectedSourceRef, expectedAction));
    if (queryAccepted) _commit(unknown!);
    return OrganizationAnnouncementOutcome.parseQuery(
      {
        'schemaVersion': 1,
        'kind': 'query',
        'requestId': requestId,
        if (queryAccepted) ...{
          'sourceRef': expectedSourceRef,
          'action': expectedAction,
          'status': 'accepted',
          'revision': reads.revision,
        } else ...{
          'status': 'unknown',
          'error': 'notFound',
        },
      },
      requestId,
      expectedSourceRef: expectedSourceRef,
      expectedAction: expectedAction,
    );
  }
}
