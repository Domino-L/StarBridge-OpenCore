import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_avatars.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';

import 'menu_chat_media_test.dart' show photo;
import 'menu_organization_ships_test.dart' show FleetPort;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disabled avatar work stays off and retired decodes cannot reappear',
    () async {
      final gate = Completer<void>();
      var decodes = 0;
      final avatars = MenuOrganizationAvatars(
        decoder: (bytes, width) async {
          decodes++;
          await gate.future;
          return decodeCommunityImage(bytes, width);
        },
      );
      addTearDown(avatars.dispose);
      avatars.enabled = false;
      expect(await avatars.logo(photo), isNull);
      expect(decodes, 0);
      avatars.enabled = true;
      final stale = avatars.logo(photo, background: true);
      expect(decodes, 1);
      avatars.enabled = false;
      avatars.enabled = true;
      gate.complete();
      expect(await stale, isNull);
      expect(await avatars.logo(photo), isNotNull);
      expect(decodes, 2);
      avatars.clear();
      final pending = avatars.logo(photo, background: true);
      avatars.clear();
      expect(await pending, isNull);
    },
  );
  test('full logo cache does not evict a hit', () async {
    var decodes = 0;
    final avatars = MenuOrganizationAvatars(
      decoder: (bytes, width) {
        decodes++;
        return decodeCommunityImage(bytes, width);
      },
    );
    addTearDown(avatars.dispose);
    final png = base64Decode(photo.split(',').last);
    final images = [
      for (var i = 0; i < 32; i++)
        'data:image/png;base64,${base64Encode([...png, i])}',
    ];
    final first = avatars.logo(images.first);
    for (final image in images) {
      expect(await avatars.logo(image), isNotNull);
    }
    // A completed hit must stay available even when the capacity is reached.
    // Cache keys are deliberately varied without adding personal media.
    expect(await avatars.logo(images.first), await first);
    expect(decodes, 32);
  });
  test(
    'a foreground decode timeout preserves the pending shared decode',
    () async {
      final gate = Completer<void>();
      var decodes = 0;
      final avatars = MenuOrganizationAvatars(
        decoder: (bytes, width) async {
          decodes++;
          await gate.future;
          return decodeCommunityImage(bytes, width);
        },
      );
      addTearDown(avatars.dispose);
      expect(await avatars.logo(photo), isNull);
      final retry = avatars.logo(photo);
      gate.complete();
      expect(await retry, isNotNull);
      expect(decodes, 1);
    },
  );
  test(
    'late member result cannot repopulate a cleared account scope',
    () async {
      final port = FleetPort();
      final avatars = MenuOrganizationAvatars();
      addTearDown(avatars.dispose);
      addTearDown(port.close);
      final ship = (await port.readShips(
        'a' * 32,
        query: CommunityShipQuery(text: ''),
      )).ships.first;
      final member = CommunityWorkspaceMember.parse({
        'memberRef': ship.ownerMemberRef,
        'gameName': 'fixture',
        'callsign': '',
        'roleTitle': '',
        'roleColor': '#FFFFFF',
        'isSelf': false,
        'isOwner': false,
        'online': true,
        'hasAvatar': true,
        'avatarVersion': ship.ownerAvatarVersion,
        'liveStatus': 'online',
        'arrivalPendingConfirmation': false,
      });
      final row = avatars.bind(
        <String, Object?>{'avatar': null},
        'a' * 32,
        member,
      );
      final read = avatars.read(port, 'a' * 32, member);
      avatars.clear();
      expect(await read, isNull);
      expect(
        ((avatars.project({
                      'organization': {
                        'rows': [row],
                      },
                    })['organization']
                    as Map)['rows']
                as List)
            .single['avatar'],
        isNull,
      );
    },
  );
}
