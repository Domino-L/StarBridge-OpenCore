import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

const owner = '00000000000000000000000000000002';
const member = '00000000000000000000000000000001';
void main() {
  late ExampleCommunities port;
  var sequence = 0;
  CommunityChatSendIntent intent({
    String target = owner,
    String text = '示例发送',
    Map<String, Object?>? attachment,
    String? request,
  }) => CommunityChatSendIntent(
    targetRef: target,
    text: text,
    attachment: attachment,
    requestId: request ?? (++sequence).toRadixString(16).padLeft(32, '0'),
  );
  setUp(() {
    port = ExampleCommunities();
    sequence = 0;
  });
  tearDown(() => port.close());

  test(
    'example timeline pages history without reading messages implicitly',
    () async {
      final first = await port.readChat(owner);
      expect(first.messages, hasLength(50));
      expect(first.hasOlder, isTrue);
      expect(first.unreadCount, greaterThan(0));
      final older = await port.readChat(owner, before: first.oldestSequence);
      expect(older.messages, hasLength(6));
      expect(older.hasOlder, isFalse);
      final refs = [
        ...older.messages,
        ...first.messages,
      ].map((m) => m.messageRef);
      expect(refs.toSet(), hasLength(56));
      expect((await port.readChat(owner)).unreadCount, first.unreadCount);
    },
  );
  test('only an actual message of this organization advances monotonic read cursor', () async {
    final own = await port.readChat(owner);
    final foreign = await port.readChat(member);
    expect(
      (await port.markChatRead(owner, foreign.messages.last)).status,
      'rejected',
    );
    expect(
      (await port.markChatRead(owner, own.messages.last)).readThrough,
      own.latestSequence,
    );
    expect(
      (await port.markChatRead(owner, own.messages.first)).readThrough,
      own.latestSequence,
    );
    expect((await port.readChat(owner)).unreadCount, 0);
    expect((await port.readChat(member)).unreadCount, foreign.unreadCount);
  });
  test(
    'send is self aligned scoped and idempotent with fixed intent',
    () async {
      final other = await port.readChat(member);
      final write = intent(text: '一条消息');
      final results = await Future.wait([
        port.sendChat(write),
        port.sendChat(write),
      ]);
      expect(results.map((r) => r.sequence).toSet(), hasLength(1));
      final next = await port.readChat(owner, after: 56);
      expect(next.messages, hasLength(1));
      expect(next.messages.single.isSelf, isTrue);
      expect(next.messages.single.localRequestId, write.requestId);
      expect(next.messages.single.text, '一条消息');
      expect(
        (await port.sendChat(intent(text: '不同', request: write.requestId)))
            .error,
        'intentConflict',
      );
      expect(
        (await port.readChat(member)).latestSequence,
        other.latestSequence,
      );
    },
  );
  test(
    'preset sharing resolves the original detail and imports additively',
    () async {
      final catalog = await port.readCommunityPresets();
      final attachment = await port.exportCommunityPreset(
        catalog.presets.single.id,
        catalog.revision,
      );
      await port.sendChat(intent(text: '', attachment: attachment));
      final message = (await port.readChat(owner, after: 56)).messages.single;
      expect(message.hasAttachment, isTrue);
      final detail = await assembleCommunityChatDetail(
        port,
        owner,
        message.messageRef,
        checkCurrent: () {},
      );
      expect(detail.attachment, attachment);
      final name = await port.importCommunityPreset(
        detail.attachment!,
        catalog.revision,
      );
      final next = await port.readCommunityPresets();
      expect(next.presets, hasLength(2));
      expect(next.presets.first.name, catalog.presets.first.name);
      expect(next.presets.last.name, name);
      await expectLater(
        port.importCommunityPreset(attachment, catalog.revision),
        throwsA(isA<CommunityFailure>()),
      );
      final imported = await port.exportCommunityPreset(
        next.presets.last.id,
        next.revision,
      );
      expect(
        (jsonDecode(imported['overlayPresetPackage'] as String) as Map)['Name'],
        name,
      );
    },
  );
  test('foreign detail and malformed cursors are refused', () async {
    final message = (await port.readChat(owner)).messages.last;
    await expectLater(
      port.readChatDetail(member, message.messageRef, 0, null),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      port.readChat(owner, after: 1, before: 3),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      port.readChatDetail(owner, message.messageRef, 1, null),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(
      port.readChatDetail(owner, message.messageRef, 0, 'bad'),
      throwsA(isA<CommunityFailure>()),
    );
  });
  test(
    'leaving organization revokes reads details receipts and sending',
    () async {
      final message = (await port.readChat(owner)).messages.last;
      final write = intent();
      await port.sendChat(write);
      await port.execute('leave', owner);
      await expectLater(port.readChat(owner), throwsA(isA<CommunityFailure>()));
      await expectLater(
        port.readChatDetail(owner, message.messageRef, 0, null),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        port.markChatRead(owner, message),
        throwsA(isA<CommunityFailure>()),
      );
      expect((await port.sendChat(write)).error, 'notAllowed');
      expect((await port.readChat(member)).messages, isNotEmpty);
    },
  );
  test(
    'closing example clears chat controller and isolated preset changes',
    () async {
      final model = CommunityChatController(port, owner);
      addTearDown(model.dispose);
      await model.refresh();
      model.updateDraft('未保存');
      await port.close();
      expect(model.invalidated, isTrue);
      expect(model.messages, isEmpty);
      expect(model.draft, isEmpty);
      expect(port.chatAvailable, isFalse);
      await expectLater(
        port.readCommunityPresets(),
        throwsA(isA<CommunityFailure>()),
      );
      final next = ExampleCommunities();
      addTearDown(next.close);
      expect((await next.readCommunityPresets()).presets, hasLength(1));
      expect((await next.readChat(owner)).latestSequence, 56);
    },
  );
  test('new organization has empty chat and sends first message', () async {
    final created = await port.createCommunity('create', {
      'code': 'EMPTY',
      'name': '新组织',
      'description': '',
      'tagIds': <String>[],
      'activeSystemIds': <String>[],
      'activeFrom': '18:00',
      'activeTo': '20:00',
      'timeZoneId': 'UTC',
      'joinPolicy': 'Open',
    });
    final target = created.organization!.targetRef;
    final page = await port.readChat(target);
    expect(page.messages, isEmpty);
    expect(page.latestSequence, 0);
    expect((await port.sendChat(intent(target: target))).sequence, 1);
    expect((await port.readChat(target)).messages.single.isSelf, isTrue);
  });
}
