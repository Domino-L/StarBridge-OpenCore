import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_conversation_snapshot.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

void main() {
  test(
    'menu rows retain order and bounded presentation without command refs',
    () {
      final time = DateTime.utc(2026, 1, 1);
      final rows = menuConversationRows(
        {
          'view-b': Conversation(
            'private-ref',
            'B\x00',
            'x' * 300,
            time,
            2,
            'request_incoming',
            conversationKey: 'private-key',
          ),
          'view-a': Conversation('other-ref', 'A' * 150, '', time, 0, 'friend'),
        },
        {'view-b': 'portrait'},
      );
      expect(rows.first, {
        'key': 'view-b',
        'name': 'B',
        'preview': 'x' * 256,
        'avatar': 'portrait',
        'time': time.toIso8601String(),
        'unread': 2,
        'request': true,
      });
      expect(rows.last['key'], 'view-a');
      expect(rows.last['name'], 'A' * 128);
      expect(rows.last['avatar'], isNull);
      expect(rows.last['request'], false);
      expect(menuConversationRows({}, {}), isEmpty);
    },
  );
}
