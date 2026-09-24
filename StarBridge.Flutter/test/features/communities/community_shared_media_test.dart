import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';

import 'community_chat_test.dart' show ChatDetailFake, chatPage;
import 'community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload, mediaChunk;
import 'community_workspace_view_test.dart' show host;
import 'community_ships_test.dart' show shipPage, shipRow;
import '../friends/social_layout_test.dart' show loadFonts;

class SharedMediaPort extends WorkspaceTestPort
    implements CommunityChatPort, CommunityShipsPort {
  SharedMediaPort() {
    reader = (target, query, offset) async {
      final payload = workspacePayload(target: target, query: query);
      final member = (payload['members'] as List).single as Map;
      member['memberRef'] = 'd' * 32;
      member['hasAvatar'] = true;
      member['avatarVersion'] = avatarVersion;
      return CommunityWorkspace.parse(payload);
    };
  }
  final chat = ChatDetailFake();
  int avatarReads = 0;
  String? heldMember;
  Completer<void>? mediaGate;
  String avatarVersion = 'a' * 64;
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async => CommunityShipsPage.parse({
    ...shipPage(),
    'targetRef': targetRef,
    'queryVersion': 2,
    'query': query?.toPayload(),
    'matchedCount': 1,
    'ships': [
      {
        ...shipRow(),
        'ownerAvatarVersion': avatarVersion,
        'hasCustomImage': false,
      },
    ],
  });
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => chat.markChatRead(targetRef, message);
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    final payload = chatPage();
    for (final row in payload['messages'] as List) {
      (row as Map)['hasAttachment'] = false;
      row['avatarVersion'] = avatarVersion;
    }
    return CommunityChatPage.parse(payload);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => chat.readChatDetail(targetRef, messageRef, offset, version);
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    avatarReads++;
    if (memberRef == heldMember) await mediaGate?.future;
    return mediaChunk(
      base64Decode(chat.avatar.split(',').last),
      offset,
      kind: kind,
      memberRef: memberRef,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  test(
    'slow first member avatar does not serialize the rest of the page',
    () async {
      final port = SharedMediaPort();
      addTearDown(port.changes.close);
      port.reader = (target, query, offset) async {
        final payload = workspacePayload(target: target);
        final source = (payload['members'] as List).single as Map;
        return CommunityWorkspace.parse({
          ...payload,
          'totalCount': 3,
          'matchedCount': 3,
          'members': [
            for (final id in ['b', 'c', 'd'])
              {...source, 'hasAvatar': true, 'memberRef': id * 32},
          ],
        });
      };
      port.heldMember = 'b' * 32;
      port.mediaGate = Completer<void>();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      final read = model.load();
      await Future<void>.delayed(Duration.zero);
      expect(model.image('b' * 32), isNull);
      expect(model.image('c' * 32), isNotNull);
      expect(model.image('d' * 32), isNotNull);
      port.mediaGate!.complete();
      await read;
      expect(model.image('b' * 32), isNotNull);
    },
  );
  testWidgets('member roster, online members and chat reuse one avatar read', (
    tester,
  ) async {
    final port = SharedMediaPort();
    addTearDown(port.changes.close);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(port.avatarReads, 3);
    await tester.tap(find.byKey(const ValueKey('community-section-chat')));
    await tester.pumpAndSettle();
    expect(
      port.avatarReads + port.chat.reads,
      3,
      reason:
          'Authorized member avatar must be shared by all organization views.',
    );
    await tester.tap(find.byKey(const ValueKey('community-section-ships')));
    await tester.pumpAndSettle();
    expect(
      port.avatarReads + port.chat.reads,
      3,
      reason: 'Ship owners must reuse the same member and chat avatar.',
    );
    await tester.pumpWidget(
      host(port, const Locale('zh', 'CN'), target: 'e' * 32),
    );
    await tester.pumpAndSettle();
    expect(
      port.avatarReads,
      6,
      reason:
          'Another organization creates a separate authorized avatar scope.',
    );
    await tester.pumpWidget(const SizedBox());
  });
  test('chat-first avatar warms roster; changed version reloads without stale reuse', () async {
    final port = SharedMediaPort();
    addTearDown(port.changes.close);
    final workspace = CommunityWorkspaceController(port, 'a' * 32);
    final chat = CommunityChatMediaCache(
      port,
      'a' * 32,
      avatars: workspace.avatars,
    );
    addTearDown(workspace.dispose);
    addTearDown(chat.dispose);
    final messages = await port.readChat('a' * 32);
    final first = await chat.load(messages.messages.first);
    await workspace.load();
    expect(workspace.image('d' * 32), same(first.avatar));
    expect(port.avatarReads, 0);
    port.avatarVersion = 'b' * 64;
    await workspace.load();
    expect(port.avatarReads, 3);
    expect(identical(workspace.image('d' * 32), first.avatar), isFalse);
    await workspace.load();
    expect(port.avatarReads, 3);
  });
}
