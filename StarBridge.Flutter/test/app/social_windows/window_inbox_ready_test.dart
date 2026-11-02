import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';

import 'social_window_test.dart' as social;

// DL-138 (2026-10-21, "the notifications window stalls on open"): the window
// started empty and waited for the primary's refresh(reuseFresh). The primary
// treats its inbox as fresh for 15 s but reads it every 60 s, so nearly every
// opening waited for a full account + inbox read although the primary already
// held a ready list. Automatic window refreshes now show that list at once.

final class _Inbox extends NotificationInboxController {
  _Inbox() : super(null) {
    items = [
      InboxItem(
        'a' * 32,
        'room',
        'normal',
        'Room invitation',
        'Join us',
        DateTime.utc(2026, 10, 21),
        false,
        '/rooms',
        'Open',
        true,
      ),
    ];
    ready = true;
  }
  Completer<bool>? pending;
  final requests = <bool>[];
  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) {
    requests.add(reuseFresh);
    return (pending = Completer<bool>()).future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SocialWindowBinding, _Inbox, social.Port)> open() async {
    const channel = MethodChannel('starbridge/notifications-primary');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'show',
        );
    final port = social.Port(), inbox = _Inbox();
    final binding = SocialWindowBinding(
      kind: 'notifications',
      messages: port,
      inbox: inbox,
      navigate: (_) async {},
      channel: channel,
    );
    expect(await binding.open(), isTrue);
    addTearDown(() async {
      binding.dispose();
      inbox.dispose();
      await port.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    return (binding, inbox, port);
  }

  Future<Object?> rpc(SocialWindowBinding binding, bool reuseFresh) =>
      social.native('starbridge/notifications-primary', 'rpc', {
        'opening': 1,
        'scope': binding.scope,
        'op': 'refresh',
        'reuseFresh': reuseFresh,
      });

  test('an opening window shows the ready inbox without waiting', () async {
    final (binding, inbox, _) = await open();
    final reply = rpc(binding, true);
    final answer = await reply.timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail(
        'The window waits for a full inbox read although the '
        'primary already holds a ready list.',
      ),
    ) as Map;
    expect((answer['items'] as List), hasLength(1));
    expect(answer['ready'], isTrue);
    // The primary still refreshes behind the shown list.
    expect(inbox.requests, [true]);
    inbox.pending!.complete(true);
  });

  test('an explicit window refresh still waits for the new list', () async {
    final (binding, inbox, _) = await open();
    var answered = false;
    final reply = rpc(binding, false).whenComplete(() => answered = true);
    await pumpEventQueue();
    expect(answered, isFalse);
    expect(inbox.requests, [false]);
    inbox.pending!.complete(true);
    expect(((await reply) as Map)['items'], hasLength(1));
  });
}
