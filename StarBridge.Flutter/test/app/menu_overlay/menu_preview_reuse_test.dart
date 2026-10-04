import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_previews.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'menu_organization_renewal_test.dart' show RenewingPort;
import 'menu_organization_body_stability_test.dart' show ready;

class SlowPreviewPort extends RenewingPort implements CommunityChatPreviewPort {
  int previewReads = 0;
  @override
  Future<CommunityChatPage> readChatPreview(String targetRef) async {
    previewReads++;
    throw const CommunityFailure('unavailable');
  }
}

class PendingPreviewPort extends RenewingPort implements CommunityChatPreviewPort {
  final pending = Completer<CommunityChatPage>();
  @override
  Future<CommunityChatPage> readChatPreview(String targetRef) => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful chat supplies sidebar even when optional preview fails',
    () async {
      final port = SlowPreviewPort();
      final session = MenuOrganizationsSession(port, (_) {});
      addTearDown(session.dispose);
      session.show(true);
      await ready(session, 'chat');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final organization = session.currentView['organization'] as Map;
      final navigation = organization['navigation'] as List;
      final message = (await port.readChat(port.card.targetRef)).messages.last;
      expect(
        (navigation.single as Map)['summary'],
        contains(message.text.replaceAll(RegExp(r'\s+'), ' ')),
      );
      expect((navigation.single as Map)['summary'], isNot(contains('无法读取')));
      expect(port.previewReads, 0, reason: 'Do not duplicate a successful chat read');
    },
  );

  test('late preview cannot overwrite newer chat and reset removes summary', () async {
    final port = PendingPreviewPort();
    final previews = MenuOrganizationPreviews(port, (_, _) {});
    addTearDown(previews.dispose);
    addTearDown(port.close);
    final target = port.card.targetRef;
    previews.refresh([target]);
    final page = await port.readChat(target);
    previews.observe(target, page.messages, page.unreadCount);
    final expected = previews.value(target);
    port.pending.completeError(const CommunityFailure('unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(previews.value(target), expected);
    previews.clear();
    expect(previews.value(target)['summary'], '正在读取聊天摘要');
  });
}
