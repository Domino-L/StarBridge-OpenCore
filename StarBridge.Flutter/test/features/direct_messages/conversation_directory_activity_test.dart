import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';

import 'direct_message_live_delivery_test.dart' show IncomingPort;

class DirectoryActivityPort extends IncomingPort {
  Completer<List<Conversation>>? pendingDirectory;
  bool directoryFails = false;
  String? peerAvatar;
  String? peerKey;
  String? peerPresence;
  @override
  Future<List<Conversation>> directory() async {
    if (directoryFails) throw const DirectReadFailure('unavailable');
    if (pendingDirectory != null) return pendingDirectory!.future;
    return [
      Conversation(
        'peer',
        'Peer',
        arrived ? 'Incoming fixture' : '',
        time,
        arrived ? 1 : 0,
        'friend',
        avatar: peerAvatar,
        conversationKey: peerKey,
        presence: peerPresence,
      ),
      if (arrived)
        Conversation('other', 'Other', 'Other incoming', time, 2, 'friend'),
    ];
  }
}

void main() {
  test('directory refresh updates presence and failure clears status without false offline', () async {
    final port = DirectoryActivityPort()..peerPresence = 'online';
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await module.open(module.rows.single);
    module.editDraft('keep');
    port.peerPresence = 'away';
    await module.receive();
    expect(module.selected!.presence, 'away');
    port.directoryFails = true;
    await module.receive();
    expect(module.rows.single.presence, isNull);
    expect(module.selected!.presence, isNull);
    expect(module.draft, 'keep');
    port.directoryFails = false;
    port.peerPresence = 'offline';
    await module.receive();
    expect(module.selected!.presence, 'offline');
  });
  test(
    'profile refresh does not match another scope by display name',
    () async {
      final port = DirectoryActivityPort()
        ..peerAvatar = 'unrelated-avatar'
        ..peerKey = 'other-scoped-key';
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(
        Conversation(
          'friend-card-ref',
          'Peer',
          '',
          port.time,
          0,
          'friend',
          avatar: 'original-avatar',
          conversationKey: 'scoped-peer-key',
        ),
      );
      await module.receive(directoryOnly: true);
      expect(module.selected!.avatar, 'original-avatar');
      expect(module.selected!.ref, 'friend-card-ref');
    },
  );
  test(
    'friend handoff refreshes peer profile across distinct scoped references',
    () async {
      final port = DirectoryActivityPort()
        ..peerAvatar = 'new-avatar-fixture'
        ..peerKey = 'scoped-peer-key';
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(
        Conversation(
          'friend-card-ref',
          'Old name',
          '',
          port.time,
          0,
          'friend',
          avatar: 'old-avatar-fixture',
          conversationKey: 'scoped-peer-key',
        ),
      );
      module.editDraft('keep handoff draft');
      module.scrollOffset = 91;
      await module.receive(directoryOnly: true);
      expect(module.rows.single.avatar, 'new-avatar-fixture');
      expect(module.selected!.avatar, 'new-avatar-fixture');
      expect(module.selected!.name, 'Peer');
      expect(
        module.selected!.ref,
        'friend-card-ref',
        reason: 'retain the history/paging capability',
      );
      expect(module.draft, 'keep handoff draft');
      expect(module.scrollOffset, 91);
    },
  );
  test(
    'peer avatar-only activity updates selected chat without a new message',
    () async {
      final port = DirectoryActivityPort()..peerAvatar = 'old-avatar-fixture';
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.single);
      module.editDraft('keep draft');
      module.scrollOffset = 91;
      port.peerAvatar = 'new-avatar-fixture';
      port.activity.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(module.selected!.avatar, 'new-avatar-fixture');
      expect(module.rows.single.avatar, 'new-avatar-fixture');
      expect(module.rows.single.unread, 0);
      expect(module.messages, isEmpty);
      expect(module.draft, 'keep draft');
      expect(module.scrollOffset, 91);
    },
  );
  test('late directory cannot restore departed conversation or overwrite new scope', () async {
    final port = DirectoryActivityPort();
    final module = DirectMessagesModule(port);
    addTearDown(module.dispose);
    await module.openFriend(port.peer);
    port.pendingDirectory = Completer<List<Conversation>>();
    final receiving = module.receive();
    module.back();
    port.pendingDirectory!.complete([
      Conversation('late', 'Late', '', port.time, 99, 'friend'),
    ]);
    await receiving;
    expect(module.selected, isNull);
    expect(module.rows.any((row) => row.ref == 'late'), isFalse);
  });
  test(
    'directory failure retains rows but does not block incoming history',
    () async {
      final port = DirectoryActivityPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.openFriend(port.peer);
      port.directoryFails = true;
      port.arrived = true;
      await module.receive();
      expect(module.messages.single.text, 'Incoming fixture');
      expect(module.rows.single.ref, 'peer');
      expect(module.error, isNull);
    },
  );
  test(
    'selected history and all directory unread rows advance on one activity',
    () async {
      final port = DirectoryActivityPort();
      final module = DirectMessagesModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await module.open(module.rows.single);
      module.editDraft('keep draft');
      module.scrollOffset = 127;
      port.arrived = true;
      port.activity.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(module.rows.map((r) => r.ref), ['peer', 'other']);
      expect(module.rows.map((r) => r.unread), [1, 2]);
      expect(module.rows.first.preview, 'Incoming fixture');
      expect(module.selected!.unread, 1);
      expect(module.messages.single.text, 'Incoming fixture');
      expect(module.draft, 'keep draft');
      expect(module.scrollOffset, 127);
      expect(module.busy, isFalse);
    },
  );
}
