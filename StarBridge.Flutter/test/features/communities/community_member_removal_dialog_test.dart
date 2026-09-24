import 'dart:async';
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
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_copy.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';

import 'community_member_removal_test.dart';
import 'community_workspace_test.dart' show workspacePayload;
import 'community_workspace_view_test.dart' show host, openMemberActions;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> openRemoval(
  WidgetTester tester,
  RemovalFake port, {
  Locale locale = const Locale('zh', 'CN'),
  double width = 1000,
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
            child: const Text('Open'),
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('removal-capture'),
                child: CommunityMemberRemovalDialog(
                  port: port,
                  targetRef: 'a' * 32,
                  memberRef: 'b' * 32,
                  organizationName: '探索组织',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, String key) => memberRemovalText(
  tester.element(find.byType(CommunityMemberRemovalDialog)),
  key,
);

void main() {
  setUpAll(loadFonts);
  for (final width in [420.0, 800.0, 1200.0]) {
    testWidgets(
      'role and removal actions coexist in actual example workspace $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = ExampleCommunities();
        addTearDown(port.close);
        await tester.pumpWidget(
          host(
            port,
            const Locale('en'),
            target: '00000000000000000000000000000002',
          ),
        );
        await tester.pumpAndSettle();
        final id = '1'.padLeft(32, '0');
        final action = find.byKey(ValueKey('remove-member-$id'));
        await openMemberActions(tester, id);
        await tester.scrollUntilVisible(
          action,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(find.byKey(ValueKey('assign-member-$id')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('remove-member-$id')), findsNothing);
        expect(
          (await port.readWorkspace(
            '00000000000000000000000000000002',
            '',
            0,
          )).totalCount,
          47,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final width in [420.0, 1000.0]) {
      testWidgets(
        'removal confirmation has identity and red action $locale $width',
        (tester) async {
          final port = RemovalFake();
          await openRemoval(tester, port, locale: locale, width: width);
          expect(find.text('示例成员'), findsOneWidget);
          expect(find.text('探索组织'), findsOneWidget);
          final button = tester.widget<FilledButton>(find.byType(FilledButton));
          final context = tester.element(
            find.byType(CommunityMemberRemovalDialog),
          );
          expect(
            button.style!.backgroundColor!.resolve({}),
            context.tokens.colors.danger,
          );
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.widgetWithText(TextButton, text(tester, 'cancel')),
          );
          await tester.pumpAndSettle();
          expect(port.writes, 0);
          expect(find.byType(CommunityMemberRemovalDialog), findsNothing);
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(port.writes, 1);
          expect(find.byType(CommunityMemberRemovalDialog), findsNothing);
        },
      );
    }
  }
  testWidgets(
    'unknown result requires reload and visibly labelled explicit retry',
    (tester) async {
      final port = RemovalFake()
        ..outcome = const CommunityMemberRemovalOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      await openRemoval(tester, port);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text(text(tester, 'retry')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, text(tester, 'reload')));
      await tester.pumpAndSettle();
      port.outcome = const CommunityMemberRemovalOutcome('accepted');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(port.confirmations, [false, true]);
      expect(find.byType(CommunityMemberRemovalDialog), findsNothing);
    },
  );
  testWidgets(
    'switching account removes identity and cannot confirm late success',
    (tester) async {
      final port = RemovalFake()
        ..pendingWrite = Completer<CommunityMemberRemovalOutcome>();
      await openRemoval(tester, port);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('示例成员'), findsNothing);
      expect(find.text('探索组织'), findsNothing);
      port.pendingWrite!.complete(
        const CommunityMemberRemovalOutcome('accepted'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommunityMemberRemovalDialog), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
  for (final access in [
    'owner',
    'manager',
    'member',
    'self',
    'targetOwner',
    'oldHost',
  ]) {
    testWidgets(
      'workspace member removal gates $access and refreshes actual rows',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = RemovalFake()
          ..memberRemovalAvailable = access != 'oldHost';
        addTearDown(port.changes.close);
        var workspaceReads = 0;
        port.reader = (target, query, offset) async {
          workspaceReads++;
          final data = workspacePayload(target: target, query: query);
          (data['access'] as Map)['isOwner'] =
              access != 'member' && access != 'manager';
          (data['access'] as Map)['canRemoveMembers'] = access == 'manager';
          final member = (data['members'] as List).first as Map;
          member['isSelf'] = access == 'self';
          member['isOwner'] = access == 'targetOwner';
          if (port.removed) {
            data['members'] = [];
            data['matchedCount'] = data['totalCount'] = 0;
          }
          return CommunityWorkspace.parse(data);
        };
        await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(UserAvatarMenu),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final action = find.byKey(ValueKey('remove-member-${'b' * 32}'));
        await openMemberActions(tester, 'b' * 32);
        final allowed = access == 'owner' || access == 'manager';
        expect(action, allowed ? findsOneWidget : findsNothing);
        expect(find.text('操作'), allowed ? findsOneWidget : findsNothing);
        expect(
          find.byKey(ValueKey('member-actions-${'b' * 32}')),
          allowed ? findsOneWidget : findsNothing,
        );
        expect(
          tester
              .widget<UserAvatarMenu>(find.byType(UserAvatarMenu))
              .actions
              .isNotEmpty,
          allowed,
        );
        if (allowed) {
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(workspaceReads, 2);
          expect(find.text('示例成员'), findsNothing);
          expect(port.writes, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('changing organization clears open removal without a write', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = RemovalFake();
    addTearDown(port.changes.close);
    port.reader = (target, query, offset) async {
      final data = workspacePayload(target: target, query: query);
      (data['access'] as Map)['isOwner'] = true;
      ((data['members'] as List).first as Map)['isSelf'] = false;
      return CommunityWorkspace.parse(data);
    };
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    final action = find.byKey(ValueKey('remove-member-${'b' * 32}'));
    await openMemberActions(tester, 'b' * 32);
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      host(port, const Locale('zh', 'CN'), target: 'd' * 32),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CommunityMemberRemovalDialog),
        matching: find.text('示例成员'),
      ),
      findsNothing,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(port.writes, 0);
  });
  testWidgets('capture real removal confirmation', (tester) async {
    final port = RemovalFake();
    await openRemoval(tester, port);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('removal-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/community-member-removal.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
