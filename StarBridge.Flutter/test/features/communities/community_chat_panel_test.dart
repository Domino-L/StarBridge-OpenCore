import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_message_bubble.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';

import 'community_chat_controller_test.dart' show FakeChat, page;
import 'community_chat_test.dart' show ChatDetailFake, chatPage;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

Future<void> showChat(
  WidgetTester tester,
  CommunityChatPort port, {
  String? targetRef,
  Locale locale = const Locale('zh', 'CN'),
  double width = 1000,
  bool visible = true,
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = Size(width, 760);
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
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: RepaintBoundary(
            key: const ValueKey('chat-capture'),
            child: CommunityChatPanel(
              port: port,
              targetRef: targetRef ?? 'a' * 32,
              name: 'Northwind 联合组织',
              onBack: onBack ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  testWidgets('polling an already loaded empty chat stays silent', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page([], latest: 0, unread: 0, older: false);
    addTearDown(port.changes.close);
    await showChat(tester, port);
    port.heldRead = Completer();
    final before = port.reads.length;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(port.reads.length, before + 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    port.heldRead!.complete(page([], latest: 0, unread: 0, older: false));
    await tester.pumpAndSettle();
    port.heldRead = Completer();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    port.heldRead!.complete(page([], latest: 0, unread: 0, older: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'same sender avatar is fetched once for multiple visible messages',
    (tester) async {
      final media = ChatDetailFake();
      final payload = chatPage();
      for (final row in payload['messages'] as List) {
        (row as Map)['hasAttachment'] = false;
      }
      media.pageOverride = CommunityChatPage.parse(payload);
      await showChat(tester, media);
      final chunksPerImage = (media.bytes.length / (192 * 1024)).ceil();
      expect(
        media.reads,
        chunksPerImage,
        reason:
            'Messages from one sender must share one in-flight avatar read.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('scrolling remounts messages without fetching avatars again', (
    tester,
  ) async {
    final media = ChatDetailFake();
    final payload = chatPage();
    final template = Map<String, Object?>.from(
      (payload['messages'] as List).first as Map,
    );
    payload['messages'] = [
      for (var i = 1; i <= 40; i++)
        {
          ...template,
          'sequence': i,
          'messageRef': i.toRadixString(16).padLeft(32, '0'),
          'hasAttachment': false,
          'text': 'Message $i',
        },
    ];
    payload['oldestSequence'] = 1;
    payload['latestSequence'] = 40;
    payload['hasOlder'] = false;
    media.pageOverride = CommunityChatPage.parse(payload);
    await showChat(tester, media);
    final list = tester.widget<ListView>(find.byType(ListView).last);
    final scroll = list.controller!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Message 1'), findsOneWidget);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Message 40'), findsOneWidget);
    expect(media.reads, (media.bytes.length / (192 * 1024)).ceil());
    await tester.pumpWidget(const SizedBox());
  });
  late FakeChat port;
  setUp(() {
    port = FakeChat()..next = page([10, 12], latest: 12, older: false);
  });
  tearDown(() => port.changes.close());
  final input = find.byKey(const ValueKey('community-chat-input'));
  testWidgets(
    'example organization workspace exposes chat and returns to profile',
    (tester) async {
      final example = ExampleCommunities();
      addTearDown(example.close);
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          example,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000002',
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('community-section-chat'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(CommunityChatPanel), findsOneWidget);
      await tester.tap(find.byTooltip('返回组织资料'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityChatPanel), findsNothing);
      expect(button, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'actual example chat sends with Enter and shows self avatar on right',
    (tester) async {
      final example = ExampleCommunities();
      addTearDown(example.close);
      const target = '00000000000000000000000000000002';
      await showChat(tester, example, targetRef: target);
      expect(find.byType(UserAvatarMenu), findsWidgets);
      await tester.enterText(input, '示例组织发送检查');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final messages = await example.readChat(target, after: 56);
      expect(messages.messages, hasLength(1));
      expect(messages.messages.single.isSelf, isTrue);
      expect(find.text('示例组织发送检查'), findsOneWidget);
      final listRect = tester.getRect(find.byType(ListView).last);
      for (final avatar in find.byType(UserAvatarMenu).evaluate()) {
        expect(
          tester.getRect(find.byWidget(avatar.widget)).right,
          lessThanOrEqualTo(listRect.right - 16),
          reason: 'The scrollbar gutter must not cover message avatars.',
        );
      }
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('chat-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/test-artifacts/community-chat-example.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await example.close();
      await tester.pumpAndSettle();
      expect(find.text('示例组织发送检查'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'actual example shares then imports preset through message card',
    (tester) async {
      final example = ExampleCommunities();
      addTearDown(example.close);
      const target = '00000000000000000000000000000002';
      await showChat(tester, example, targetRef: target);
      await tester.tap(find.text('分享浮层预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例浮层预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(
        (await example.readChat(
          target,
          after: 56,
        )).messages.single.hasAttachment,
        isTrue,
      );
      await tester.tap(find.widgetWithText(TextButton, '导入为新预设'));
      await tester.pumpAndSettle();
      expect((await example.readCommunityPresets()).presets, hasLength(1));
      await tester.tap(find.widgetWithText(FilledButton, '导入为新预设'));
      await tester.pumpAndSettle();
      expect((await example.readCommunityPresets()).presets, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Enter sends once; Shift+Enter does not send; rejection keeps draft',
    (tester) async {
      await showChat(tester, port);
      await tester.enterText(input, 'hello');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(port.sends, isEmpty);
      port.sendResult = const CommunityChatSendOutcome(
        'rejected',
        error: 'rateLimited',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(port.sends, hasLength(1));
      expect(
        tester.widget<TextField>(input).controller!.text,
        contains('hello'),
      );
      expect(find.textContaining('发送过于频繁'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('uncertain send cannot be duplicated and back protects draft', (
    tester,
  ) async {
    var returned = false;
    await showChat(tester, port, onBack: () => returned = true);
    port.sendResult = const CommunityChatSendOutcome(
      'unknown',
      error: 'outcomeUnknown',
    );
    await tester.enterText(input, 'uncertain');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(port.sends, hasLength(1));
    await tester.tap(find.byTooltip('返回组织资料'));
    await tester.pumpAndSettle();
    expect(returned, false);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'uncertain');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'visible reading confirms only once; unknown receipt does not loop',
    (tester) async {
      port.receipt = const CommunityChatReadReceipt(
        'unknown',
        error: 'outcomeUnknown',
      );
      await showChat(tester, port);
      expect(port.receipts, [12]);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(port.receipts, [12]);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(port.receipts, [12, 12]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hidden chat never marks messages read', (tester) async {
    await showChat(tester, port, visible: false);
    expect(port.receipts, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'own message uses right bubble and avatar; compact $locale has no overflow',
      (tester) async {
        port.next = page(
          [10, 12],
          latest: 12,
          older: false,
          localRequestId: 'b' * 32,
        );
        await showChat(tester, port, locale: locale, width: 420);
        final bubbles = tester.widgetList<ChatMessageBubble>(
          find.byType(ChatMessageBubble),
        );
        expect(bubbles.every((b) => !b.incoming), true);
        expect(find.byType(UserAvatarMenu), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('organization chat visual capture', (tester) async {
    await showChat(tester, port);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('chat-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build').create(recursive: true);
      await File('build/community-chat-ui.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
