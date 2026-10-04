import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';

import 'menu_organization_renewal_test.dart' show RenewingPort;
import 'menu_organization_body_stability_test.dart' show ready;
import '../../features/communities/community_chat_test.dart' show chatPage;

class SendingRenewalPort extends RenewingPort implements CommunityChatSendPort {
  final sent = <CommunityChatSendIntent>[];
  bool confirm = false;
  @override
  bool get chatSendAvailable => true;
  @override
  Future<CommunityChatSendOutcome> sendChat(
    CommunityChatSendIntent intent,
  ) async {
    sent.add(intent);
    renewal++;
    return const CommunityChatSendOutcome('unknown');
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    if (confirm) {
      final raw = chatPage();
      return CommunityChatPage.parse({
        ...raw,
        'targetRef': targetRef,
        'latestSequence': 21,
        'oldestSequence': 21,
        'hasOlder': false,
        'messages': [
          <String, Object?>{
            ...((raw['messages'] as List).last as Map<String, Object?>),
            'sequence': 21,
            'messageRef': '9' * 32,
            'localRequestId': sent.single.requestId,
          },
        ],
      });
    }
    return super.readChat(targetRef, after: after, before: before);
  }
}

class HistoryRenewalPort extends RenewingPort {
  @override
  bool get chatReadReceiptsAvailable => true;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    if (before > 0) {
      final raw = chatPage();
      return CommunityChatPage.parse({
        ...raw,
        'targetRef': targetRef,
        'oldestSequence': 5,
        'hasOlder': false,
        'messages': [
          <String, Object?>{
            ...(raw['messages'] as List).first as Map<String, Object?>,
            'sequence': 5,
            'messageRef': '8' * 32,
          },
        ],
      });
    }
    return super.readChat(targetRef, after: after, before: before);
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) async =>
      CommunityChatReadReceipt('accepted', readThrough: message.sequence);
}

class BusyRenewalPort extends HistoryRenewalPort {
  final cursors = <int>[];
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    cursors.add(after);
    if (renewal == 0) {
      return super.readChat(targetRef, after: after, before: before);
    }
    final sequence = after == 0 ? 100 : after + 1;
    final raw = chatPage();
    return CommunityChatPage.parse({
      ...raw,
      'targetRef': targetRef,
      'latestSequence': 100,
      'oldestSequence': sequence,
      'hasOlder': true,
      'messages': [
        <String, Object?>{
          ...(raw['messages'] as List).first as Map<String, Object?>,
          'sequence': sequence,
          'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
        },
      ],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reference renewal does not skip the gap before a busy latest page',
    () async {
      final port = BusyRenewalPort();
      final chat = CommunityChatController(port, port.card.targetRef);
      addTearDown(chat.dispose);
      addTearDown(port.close);
      await chat.refresh();
      port.renewal++;
      chat.renewVerifiedReference(port.card.targetRef);
      await chat.refresh();
      expect(chat.messages.map((m) => m.sequence), [10, 12, 13]);
      expect(chat.hasNewer, true);
      expect(port.cursors, [0, 0, 12]);
    },
  );
  test(
    'verified renewal keeps loaded older history and acknowledged watermark',
    () async {
      final port = HistoryRenewalPort();
      final chat = CommunityChatController(port, port.card.targetRef);
      addTearDown(chat.dispose);
      addTearDown(port.close);
      await chat.refresh();
      await chat.loadOlder();
      chat.setReadingContext(visible: true, foreground: true);
      await chat.acknowledgeVisible('b' * 32);
      expect(chat.confirmedReadThrough, 10);
      port.renewal++;
      chat.renewVerifiedReference(port.card.targetRef);
      await chat.refresh();
      expect(chat.messages.map((m) => m.sequence), [5, 10, 12]);
      expect(chat.hasOlder, false);
      expect(chat.confirmedReadThrough, 10);
    },
  );
  test(
    'old navigation key resolves current organization without resetting shell',
    () async {
      final port = RenewingPort();
      final session = MenuOrganizationsSession(port, (_) {});
      addTearDown(session.dispose);
      session.show(true);
      await ready(session, 'chat');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final original = MenuFeatureView.parse(session.currentView);
      final identity = (session.currentView['organization'] as Map)['identity'];
      final reads = port.calls.length;
      port.renewal++;
      await session.refresh(silent: true);
      session.act(original.organization!.navigation.single.key, '');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        (session.currentView['organization'] as Map)['identity'],
        identity,
      );
      expect(
        port.calls.length,
        reads,
        reason: 'Completed same-version avatars are not downloaded again',
      );
    },
  );
  test('menu reference renewal preserves unknown send until history confirms exact request', () async {
    final port = SendingRenewalPort();
    final session = MenuOrganizationsSession(port, (_) {});
    addTearDown(session.dispose);
    session.show(true);
    await ready(session, 'chat');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final view = MenuFeatureView.parse(session.currentView);
    session.act(
      view.buttons.singleWhere((b) => b.label == '发送消息').key,
      'fixture draft',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect((session.currentView['chat'] as Map)['status'], 'unknown');
    expect((session.currentView['chat'] as Map)['revision'], 0);
    expect(
      MenuFeatureView.parse(session.currentView).buttons
          .any((b) => b.label == '发送消息'),
      false,
    );
    port.confirm = true;
    await session.refresh(silent: true);
    expect((session.currentView['chat'] as Map)['status'], 'sent');
    expect((session.currentView['chat'] as Map)['revision'], 1);
    expect(port.sent, hasLength(1));
  });
}
