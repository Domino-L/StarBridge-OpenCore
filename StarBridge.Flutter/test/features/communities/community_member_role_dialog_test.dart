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
import 'package:starbridge_flutter/features/communities/community_member_role_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_copy.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';

import 'community_member_role_test.dart' show MemberRoleFake;
import 'community_workspace_test.dart' show workspacePayload;
import 'community_workspace_view_test.dart' show host, openMemberActions;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> openAssignment(
  WidgetTester tester,
  MemberRoleFake port, {
  double width = 1000,
  Locale locale = const Locale('zh', 'CN'),
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(port.changes.close);
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open assignment'),
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('member-role-capture'),
                child: CommunityMemberRoleDialog(
                  port: port,
                  targetRef: 'a' * 32,
                  memberRef: 'b' * 32,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open assignment'));
  await tester.pumpAndSettle();
}

String copy(WidgetTester tester, String key) =>
    memberRoleText(tester.element(find.byType(CommunityMemberRoleDialog)), key);
void main() {
  setUpAll(loadFonts);
  testWidgets(
    'closing a draft requires confirmation and cancellation preserves selection',
    (tester) async {
      final port = MemberRoleFake();
      await openAssignment(tester, port);
      await tester.tap(
        find.byKey(const ValueKey('assign-option-custom_navigation')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(copy(tester, 'close')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, copy(tester, 'cancel')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('assign-option-custom_navigation')),
            )
            .selected,
        isTrue,
      );
      expect(port.writes, 0);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final width in [420.0, 1000.0]) {
      testWidgets(
        'assignment confirmation and actual reread $locale at $width',
        (tester) async {
          final port = MemberRoleFake();
          await openAssignment(tester, port, width: width, locale: locale);
          expect(find.text('示例成员'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('assign-option-custom_navigation')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, copy(tester, 'assignRole')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(port.writes, 0);
          expect(find.textContaining('→ 领航员'), findsOneWidget);
          await tester.tap(
            find.widgetWithText(TextButton, copy(tester, 'cancel')),
          );
          await tester.pumpAndSettle();
          expect(port.writes, 0);
          await tester.tap(
            find.widgetWithText(FilledButton, copy(tester, 'assignRole')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, copy(tester, 'assignRole')).last,
          );
          await tester.pumpAndSettle();
          expect(port.writes, 1);
          expect(port.reads, 2);
          expect(find.byType(CommunityMemberRoleDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('account change removes private confirmation and member name', (
    tester,
  ) async {
    final port = MemberRoleFake();
    await openAssignment(tester, port);
    await tester.tap(
      find.byKey(const ValueKey('assign-option-custom_navigation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, copy(tester, 'assignRole')),
    );
    await tester.pumpAndSettle();
    port.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('示例成员'), findsNothing);
    expect(port.writes, 0);
  });
  for (final access in ['owner', 'member', 'self', 'targetOwner', 'oldHost']) {
    testWidgets('workspace assignment button and avatar action obey $access', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = MemberRoleFake()..memberRoleAvailable = access != 'oldHost';
      addTearDown(port.changes.close);
      var workspaceReads = 0;
      port.reader = (target, query, offset) async {
        workspaceReads++;
        final data = workspacePayload(target: target, query: query);
        (data['access'] as Map)['isOwner'] = access != 'member';
        final member = (data['members'] as List).first as Map;
        member['isSelf'] = access == 'self';
        member['isOwner'] = access == 'targetOwner';
        member['roleTitle'] = port.currentRole.isEmpty ? '成员' : '领航员';
        return CommunityWorkspace.parse(data);
      };
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(UserAvatarMenu),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      final action = find.byKey(ValueKey('assign-member-${'b' * 32}'));
      await openMemberActions(tester, 'b' * 32);
      expect(action, access == 'owner' ? findsOneWidget : findsNothing);
      expect(
        find.text('操作'),
        access == 'owner' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(ValueKey('member-actions-${'b' * 32}')),
        access == 'owner' ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<UserAvatarMenu>(find.byType(UserAvatarMenu))
            .actions
            .isNotEmpty,
        access == 'owner',
      );
      if (access == 'owner') {
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(CommunityMemberRoleDialog), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('assign-option-custom_navigation')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, copy(tester, 'assignRole')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, copy(tester, 'assignRole')).last,
        );
        await tester.pumpAndSettle();
        expect(workspaceReads, 2);
        expect(find.text('领航员'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('changing organization clears an open member confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = MemberRoleFake();
    addTearDown(port.changes.close);
    port.reader = (target, query, offset) async {
      final data = workspacePayload(target: target, query: query);
      (data['access'] as Map)['isOwner'] = true;
      ((data['members'] as List).first as Map)['isSelf'] = false;
      return CommunityWorkspace.parse(data);
    };
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    final action = find.byKey(ValueKey('assign-member-${'b' * 32}'));
    await openMemberActions(tester, 'b' * 32);
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('assign-option-custom_navigation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, copy(tester, 'assignRole')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(
      host(port, const Locale('zh', 'CN'), target: 'c' * 32),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CommunityMemberRoleDialog),
        matching: find.textContaining('示例成员'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('assign-option-custom_navigation')),
      findsNothing,
    );
    expect(port.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('capture member role dialog', (tester) async {
    final port = MemberRoleFake();
    await openAssignment(tester, port);
    await tester.tap(
      find.byKey(const ValueKey('assign-option-custom_navigation')),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('member-role-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/community-member-role.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
