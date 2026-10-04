import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';

import '../friends/social_layout_test.dart' show app;
import 'conversation_directory_activity_test.dart' show DirectoryActivityPort;

void main() {
  testWidgets('reselecting the visible conversation by its scoped key keeps the draft', (tester) async {
    final port = DirectoryActivityPort()..peerKey = 'same-peer';
    final module = DirectMessagesModule(port);
    await module.openFriend(Conversation(
      'friend-card-ref', 'Peer', '', port.time, 0, 'friend',
      conversationKey: 'same-peer',
    ));
    await module.receive(directoryOnly: true);
    module.editDraft('保留的草稿');
    await tester.pumpWidget(app(DirectMessagesPage(
      createPort: () => port,
      sharedModule: module,
      onBack: () {},
    )));
    await tester.pumpAndSettle();
    expect(module.selected?.ref, 'friend-card-ref');
    expect(module.rows.single.ref, 'peer');
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    expect(find.text('放弃当前输入？'), findsNothing);
    expect(module.draft, '保留的草稿');
    expect(module.selected?.ref, 'friend-card-ref');
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });
  testWidgets(
    'new friend request reuses recent chats, keeps draft on cancel and rejects invalidated handoff',
    (tester) async {
      final port = ExampleDirectMessages();
      final rows = await port.directory();
      final module = DirectMessagesModule(port);
      Future<void> show(Conversation? initial) async {
        await tester.pumpWidget(
          app(
            DirectMessagesPage(
              createPort: () => port,
              sharedModule: module,
              initialConversation: initial,
              onBack: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(rows.first);
      expect(module.selected?.ref, rows.first.ref);
      module.editDraft('保留的草稿');
      await show(rows.last);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('留在会话'));
      await tester.pumpAndSettle();
      expect(module.selected?.ref, rows.first.ref);
      expect(module.draft, '保留的草稿');
      await show(null);
      await show(rows.last);
      expect(find.byType(AlertDialog), findsOneWidget);
      // An account invalidation clears the owning FriendsPage's pending target.
      await show(null);
      await tester.tap(find.text('放弃输入并离开'));
      await tester.pumpAndSettle();
      expect(module.selected?.ref, rows.first.ref);
      expect(module.draft, '保留的草稿');
      await show(rows.last);
      await tester.tap(find.text('放弃输入并离开'));
      await tester.pumpAndSettle();
      expect(module.selected?.ref, rows.last.ref);
      expect(module.draft, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
}
