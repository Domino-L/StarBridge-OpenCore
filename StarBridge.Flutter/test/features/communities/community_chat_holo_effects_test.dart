// Holo chat send/receive effects and the shared left online column
// (user decisions 2026-10-29: option B layout, tuned option one effects).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_holo_effects.dart';
import 'package:starbridge_flutter/features/communities/community_chat_holo_typing.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_workspace.dart';

import 'community_chat_controller_test.dart' show FakeChat, page;
import 'community_workspace_test.dart' show WorkspaceTestPort;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 860),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(body: OrganizationWorkspaceSurface(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Widget _panel(FakeChat port, CommunityChatController controller) =>
    CommunityChatPanel(
      port: port,
      controller: controller,
      targetRef: 'a' * 32,
      name: '主舰队',
      onBack: () {},
    );

void main() {
  late FakeChat port;
  late CommunityChatController controller;
  setUp(() {
    port = FakeChat()..next = page([10, 12, 14], latest: 14, unread: 1);
    controller = CommunityChatController(port, 'a' * 32, localEcho: true);
  });
  tearDown(() async {
    controller.dispose();
    await port.changes.close();
  });

  testWidgets('the first unread message on open gets the divider once', (
    tester,
  ) async {
    await _pump(tester, _panel(port, controller));
    final divider = find.byKey(const Key('community-chat-unread-break'));
    expect(divider, findsOneWidget);
    expect(find.text('以下是新消息'), findsOneWidget);
    expect(
      tester.getRect(divider).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Message 14')).top),
    );
    expect(
      tester.getRect(divider).top,
      greaterThanOrEqualTo(tester.getRect(find.text('Message 12')).bottom),
    );
    // Reading it does not move or remove the divider during this visit.
    port.next = page([], latest: 14, unread: 0);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(divider, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only a new arrival while following plays; history never', (
    tester,
  ) async {
    port.next = page([10, 12, 14], latest: 14, unread: 0);
    await _pump(tester, _panel(port, controller));
    // The first read never plays.
    expect(find.byType(CommunityChatHoloArrival), findsNothing);
    port.next = page([16], latest: 16, unread: 1);
    // The panel's own 3 s poll reads the new message.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final arrival = find.byType(CommunityChatHoloArrival);
    expect(arrival, findsOneWidget);
    expect(
      find.descendant(of: arrival, matching: find.text('Message 16')),
      findsOneWidget,
    );
    expect(
      tester.widget<CommunityChatHoloArrival>(arrival).kind,
      CommunityChatHoloArrivalKind.incoming,
    );
    // Within 0.2 s the text is fully revealed and readable.
    await tester.pump(const Duration(milliseconds: 150));
    final clip = tester.renderObject<RenderClipRect>(
      find.descendant(of: arrival, matching: find.byType(ClipRect)).first,
    );
    expect(clip.size.height, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion plays nothing and draws no texture', (
    tester,
  ) async {
    port.next = page([10, 12, 14], latest: 14, unread: 0);
    await _pump(tester, _panel(port, controller), reduceMotion: true);
    port.next = page([16], latest: 16, unread: 1);
    // The panel's own 3 s poll reads the new message.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final state = tester.state<CommunityChatPanelState>(
      find.byType(CommunityChatPanel),
    );
    expect(state.holoArrival.isAnimating, isFalse);
    expect(find.text('Message 16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first open without messages shows placeholders', (tester) async {
    final held = Completer<CommunityChatPage>();
    port.heldRead = held;
    await _pump(tester, _panel(port, controller), reduceMotion: true);
    expect(find.byKey(const Key('community-chat-skeleton')), findsOneWidget);
    held.complete(page([10, 12], latest: 12, unread: 0));
    port.heldRead = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-chat-skeleton')), findsNothing);
    expect(find.text('Message 12'), findsOneWidget);
  });

  testWidgets('the send button charges once there is a draft', (tester) async {
    port.next = page([10], latest: 10, unread: 0);
    await _pump(tester, _panel(port, controller));
    double charge() => tester
        .widget<TweenAnimationBuilder<double>>(
          find.descendant(
            of: find.byType(CommunityChatSendCharge),
            matching: find.byType(TweenAnimationBuilder<double>),
          ),
        )
        .tween
        .end!;
    expect(charge(), 0);
    await tester.enterText(
      find.byKey(const ValueKey('community-chat-input')),
      '集合',
    );
    await tester.pumpAndSettle();
    expect(charge(), 1);
    expect(tester.takeException(), isNull);
  });

  // User 2026-10-29: older history loads like WeChat when scrolling up.
  testWidgets('scrolling up near the top loads older history by itself', (
    tester,
  ) async {
    port.next = page(
      [for (var i = 100; i < 150; i++) i],
      latest: 149,
      unread: 0,
    );
    await _pump(tester, _panel(port, controller));
    final before = port.reads.length;
    port.next = page([90, 95], latest: 149, unread: 0, older: false);
    for (var i = 0; i < 40 && port.reads.length == before; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(port.reads.skip(before).any((r) => r.$2 == 100), isTrue);
    expect(controller.messages.first.sequence, 90);
    expect(tester.takeException(), isNull);
  });

  testWidgets('community holo chat keeps the online column on the left', (
    tester,
  ) async {
    final workspace = WorkspaceTestPort();
    addTearDown(workspace.changes.close);
    port.next = page([10], latest: 10, unread: 0);
    await _pump(
      tester,
      CommunityChatWorkspace(
        port: workspace,
        targetRef: 'a' * 32,
        onAllMembers: () {},
        chat: _panel(port, controller),
      ),
    );
    final pane = find.byKey(const Key('community-online-members'));
    expect(
      tester.getRect(pane).right,
      lessThan(tester.getRect(find.byType(CommunityChatPanel)).left),
    );
    expect(find.byKey(const Key('community-all-members')), findsOneWidget);
    expect(find.textContaining('游戏中 ·'), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-online-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getRect(pane).width, 44);
    await tester.tap(find.byKey(const Key('community-online-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-all-members')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
