import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_composer.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;
import 'menu_comms_session_test.dart' show Port, peer, page;

MenuCommsView fixture({
  bool history = true,
  int count = 24,
  bool busy = false,
}) => MenuCommsView(
  'ready',
  rows: [
    for (var i = 0; i < 3; i++)
      (
        key: 'c${i + 1}',
        name: ['北辰', '白鸦', '回声'][i],
        time: DateTime(2026, 9, 23, 19, 40),
        unread: i == 1 ? 2 : 0,
        request: i == 2,
      ),
  ],
  previews: const {'c1': '我已经到奥里森了。', 'c2': '稍等，正在准备舰船。', 'c3': '你好，可以一起探索吗？'},
  name: history ? '北辰' : null,
  profileKey: history ? 'c1' : null,
  compose: history,
  canSend: true,
  busy: busy,
  conversationState: 'friend',
  hasOlder: true,
  messages: [
    for (var i = 0; i < count; i++)
      (
        incoming: i.isEven,
        text: i.isEven ? '第 $i 条消息：我已经到奥里森了，准备好后在机库集合。' : '第 $i 条消息：收到，正在准备舰船。',
        time: DateTime(2026, 9, 23, 19, i),
        attachment: false,
      ),
  ],
  receipts: {
    for (var i = 0; i < count; i++)
      if (i.isEven) i: 'r${i + 1}',
  },
);

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'master detail search unread and fixed composer; read only foreground',
    (tester) async {
      size(tester, const Size(1000, 760));
      final actions = <String>[], boundary = GlobalKey();
      Widget subject(bool active) => app(
        RepaintBoundary(
          key: boundary,
          child: MenuCommsPanel(
            view: fixture(),
            active: active,
            embedded: true,
            onClose: () {},
            onAction: (a, k) => actions.add('$a:$k'),
            onCompose: (_, _, _, _) {},
          ),
        ),
      );
      await tester.pumpWidget(subject(false));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
      final composer = find.byKey(const ValueKey('menu-message-draft'));
      final initial = tester.getRect(composer);
      await capture(tester, boundary, 'menu-comms-client-workspace');
      await tester.drag(
        find.byKey(const ValueKey('menu-message-history')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(composer), initial);
      await tester.pumpWidget(subject(true));
      await tester.pumpAndSettle();
      expect(actions.where((a) => a.startsWith('read:')), isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('menu-comms-group-unread')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-conversation-c1')), findsNothing);
      expect(
        find.byKey(const ValueKey('menu-conversation-c2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('menu-conversation-c2')));
      expect(actions.last, 'select:c2');
      await tester.enterText(
        find.byKey(const ValueKey('menu-comms-search')),
        '不存在',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-conversation-c2')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('minimum window and 200 percent text keep composer reachable', (
    tester,
  ) async {
    size(tester, const Size(320, 200));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MenuCommsPanel(
            view: fixture(count: 2),
            embedded: true,
            onClose: () {},
            onAction: (_, _) {},
            onCompose: (_, _, _, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('menu-message-send')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('new messages do not force a reader back to the bottom', (
    tester,
  ) async {
    size(tester, const Size(1000, 760));
    Widget subject(int count) => app(
      MenuCommsPanel(
        view: fixture(count: count),
        embedded: true,
        active: false,
        onClose: () {},
        onAction: (_, _) {},
        onCompose: (_, _, _, _) {},
      ),
    );
    await tester.pumpWidget(subject(24));
    await tester.pumpAndSettle();
    final history = find.byKey(const ValueKey('menu-message-history'));
    await tester.drag(history, const Offset(0, 350));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(history).controller!;
    expect(controller.offset, greaterThan(48));
    await tester.pumpWidget(subject(25));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(48));
    final latest = find.byKey(const ValueKey('menu-comms-new-messages'));
    expect(latest, findsOneWidget);
    await tester.tap(latest);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(latest, findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'desktop send shortcut excludes IME confirmation and Shift Enter',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        app(
          MenuCommsComposer(
            view: fixture(count: 0),
            onCompose: (a, _, _, _) => actions.add(a),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('menu-message-draft'));
      await tester.pumpAndSettle();
      await tester.enterText(field, '输入法确认');
      await tester.pump();
      final controller = tester.widget<TextField>(field).controller!;
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(actions.where((a) => a == 'send'), isEmpty);
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(actions.where((a) => a == 'send'), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(actions.where((a) => a == 'send'), hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(actions.where((a) => a == 'send'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'transport failure retains history and draft but revocation clears content',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuCommsSession(port, views.add)..show(true);
      MenuCommsView view() => MenuCommsView.parse(jsonEncode(views.last));
      port.directories.last.complete([peer('A'), peer('B')]);
      await tester.pump();
      final key = view().rows.first.key;
      session.act('select', key);
      port.histories.last.reply.complete(page('secret-A'));
      await tester.pump();
      session.compose('edit', key, '保留草稿', 1);
      expect(view().rows, hasLength(2));
      await tester.pump(const Duration(seconds: 10));
      port.histories.last.reply.completeError(
        const DirectReadFailure('unavailable'),
      );
      await tester.pump();
      expect(view().name, 'A');
      expect(view().messages, isNotEmpty);
      expect(view().draft, '保留草稿');
      expect(view().canSend, isFalse);
      expect(view().notice, isEmpty, reason: 'automatic retry is silent');
      session.act('retry', '');
      port.histories.last.reply.completeError(
        const DirectReadFailure('forbidden'),
      );
      await tester.pump();
      expect(view().state, 'restricted');
      expect(view().messages, isEmpty);
      expect(view().rows, isEmpty);
      session.dispose();
    },
  );
}
