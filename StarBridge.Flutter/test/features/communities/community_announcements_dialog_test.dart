import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
          child: CommunityAnnouncementEntry(port: port, targetRef: targetRef),
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
      expect(find.byType(MenuAnchor), findsNWidgets(2));
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
