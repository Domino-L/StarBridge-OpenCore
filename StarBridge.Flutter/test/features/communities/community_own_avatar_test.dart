import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_own_avatar.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';

import 'community_shared_media_test.dart' show SharedMediaPort;
import 'community_chat_test.dart' show chatPage;
import 'community_workspace_test.dart' show workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../../embedded_avatar_test.dart' show photo;
import '../friends/social_layout_test.dart' show loadFonts;

class OwnAvatarPort extends SharedMediaPort
    implements CommunityOwnAvatarSource {
  OwnAvatarPort() {
    ownAvatarImageData = chat.avatar;
    avatarVersion = sha256.convert(utf8.encode(chat.avatar)).toString();
  }
  @override
  String? ownAvatarImageData;
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'member widget receives the existing valid photo without a media request',
    (tester) async {
      final port = OwnAvatarPort()..ownAvatarImageData = photo;
      port.avatarVersion = sha256.convert(utf8.encode(photo)).toString();
      addTearDown(port.changes.close);
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final avatar = tester.widget<CommunityWorkspaceImage>(
        find.descendant(
          of: find.byType(UserAvatarMenu),
          matching: find.byType(CommunityWorkspaceImage),
        ),
      );
      expect(avatar.bytes, base64Decode(photo.split(',').last));
      expect(avatar.loading, isFalse);
      expect(port.avatarReads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'legacy unprefixed content version matches the normalized account image',
    () async {
      final port = OwnAvatarPort();
      addTearDown(port.changes.close);
      port.avatarVersion = sha256
          .convert(utf8.encode(port.chat.avatar.split(',').last))
          .toString();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      await model.load();
      expect(model.image('d' * 32), isNotNull);
      expect(port.avatarReads, 0);
      port.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(model.workspace, isNull);
      expect(
        model.image('d' * 32),
        isNull,
        reason: 'Account invalidation also removes reused image bytes.',
      );
    },
  );
  for (final variant in [
    'another member',
    'new version',
    'withdrawn image',
    'invalid data',
    'removed avatar',
  ]) {
    test('local reuse respects $variant', () async {
      final port = OwnAvatarPort();
      addTearDown(port.changes.close);
      if (variant == 'new version') port.avatarVersion = 'e' * 64;
      if (variant == 'withdrawn image') port.ownAvatarImageData = null;
      if (variant == 'invalid data') {
        port.ownAvatarImageData = 'data:image/png;base64,%%%';
        port.avatarVersion = sha256
            .convert(utf8.encode(port.ownAvatarImageData!))
            .toString();
      }
      port.reader = (target, query, offset) async {
        final payload = workspacePayload(target: target, query: query);
        final row = (payload['members'] as List).single as Map;
        row['memberRef'] = 'd' * 32;
        row['isSelf'] = variant != 'another member';
        row['hasAvatar'] = variant != 'removed avatar';
        row['avatarVersion'] = port.avatarVersion;
        return CommunityWorkspace.parse(payload);
      };
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      await model.load();
      if (variant == 'removed avatar') {
        expect(model.image('d' * 32), isNull);
        expect(port.avatarReads, 0);
      } else {
        expect(model.image('d' * 32), isNotNull);
        expect(
          port.avatarReads,
          3,
          reason: 'Unconfirmed local bytes cannot bypass the normal read.',
        );
      }
    });
  }

  test('local avatar does not skip a message attachment', () async {
    final port = OwnAvatarPort();
    addTearDown(port.changes.close);
    final media = CommunityChatMediaCache(port, 'a' * 32);
    addTearDown(media.dispose);
    final payload = chatPage();
    for (final row in payload['messages'] as List) {
      (row as Map)['avatarVersion'] = port.avatarVersion;
    }
    final message = CommunityChatPage.parse(payload).messages
        .singleWhere((m) => m.isSelf);
    final result = await media.load(message);
    expect(result.avatar, isNotNull);
    expect(result.attachment, isNotNull);
    expect(port.chat.reads, greaterThan(0));
  });

  test(
    'own roster avatar reuses the signed-in image even after leaving the page',
    () async {
      final port = OwnAvatarPort();
      addTearDown(port.changes.close);
      for (var visit = 0; visit < 2; visit++) {
        final model = CommunityWorkspaceController(port, 'a' * 32);
        await model.load();
        expect(
          model.image('d' * 32),
          base64Decode(port.chat.avatar.split(',').last),
        );
        model.dispose();
      }
      expect(
        port.avatarReads,
        0,
        reason: 'The current account already owns these exact image bytes.',
      );
    },
  );

  test('own chat avatar needs no message-detail fetch for an attachment-free message', () async {
    final port = OwnAvatarPort();
    addTearDown(port.changes.close);
    final media = CommunityChatMediaCache(port, 'a' * 32);
    addTearDown(media.dispose);
    final page = await port.readChat('a' * 32);
    final self = page.messages.singleWhere((m) => m.isSelf);
    expect((await media.load(self)).avatar, isNotNull);
    expect(
      port.chat.reads,
      0,
      reason: 'Displaying our own avatar must not reread chat detail.',
    );
  });
}
