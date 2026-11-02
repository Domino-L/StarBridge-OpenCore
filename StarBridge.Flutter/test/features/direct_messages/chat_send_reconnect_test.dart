import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_connection_notice.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_outgoing_bubble.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

import '../friends/friends_test.dart' as fixtures;

// User choice 2026-10-21 "A2+B1" (StarBridge-DesignPreviews/ChatSendAndReconnect).

Widget _app(Widget child, {bool reduceMotion = false}) {
  final base = fixtures.page(
    const Locale('zh', 'CN'),
    UnavailableFriendsPort.new,
  ) as MaterialApp;
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    theme: base.theme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('B1 connection notice', () {
    late DateTime clock;
    late bool? health;
    late int restored;
    ChatConnectionNotice notice() => ChatConnectionNotice(
      healthy: () => health,
      onRestored: () => restored++,
      now: () => clock,
    );
    setUp(() {
      clock = DateTime.utc(2026, 10, 21);
      health = true;
      restored = 0;
    });

    test('startup before the first healthy answer is not an interruption', () {
      health = false;
      final n = notice()..check();
      clock = clock.add(const Duration(seconds: 10));
      n.check();
      expect(n.phase, ChatConnectionPhase.connected);
      n.dispose();
    });

    test('jitter shorter than 3 seconds stays silent', () {
      final n = notice()..check();
      health = false;
      n.check();
      clock = clock.add(const Duration(milliseconds: 2900));
      n.check();
      expect(n.phase, ChatConnectionPhase.connected);
      health = true;
      n.check();
      expect(n.phase, ChatConnectionPhase.connected);
      expect(restored, 0);
      n.dispose();
    });

    testWidgets('an interruption over 3 seconds shows, then restored fades', (
      tester,
    ) async {
      final n = notice()..check();
      health = false;
      n.check();
      clock = clock.add(const Duration(seconds: 3));
      n.check();
      expect(n.phase, ChatConnectionPhase.reconnecting);
      await tester.pumpWidget(
        _app(Column(children: [ChatReconnectLine(n), ChatConnectionStatus(n)])),
      );
      await tester.pump();
      expect(find.text('正在重新连接…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      health = true;
      n.check();
      expect(restored, 1, reason: 'queued messages are released');
      await tester.pump();
      expect(find.text('已恢复'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(n.phase, ChatConnectionPhase.connected);
      expect(find.text('已恢复'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      n.dispose();
    });

    testWidgets('reduced motion keeps the line still', (tester) async {
      final n = notice()..check();
      health = false;
      n.check();
      clock = clock.add(const Duration(seconds: 4));
      n.check();
      await tester.pumpWidget(_app(ChatReconnectLine(n), reduceMotion: true));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('chat-reconnect-line')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      n.dispose();
    });

    test('no health source (gateway off, older Host) never shows', () {
      health = null;
      final n = notice()..check();
      clock = clock.add(const Duration(minutes: 5));
      n.check();
      expect(n.phase, ChatConnectionPhase.connected);
      n.dispose();
    });
  });

  group('A2 outgoing bubble', () {
    Future<DirectOutgoing> queued(DirectMessagesModule module) async {
      await module.refresh();
      await module.open(module.rows.first);
      module.editDraft('草稿内容');
      await module.send();
      return module.outgoing.single;
    }

    testWidgets('sending shows a clock in the time slot, bubble unchanged', (
      tester,
    ) async {
      final module = DirectMessagesModule(_silent());
      addTearDown(module.dispose);
      final message = await queued(module);
      var retries = 0;
      await tester.pumpWidget(
        _app(
          DirectOutgoingBubble(
            message: message,
            time: '12:00',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('草稿内容'), findsOneWidget);
      expect(
        find.byKey(ValueKey('chat-send-pending-${message.id}')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is StandardIcon && w.semantic == StandardIconSemantic.schedule,
        ),
        findsOneWidget,
      );
      expect(find.text('发送失败'), findsNothing);
      expect(retries, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('failed shows the alert and retry, keeping the text', (
      tester,
    ) async {
      final module = DirectMessagesModule(_rejecting());
      addTearDown(module.dispose);
      final message = await queued(module);
      await tester.pump();
      expect(message.state, DirectOutgoingState.failed);
      var retries = 0;
      await tester.pumpWidget(
        _app(
          DirectOutgoingBubble(
            message: message,
            time: '12:00',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('草稿内容'), findsOneWidget, reason: 'nothing is lost');
      expect(find.text('发送失败'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('chat-send-retry-${message.id}')));
      await tester.tap(find.byKey(ValueKey('chat-send-alert-${message.id}')));
      expect(retries, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('strings exist in every locale', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in const [
        'direct.send.pendingTip',
        'direct.send.failed',
        'direct.send.retry',
        'direct.send.failedTip',
        'direct.connection.reconnecting',
        'direct.connection.restored',
      ]) {
        expect(strings.text(key), isNot(key), reason: '$locale $key');
      }
    }
  });
}

/// Example reads with a controlled send answer.
class _Answering implements DirectMessagesPort, DirectMessageSender {
  _Answering(this.answer);
  final Future<DirectSendResult> Function() answer;
  final _base = ExampleDirectMessages();
  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(String ref, String text, String id) => answer();
  @override
  Stream<void> get invalidations => _base.invalidations;
  @override
  Future<List<Conversation>> directory() => _base.directory();
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) =>
      _base.history(ref, before: before, after: after);
  @override
  void cancel() => _base.cancel();
  @override
  Future<void> close() => _base.close();
}

/// Never answers: a message stays sending.
_Answering _silent() => _Answering(() => Future.any(const []));

_Answering _rejecting() => _Answering(
  () async => const DirectSendResult('rejected', error: 'rate_limited'),
);
