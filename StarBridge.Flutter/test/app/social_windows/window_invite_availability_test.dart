import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';

import 'social_window_test.dart' show Port, native, row;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'the messages window invitation entry follows the account after it opened',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'show' ? true : null,
      );
      final available = ValueNotifier(true);
      var sent = 0;
      final port = Port(), inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
        sendInvite: (_) async => sent++,
        sendInviteAvailable: () => available.value,
        sendInviteChanges: available,
      );
      try {
        await binding.open(target: row);
        bool shown() =>
            (jsonDecode(binding.snapshot['view'] as String)
                as Map)['sendInvite'] ==
            true;
        expect(shown(), isTrue);
        available.value = false;
        expect(shown(), isFalse);
        await expectLater(
          native(channel.name, 'rpc', {
            'opening': binding.snapshot['opening'],
            'scope': binding.scope,
            'op': 'sendInvite',
            'ref': row.ref,
          }),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'window.invalid',
            ),
          ),
        );
        expect(
          sent,
          0,
          reason: 'a hidden entry cannot be used from the window',
        );
        available.value = true;
        expect(shown(), isTrue);
      } finally {
        binding.dispose();
        inbox.dispose();
        available.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
