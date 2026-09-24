import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import 'community_sharing_test.dart' show SharingFixture;

void main() {
  test(
    'rename preserves sharing draft and supersedes a pending target read',
    () async {
      final port = HeldTargets();
      final controller = LocalPrivacyController(port);
      addTearDown(controller.dispose);
      await controller.refresh();
      controller.edit(controller.draft!.copyWith(roomFields: 1));
      final draft = controller.draft;
      final before = controller.communityTargets!;
      port.gate = Completer<CommunitySharingTargets>();
      final refresh = controller.refreshCommunityTargets();
      controller.renameCommunity('A', '新名称');
      expect(controller.communityTargets!.communities.first.name, '新名称');
      expect(controller.draft, same(draft));
      port.gate!.complete(before);
      await refresh;
      expect(controller.communityTargets!.communities.first.name, '新名称');
      expect(
        controller.communityTargets!.communities.first.joinedAt,
        before.communities.first.joinedAt,
      );
      expect(
        controller.communityTargets!.communities.last,
        same(before.communities.last),
      );
      expect(controller.draft, same(draft));
      expect(controller.dirty, isTrue);
      expect(port.writes, 0);
      expect(port.applies, 0);
    },
  );
}

class HeldTargets extends SharingFixture {
  Completer<CommunitySharingTargets>? gate;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() =>
      gate?.future ?? super.readCommunityTargets();
}
