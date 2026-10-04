import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import 'community_chat_controller_test.dart' show FakeChat, page;
import 'community_chat_panel_test.dart' show showChat;
import 'community_chat_test.dart' show chatPage;
import '../friends/social_layout_test.dart' show loadFonts;

ScrollController scrollOf(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView).last).controller!;

Finder message(int sequence) => find.byWidgetPredicate(
  (widget) =>
      widget is CommunityChatMessageTile && widget.message.sequence == sequence,
);

CommunityChatPage variedPage(int first, int last, {bool older = false}) {
  final data = chatPage();
  final row = Map<String, Object?>.from(
    (data['messages'] as List).first as Map,
  );
  data['oldestSequence'] = first;
  data['latestSequence'] = 100;
  data['hasOlder'] = older;
  data['messages'] = [
    for (var i = first; i <= last; i++)
      {
        ...row,
        'sequence': i,
        'messageRef': i.toRadixString(16).padLeft(32, '0'),
        'text': 'Message $i ${'Long wrapping fixture text. ' * (i % 5 + 1)}',
        'hasAvatar': false,
        'hasAttachment': false,
        'isSelf': false,
      },
  ];
  return CommunityChatPage.parse(data);
}

void main() {
  setUpAll(loadFonts);

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('new message affordance fits compact $locale', (tester) async {
      final port = FakeChat()
        ..next = page(
          List.generate(40, (i) => i + 1),
          latest: 40,
          unread: 0,
          older: false,
        );
      final model = CommunityChatController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await showChat(
        tester,
        port,
        controller: model,
        width: 420,
        locale: locale,
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, 700));
      await tester.pumpAndSettle();
      port.next = page([41], latest: 41, unread: 1, older: false);
      await model.refresh(silent: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = find.byType(OutlinedButton);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      if (locale.countryCode == 'CN') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('chat-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build').create(recursive: true);
          await File('build/community-chat-new-message-ui.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('incoming message does not pull a reader out of history', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page(
        List.generate(40, (i) => i + 1),
        latest: 40,
        unread: 0,
        older: false,
      );
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model);
    await tester.drag(find.byType(ListView).last, const Offset(0, 700));
    await tester.pumpAndSettle();
    final before = scrollOf(tester).offset;
    expect(scrollOf(tester).position.extentAfter, greaterThan(300));
    port.receipts.clear();
    port.next = page([41], latest: 41, unread: 1, older: false);
    await model.refresh(silent: true);
    await tester.pumpAndSettle();
    expect(scrollOf(tester).offset, closeTo(before, 1));
    expect(find.text('有新消息 · 回到最新'), findsOneWidget);
    expect(port.receipts, isNot(contains(41)));
    await tester.tap(find.text('有新消息 · 回到最新'));
    await tester.pumpAndSettle();
    expect(scrollOf(tester).position.extentAfter, lessThan(1));
    expect(port.receipts, contains(41));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning to retained conversation restores history position', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page(
        List.generate(40, (i) => i + 1),
        latest: 40,
        unread: 0,
        older: false,
      );
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model);
    await tester.drag(find.byType(ListView).last, const Offset(0, 700));
    await tester.pumpAndSettle();
    final before = scrollOf(tester).offset;
    await tester.pumpWidget(const SizedBox());
    await showChat(tester, port, controller: model);
    expect(scrollOf(tester).offset, closeTo(before, 1));
    expect(find.text('回到最新'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wheel scroll pauses following and new arrivals stay unread', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page(
        List.generate(40, (i) => i + 1),
        latest: 40,
        unread: 0,
        older: false,
      );
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView).last),
        scrollDelta: const Offset(0, -600),
      ),
    );
    await tester.pumpAndSettle();
    final before = scrollOf(tester).offset;
    expect(scrollOf(tester).position.extentAfter, greaterThan(500));
    port.receipts.clear();
    port.next = page([41], latest: 41, unread: 1, older: false);
    await model.refresh(silent: true);
    await tester.pumpAndSettle();
    expect(scrollOf(tester).offset, closeTo(before, 1));
    expect(port.receipts, isNot(contains(41)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restores a wrapping row anchor after returning at a new width', (
    tester,
  ) async {
    final port = FakeChat()..next = variedPage(1, 40);
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model);
    await tester.drag(find.byType(ListView).last, const Offset(0, 1300));
    await tester.pumpAndSettle();
    final anchor = model.viewport!.anchorSequence!;
    final before = tester.getTopLeft(message(anchor)).dy;
    await tester.pumpWidget(const SizedBox());
    port.receipts.clear();
    await showChat(tester, port, controller: model, width: 540);
    expect(tester.getTopLeft(message(anchor)).dy, closeTo(before, 1));
    expect(port.receipts, isNot(contains(40)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prepending variable height history retains the visible anchor', (
    tester,
  ) async {
    final port = FakeChat()..next = variedPage(21, 40, older: true);
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model, width: 540);
    scrollOf(tester).jumpTo(50);
    await tester.pumpAndSettle();
    final anchor = model.viewport!.anchorSequence!;
    final before = tester.getTopLeft(message(anchor)).dy;
    // Preserve the older action's height to isolate insertion anchoring.
    port.next = variedPage(1, 20, older: true);
    await tester.tap(find.text('查看更早消息'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(message(anchor)).dy, closeTo(before, 1));
    expect(model.messages, hasLength(40));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offscreen arrivals do not mark latest read on history return', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page(
        List.generate(40, (i) => i + 1),
        latest: 40,
        unread: 0,
        older: false,
      );
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await showChat(tester, port, controller: model);
    await tester.drag(find.byType(ListView).last, const Offset(0, 700));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    port.receipts.clear();
    port.next = page([41, 42], latest: 42, unread: 2, older: false);
    await model.refresh(silent: true);
    await showChat(tester, port, controller: model);
    expect(find.text('有新消息 · 回到最新'), findsOneWidget);
    expect(port.receipts.where((seq) => seq > 40), isEmpty);
    model.invalidate();
    await tester.pumpAndSettle();
    expect(model.viewport, isNull);
    expect(model.messages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(
      model.viewport,
      isNull,
      reason: 'Unmount cannot restore revoked state',
    );
  });
}
