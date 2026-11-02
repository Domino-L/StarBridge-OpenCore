import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_ports.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';

import 'social_window_test.dart' as fixture;

class FailingPort extends fixture.Port {
  String? failure;
  @override
  Future<List<Conversation>> directory() => failure == null
      ? super.directory()
      : Future.error(DirectReadFailure(failure!));
}

void main() {
  testWidgets(
    'typed forbidden survives primary RPC and withdraws child rows and draft',
    (t) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'show' ? true : null,
      );
      final port = FailingPort(), inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
      );
      await binding.open();
      final child = WindowMessagesPort(
        (op, args) => fixture.native(channel.name, 'rpc', {
          ...args,
          'op': op,
          'opening': binding.snapshot['opening'],
          'scope': binding.scope,
        }),
        () => {'supportsSending': true},
      );
      final module = DirectMessagesModule(child);
      await module.refresh();
      module.editDraft('fixture draft');
      expect(module.rows, isNotEmpty);
      port.failure = 'forbidden';
      await module.receive();
      final error = module.error, rows = module.rows, draft = module.draft;
      module.dispose();
      binding.dispose();
      inbox.dispose();
      await t.pump();
      messenger.setMockMethodCallHandler(channel, null);
      expect(error, 'forbidden');
      expect(rows, isEmpty);
      expect(draft, isEmpty);
    },
  );
}
