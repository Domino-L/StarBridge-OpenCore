import 'community_image_test_support.dart';

import 'dart:async';
import 'dart:convert';
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
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_session.dart';
import 'package:starbridge_flutter/features/communities/community_member_banner.dart';

import 'community_workspace_test.dart';
import '../friends/social_layout_test.dart' show loadFonts;

Widget host(
  CommunityWorkspacePort port,
  Locale locale, {
  String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  Future<void> Function()? onGovernanceChanged,
  String? organizationKey,
  bool disableAnimations = false,
  CommunityWorkspaceSession? session,
  void Function(String)? onFocused,
  bool active = true,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
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
  home: Scaffold(
    backgroundColor: FutureRestraintStyle.resolve(AppearanceMode.dark)
        .surfaces
        .ground
        .fill,
    body: RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TickerMode(
          enabled: active,
          child: CommunityWorkspaceView(
            port: port,
            targetRef: target,
            organizationKey: organizationKey,
            session: session,
            onFocused: onFocused,
            onGovernanceChanged: onGovernanceChanged,
            actions: const Text('Existing membership action'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> openMemberActions(WidgetTester tester, String memberRef) async {
  final menu = find.byKey(ValueKey('member-actions-$memberRef'));
  if (menu.evaluate().isEmpty) {
    return; // No actions for self or an unauthorized viewer.
  }
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await settleCommunityImages(tester);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('offline members suppress stale runtime values like WPF S2', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    port.reader = (target, query, offset) async {
      final payload = workspacePayload(target: target, query: query);
      final row = (payload['members'] as List).single as Map<String, Object?>;
      row.addAll({
        'online': false,
        'liveStatus': 'Offline',
        'ship': 'Unknown',
        'location': 'Unknown',
      });
      return CommunityWorkspace.parse(payload);
    };
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await settleCommunityImages(tester);
    final banner = tester.widget<CommunityMemberBanner>(
      find.byType(CommunityMemberBanner),
    );
    expect(
      (banner.server, banner.ship, banner.location),
      ('未进入游戏', '未进入游戏', '未进入游戏'),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'member columns match WPF and header retains required information',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await settleCommunityImages(tester);
      final banner = find.byType(CommunityMemberBanner);
      final fields = ['示例成员 · 你', '探索', '美服', 'C2 Hercules', '奥里森', '游戏中'];
      double? previous;
      for (final field in fields) {
        final value = find.descendant(of: banner, matching: find.text(field));
        expect(value, findsOneWidget);
        final x = tester.getTopLeft(value).dx;
        if (previous != null) expect(x, greaterThan(previous));
        previous = x;
      }
      expect(find.text('加入时间'), findsNothing);
      expect(find.text('到达待确认'), findsNothing);
      expect(find.text('ARRIVAL'), findsNothing);
      final information = find.byKey(const Key('community-header-information'));
      for (final label in ['在线信息', '活跃时间', '公告', '组织联系方式']) {
        expect(
          find.descendant(of: information, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        tester.getTopLeft(information).dy,
        lessThan(tester.getTopLeft(banner).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets(
        'Workspace ${locale.toLanguageTag()} fits $width and keeps avatar menu',
        (tester) async {
          tester.view.physicalSize = Size(width, 1050);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = WorkspaceTestPort();
          addTearDown(port.changes.close);
          await tester.pumpWidget(host(port, locale));
          await settleCommunityImages(tester);
          expect(find.text('Organization A'), findsOneWidget);
          expect(
            find.textContaining('organization-contact'),
            width < 1000 ? findsNothing : findsOneWidget,
          );
          expect(find.text('Existing membership action'), findsOneWidget);
          expect(find.textContaining('must-not-be-rendered'), findsNothing);
          await tester.scrollUntilVisible(
            find.byType(UserAvatarMenu),
            250,
            scrollable: find.byType(Scrollable).last,
          );
          expect(tester.takeException(), isNull);
          final avatar = find.byType(UserAvatarMenu);
          await tester.tap(avatar);
          await settleCommunityImages(tester);
          expect(find.byType(MenuItemButton), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('Account invalidation removes contacts, members and open menu', (
    tester,
  ) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(port, const Locale('en')));
    await settleCommunityImages(tester);
    await tester.ensureVisible(find.byType(UserAvatarMenu));
    await tester.tap(find.byType(UserAvatarMenu));
    await settleCommunityImages(tester);
    port.changes.add(null);
    await settleCommunityImages(tester);
    expect(find.textContaining('organization-contact'), findsNothing);
    expect(find.byType(UserAvatarMenu), findsNothing);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text('Existing membership action'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Changing organization ignores old delayed workspace', (
    tester,
  ) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    final delayed = Completer<CommunityWorkspace>();
    port.reader = (target, query, offset) => target.startsWith('a')
        ? delayed.future
        : Future.value(
            CommunityWorkspace.parse(
              workspacePayload(target: target)..['name'] = 'Organization B',
            ),
          );
    await tester.pumpWidget(host(port, const Locale('en')));
    await tester.pump();
    await tester.pumpWidget(host(port, const Locale('en'), target: 'c' * 32));
    await settleCommunityImages(tester);
    delayed.complete(CommunityWorkspace.parse(workspacePayload()));
    await settleCommunityImages(tester);
    expect(find.text('Organization B'), findsOneWidget);
    expect(find.text('Organization A'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Native image decode is bounded and bypasses global image cache',
    (tester) async {
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (target, _, _) async => CommunityWorkspace.parse(
        workspacePayload(target: target)..['hasLogo'] = true,
      );
      port.mediaReader = (offset, _) async => mediaChunk(image, offset);
      final before = PaintingBinding.instance.imageCache.currentSize;
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await settleCommunityImages(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settleCommunityImages(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(PaintingBinding.instance.imageCache.currentSize, before);
      port.changes.add(null);
      await settleCommunityImages(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Render workspace review artifact without starting a client', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await settleCommunityImages(tester);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('build/community-workspace-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
