import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';

import 'community_chat_media_cache_test.dart' show MediaPort, message;
import '../overlay_settings/overlay_acceptance_polish_test.dart' show polishApp;

void main() {
  test('media first requested after revocation cannot start a read', () async {
    final port = MediaPort();
    final controller = CommunityChatController(port, 'a' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    controller.invalidate();
    await expectLater(controller.media().load(message(1, attachment: true)), throwsStateError);
    expect(port.calls, isEmpty);
  });
  test('renewed authorization reference cannot reuse the old media owner', () async {
    final port = MediaPort();
    final controller = CommunityChatController(port, 'a' * 32);
    addTearDown(controller.dispose);
    addTearDown(port.changes.close);
    final previous = controller.media();
    final item = message(1, attachment: true, hasAvatar: false);
    await previous.load(item);
    controller.renewVerifiedReference('b' * 32);
    expect(previous.peek(item), isNull);
    await expectLater(previous.load(item), throwsStateError);
    expect(controller.media(), isNot(same(previous)));
    controller.invalidate();
    await expectLater(controller.media().load(item), throwsStateError);
  });
  testWidgets(
    'returning to retained conversation keeps loaded attachment without a spinner',
    (tester) async {
      final port = MediaPort();
      final controller = CommunityChatController(port, 'a' * 32);
      addTearDown(controller.dispose);
      addTearDown(port.changes.close);
      Widget panel() => polishApp(
        CommunityChatPanel(
          port: port,
          targetRef: 'a' * 32,
          name: 'Fixture',
          onBack: () {},
          controller: controller,
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      final first = tester
          .state<CommunityChatPanelState>(find.byType(CommunityChatPanel))
          .media;
      final attachment = message(1, attachment: true, hasAvatar: false);
      await first.load(attachment);
      final reads = port.calls.length;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(panel());
      await tester.pumpAndSettle();
      final second = tester
          .state<CommunityChatPanelState>(find.byType(CommunityChatPanel))
          .media;
      expect(
        second,
        same(first),
        reason: 'Page navigation must not discard authorized attachment cache',
      );
      await tester.pumpWidget(
        polishApp(
          CommunityChatMessageTile(
            port: port,
            targetRef: 'a' * 32,
            message: attachment,
            mediaCache: second,
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(port.calls.length, reads);
      port.changes.add(null);
      await tester.pump();
      expect(find.text(attachment.messageRef), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
