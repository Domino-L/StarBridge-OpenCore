import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_frame.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_codec.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, capture;

final row = Conversation(
  'fixture-ref',
  '测试好友',
  '测试内容',
  DateTime(2026),
  1,
  'friend',
  conversationKey: 'fixture-key',
);

class Port
    implements DirectMessagesPort, DirectMessageSender, DirectReadReceiptPort {
  final events = StreamController<void>.broadcast(sync: true);
  int sends = 0, reads = 0;
  Completer<List<Conversation>>? pending;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() async =>
      pending == null ? [row] : pending!.future;
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => DirectPage(ref, [], 0, 0, false, 'friend', canSend: true);
  @override
  bool get supportsSending => true;
  @override
  bool get supportsReadReceipts => true;
  @override
  Future<DirectSendResult> send(String ref, String text, String id) async {
    sends++;
    return const DirectSendResult('unknown');
  }

  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    reads++;
    return DirectReadReceipt(through, 0);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

const codec = StandardMethodCodec();
Future<Object?> native(String channel, String method, Object? args) {
  final done = Completer<Object?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel,
        codec.encodeMethodCall(MethodCall(method, args)),
        (data) {
          try {
            done.complete(data == null ? null : codec.decodeEnvelope(data));
          } catch (e, s) {
            done.completeError(e, s);
          }
        },
      );
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  testWidgets(
    'authority rejects hidden, old-account and malformed sends; no automatic resend',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'show' ? true : null,
      );
      final port = Port(), inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
      );
      await binding.open();
      Map<String, Object?> args(String op) => {
        'opening': binding.snapshot['opening'],
        'scope': binding.scope,
        'op': op,
      };
      final send = {
        ...args('send'),
        'ref': row.ref,
        'text': 'fixture',
        'id': 'a' * 32,
      };
      final result = await native(channel.name, 'rpc', send) as Map;
      expect(result['status'], 'unknown');
      expect(port.sends, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(port.sends, 1);
      await native(channel.name, 'hidden', {
        'opening': binding.snapshot['opening'],
      });
      await expectLater(
        native(channel.name, 'rpc', send),
        throwsA(isA<PlatformException>()),
      );
      await binding.open();
      await expectLater(
        native(channel.name, 'rpc', send),
        throwsA(isA<PlatformException>()),
      );
      final old = args('directory');
      binding.invalidate();
      await expectLater(
        native(channel.name, 'rpc', old),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        native(channel.name, 'rpc', {
          ...args('send'),
          'ref': row.ref,
          'text': 'x' * 1001,
          'id': 'a' * 32,
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(port.sends, 1);
      binding.dispose();
      inbox.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets(
    'late result after account invalidation is rejected; focused conversation is scoped',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'show' ? true : null,
      );
      final port = Port(), inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
      );
      await binding.open(target: row);
      final args = {
        'opening': binding.snapshot['opening'],
        'scope': binding.scope,
      };
      await native(channel.name, 'rpc', {
        ...args,
        'op': 'viewport',
        'ref': row.ref,
      });
      expect(binding.visibleConversationKey, null);
      await native(channel.name, 'viewportActive', {...args, 'active': true});
      expect(binding.visibleConversationKey, 'fixture-key');
      port.pending = Completer();
      final pending = native(channel.name, 'rpc', {...args, 'op': 'directory'});
      await tester.pump();
      final assertion = expectLater(pending, throwsA(isA<PlatformException>()));
      binding.invalidate();
      port.pending!.complete([row]);
      await assertion;
      expect(binding.visibleConversationKey, null);
      binding.dispose();
      inbox.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  for (final kind in ['messages', 'notifications']) {
    testWidgets(
      '$kind shares approved frame and retains content across hide/reopen',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = Size(kind == 'messages' ? 920 : 560, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final channel = MethodChannel('starbridge/$kind-surface');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <MethodCall>[];
        Map snapshot(int opening) => {
          'opening': opening,
          'revision': opening,
          'view': jsonEncode({
            'scope': 'fixture',
            'targetVersion': 1,
            'supportsSending': true,
            'supportsRead': true,
            if (kind == 'messages') 'target': encodeConversation(row),
          }),
        };
        messenger.setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          if (c.method == 'ready') return snapshot(1);
          if (c.method == 'rpc') {
            final a = c.arguments as Map;
            if (a['op'] == 'history') {
              return {
                'ref': row.ref,
                'messages': [
                  if (a['after'] == 0)
                    encodeMessage(
                      DirectMessage(
                        1,
                        'fixture-message',
                        true,
                        '准备好一起出发了吗？',
                        DateTime(2026),
                        null,
                      ),
                    ),
                ],
                'oldest': 1,
                'latest': 1,
                'hasOlder': false,
                'state': 'friend',
                'canSend': true,
              };
            }
            if (a['op'] == 'directory') return [encodeConversation(row)];
            if (a['op'] == 'refresh') {
              return {
                'items': [
                  encodeInbox(
                    InboxItem(
                      'a' * 32,
                      'room',
                      'action_required',
                      '收到房间邀请',
                      '好友邀请你加入行动房间。',
                      DateTime(2026),
                      false,
                      'room_invitations',
                      '查看邀请',
                      true,
                    ),
                  ),
                ],
                'ready': true,
                'error': null,
              };
            }
            if (a['op'] == 'markRead') return {'through': 1, 'unread': 0};
            return true;
          }
          return null;
        });
        final shot = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: SocialWindowApp(kind: kind),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          calls.where(
            (c) =>
                c.method == 'rpc' && (c.arguments as Map)['op'] == 'markRead',
          ),
          isEmpty,
        );
        await native(channel.name, 'viewportActive', true);
        await tester.pumpAndSettle();
        expect(find.byType(SocialWindowFrame), findsOneWidget);
        await capture(tester, shot, '$kind-detached');
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.backgroundColor,
          FutureRestraintStyle.resolve(AppearanceMode.dark)
              .surfaces
              .raised
              .fill,
        );
        if (kind == 'messages') {
          final page = tester.widget<DirectMessagesPage>(
            find.byType(DirectMessagesPage),
          );
          page.sharedModule!.editDraft('保留草稿');
          page.sharedModule!.scrollOffset = 21;
          await tester.pump();
          await native(channel.name, 'viewportActive', false);
          await native(channel.name, 'snapshot', snapshot(2));
          await tester.pump();
          final reopened = tester.widget<DirectMessagesPage>(
            find.byType(DirectMessagesPage),
          );
          expect(identical(page.sharedModule, reopened.sharedModule), true);
          expect(reopened.sharedModule!.draft, '保留草稿');
        } else {
          expect(find.byType(NotificationInboxPage), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
          expect(
            calls.where(
              (c) =>
                  c.method == 'rpc' && (c.arguments as Map)['op'] == 'markRead',
            ),
            isNotEmpty,
          );
          final reads = calls
              .where(
                (c) =>
                    c.method == 'rpc' &&
                    (c.arguments as Map)['op'] == 'markRead',
              )
              .length;
          await native(channel.name, 'viewportActive', false);
          await tester.pump(const Duration(seconds: 2));
          expect(
            calls
                .where(
                  (c) =>
                      c.method == 'rpc' &&
                      (c.arguments as Map)['op'] == 'markRead',
                )
                .length,
            reads,
          );
        }
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        messenger.setMockMethodCallHandler(channel, null);
      },
    );
  }
}
