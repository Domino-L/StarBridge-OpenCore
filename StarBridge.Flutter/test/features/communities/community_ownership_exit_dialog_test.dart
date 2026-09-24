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
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_copy.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import 'community_ownership_exit_test.dart' show ExitFake, exitPayload;
import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

String id(int value) => value.toRadixString(16).padLeft(32, '0');
Finder candidate(String ref) => find.byKey(ValueKey('successor-$ref'));
String t(WidgetTester tester, String key) => ownershipExitText(
  tester.element(find.byType(CommunityOwnershipExitDialog)),
  key,
);

WorkspaceTestPort memberWorkspace({bool self = false, bool owner = true}) {
  final port = WorkspaceTestPort();
  port.reader = (_, _, _) async {
    final payload = workspacePayload();
    (payload['access'] as Map)['isOwner'] = owner;
    ((payload['members'] as List).single as Map)['isSelf'] = self;
    return CommunityWorkspace.parse(payload);
  };
  addTearDown(port.changes.close);
  return port;
}

Future<void> openExit(
  WidgetTester tester,
  CommunityOwnershipExitPort port,
  CommunityWorkspacePort workspace, {
  String? target,
  Locale locale = const Locale('zh', 'CN'),
  double width = 1000,
  Stream<void>? invalidations,
  bool pendingAvatar = false,
}) async {
  tester.view.physicalSize = Size(width, 850);
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('exit-capture'),
                child: CommunityOwnershipExitDialog(
                  port: port,
                  workspacePort: workspace,
                  targetRef: target ?? 'a' * 32,
                  contextInvalidations: invalidations,
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
  if (pendingAvatar) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1000.0]) {
      testWidgets(
        'candidate and explicit exit confirmation fit $locale $width',
        (tester) async {
          final port = ExampleCommunities();
          addTearDown(port.close);
          await openExit(
            tester,
            port,
            port,
            target: '00000000000000000000000000000002',
            locale: locale,
            width: width,
          );
          expect(candidate(id(0)), findsNothing);
          expect(find.byType(UserAvatarMenu), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.tap(candidate(id(1)));
          await tester.pumpAndSettle();
          expect(find.text(t(tester, 'consequence')), findsOneWidget);
          expect(find.text('副负责人'), findsNothing);
          expect(
            (await port.readWorkspace(
              '00000000000000000000000000000002',
              '',
              0,
            )).access['isOwner'],
            isTrue,
          );
          expect(tester.takeException(), isNull);
          if (locale == const Locale('zh', 'CN') && width == 1000) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('exit-capture')),
            );
            await tester.runAsync(() async {
              final pixels = await boundary.toImage(pixelRatio: 1);
              final png = await pixels.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('build/community-owner-exit.png')
                  .writeAsBytes(png!.buffer.asUint8List());
              pixels.dispose();
            });
          }
          await tester.tap(find.text(t(tester, 'cancel')));
          await tester.pumpAndSettle();
          expect(
            (await port.readWorkspace(
              '00000000000000000000000000000002',
              '',
              0,
            )).access['isOwner'],
            isTrue,
          );
        },
      );
    }
  }

  testWidgets(
    'pagination search and avatar menu reach members beyond first page',
    (tester) async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      await openExit(
        tester,
        port,
        port,
        target: '00000000000000000000000000000002',
      );
      final next = find.text(t(tester, 'next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(candidate(id(20)), findsOneWidget);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Example_Member_40');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(candidate(id(40)), findsOneWidget);
      expect(candidate(id(20)), findsNothing);
      await tester.tap(find.byType(UserAvatarMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t(tester, 'choose')).last);
      await tester.pumpAndSettle();
      expect(find.text('示例成员 40'), findsOneWidget);
      await tester.tap(find.text(t(tester, 'back')));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'no-such-member');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(t(tester, 'noMatch')), findsOneWidget);
    },
  );

  testWidgets(
    'late candidate read cannot restore rows after context invalidation',
    (tester) async {
      final port = ExitFake();
      addTearDown(port.changes.close);
      final workspace = memberWorkspace();
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      await openExit(tester, port, workspace, invalidations: changes.stream);
      final pending = Completer<CommunityWorkspace>();
      workspace.reader = (_, _, _) => pending.future;
      await tester.enterText(find.byType(TextField), 'private search');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      changes.add(null);
      await tester.pump();
      final payload = workspacePayload();
      (payload['access'] as Map)['isOwner'] = true;
      ((payload['members'] as List).single as Map)['isSelf'] = false;
      pending.complete(CommunityWorkspace.parse(payload));
      await tester.pumpAndSettle();
      expect(candidate('b' * 32), findsNothing);
      expect(find.text('private search'), findsNothing);
      expect(find.text(t(tester, 'identityUnavailable')), findsOneWidget);
      expect(port.reads, 0);
      expect(port.writes, 0);
    },
  );

  testWidgets('wrong organization member page cannot be selected', (
    tester,
  ) async {
    final port = ExitFake();
    addTearDown(port.changes.close);
    final workspace = memberWorkspace();
    workspace.reader = (_, _, _) async {
      final payload = workspacePayload(target: 'c' * 32);
      (payload['access'] as Map)['isOwner'] = true;
      ((payload['members'] as List).single as Map)['isSelf'] = false;
      return CommunityWorkspace.parse(payload);
    };
    await openExit(tester, port, workspace);
    expect(candidate('b' * 32), findsNothing);
    expect(find.text(t(tester, 'dataInvalid')), findsOneWidget);
    expect(port.reads, 0);
  });

  testWidgets(
    'late avatar access denial clears an open successor confirmation',
    (tester) async {
      final port = ExitFake();
      addTearDown(port.changes.close);
      final workspace = memberWorkspace();
      final media = Completer<Map<String, Object?>>();
      workspace.reader = (_, _, _) async {
        final payload = workspacePayload();
        (payload['access'] as Map)['isOwner'] = true;
        final member = (payload['members'] as List).single as Map;
        member['isSelf'] = false;
        member['hasAvatar'] = true;
        return CommunityWorkspace.parse(payload);
      };
      workspace.mediaReader = (_, _) => media.future;
      await openExit(tester, port, workspace, pendingAvatar: true);
      await tester.tap(candidate('b' * 32));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      media.completeError(const CommunityFailure('notAllowed'));
      await tester.pumpAndSettle();
      expect(find.text('Organization A'), findsNothing);
      expect(find.text(t(tester, 'notAllowed')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(port.writes, 0);
    },
  );

  testWidgets(
    'workspace exit refreshes parent even after member read becomes forbidden',
    (tester) async {
      final port = ExampleCommunities();
      final model = CommunitiesModule(port);
      addTearDown(port.close);
      addTearDown(model.dispose);
      await model.refresh();
      model.open(
        model.directory!.items.singleWhere(
          (c) => c.targetRef == '00000000000000000000000000000002',
        ),
      );
      var refreshed = 0;
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000002',
          onGovernanceChanged: () async {
            refreshed++;
            await model.refresh(preserveSelection: true);
            await model.refreshJoined();
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-danger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leave-with-successor')));
      await tester.pumpAndSettle();
      await tester.tap(candidate(id(1)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CommunityOwnershipExitDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(refreshed, 1);
      expect(model.selected, isNull);
      expect(model.joined.map((c) => c.targetRef), [
        '00000000000000000000000000000001',
      ]);
      expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown exit requires reload and explicit retry without another candidate',
    (tester) async {
      final port = ExitFake()
        ..outcome = const CommunityOwnershipTransferOutcome('unknown');
      addTearDown(port.changes.close);
      await openExit(tester, port, memberWorkspace());
      await tester.tap(candidate('b' * 32));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(find.text(t(tester, 'back')), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text(t(tester, 'reload')));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      port.outcome = const CommunityOwnershipTransferOutcome('accepted');
      await tester.tap(find.text(t(tester, 'retry')));
      await tester.pumpAndSettle();
      expect(port.confirmations, [false, true]);
      expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
    },
  );

  for (final writing in [false, true]) {
    testWidgets(
      'invalidation clears private data and ignores late completion writing=$writing',
      (tester) async {
        final port = ExitFake();
        addTearDown(port.changes.close);
        final changed = StreamController<void>.broadcast();
        addTearDown(changed.close);
        await openExit(
          tester,
          port,
          memberWorkspace(),
          invalidations: changed.stream,
        );
        if (!writing) port.pendingRead = Completer<CommunityOwnershipExit>();
        await tester.tap(candidate('b' * 32));
        await tester.pump();
        if (writing) {
          await tester.pumpAndSettle();
          port.pendingWrite = Completer<CommunityOwnershipTransferOutcome>();
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, t(tester, 'cancel')),
                )
                .onPressed,
            isNull,
          );
        }
        changed.add(null);
        await tester.pump();
        if (writing) {
          port.pendingWrite!.complete(
            const CommunityOwnershipTransferOutcome('accepted'),
          );
        } else {
          port.pendingRead!.complete(
            CommunityOwnershipExit.parse(exitPayload()),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Organization A'), findsNothing);
        expect(find.text(t(tester, 'identityUnavailable')), findsOneWidget);
        expect(find.byType(CommunityOwnershipExitDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty owner, non-owner and unavailable capability never write', (
    tester,
  ) async {
    final port = ExitFake();
    addTearDown(port.changes.close);
    await openExit(tester, port, memberWorkspace(self: true));
    expect(find.text(t(tester, 'empty')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await openExit(tester, port, memberWorkspace(owner: false));
    expect(candidate('b' * 32), findsNothing);
    expect(find.text(t(tester, 'notAllowed')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    port.ownershipExitAvailable = false;
    await openExit(tester, port, memberWorkspace());
    expect(candidate('b' * 32), findsNothing);
    expect(port.reads, 0);
    expect(port.writes, 0);
  });
}
