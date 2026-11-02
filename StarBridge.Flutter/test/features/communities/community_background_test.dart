import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';
import 'package:starbridge_flutter/features/communities/community_roles_copy.dart';
import 'package:starbridge_flutter/features/communities/community_roles_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'community_profile_test.dart' show profilePayload;
import 'community_workspace_test.dart'
    show workspacePayload, mediaChunk, WorkspaceTestPort;

void main() {
  test('Old profile and workspace payloads default background to unset', () {
    expect(
      CommunityEditingProfile.parse(profilePayload()).hasBackground,
      false,
    );
    expect(CommunityWorkspace.parse(workspacePayload()).hasBackground, false);
    expect(
      CommunityWorkspace.parse(workspacePayload()..['hasBackground'] = true)
          .hasBackground,
      true,
    );
  });

  test('Banner grant controls each image without granting profile or logo', () {
    final payload = profilePayload()
      ..['hasBackground'] = true
      ..['access'] = {
        'canEditProfile': false,
        'canEditLogo': false,
        'canEditBanner': true,
      };
    final profile = CommunityEditingProfile.parse(payload);
    expect(profile.hasBackground, true);
    for (final field in [
      'bannerImageData',
      'clearBannerImage',
      'backgroundImageData',
      'clearBackgroundImage',
    ]) {
      expect(profile.permits(field), true);
    }
    expect(profile.permits('description'), false);
    expect(profile.permits('logoImageData'), false);
    expect(communityProfileChange('clearBackgroundImage', true), true);
    expect(
      () => communityProfileChange(
        'backgroundImageData',
        'https://image.invalid',
      ),
      throwsFormatException,
    );
    expect(communityRolePermissions['profile'], contains('fleet.banner.edit'));
    expect(communityRolesCopy['fleet.banner.edit']!.$1, '可编辑横幅和背景');
    expect(communityRolesCopy['fleet.banner.edit']!.$2, '可編輯橫幅和背景');
    expect(communityRolesCopy['fleet.banner.edit']!.$3, isNotEmpty);
  });

  test(
    'Background assembles 2 MiB with the existing chunk/version protocol',
    () async {
      final bytes = Uint8List(2 * 1024 * 1024);
      final received = await assembleCommunityMedia(
        (offset, version) async =>
            mediaChunk(bytes, offset, kind: 'background'),
        'background',
        checkCurrent: () {},
      );
      expect(received, bytes);
      await expectLater(
        assembleCommunityMedia(
          (offset, version) async => mediaChunk(
            Uint8List(bytes.length + 1),
            offset,
            kind: 'background',
          ),
          'background',
          checkCurrent: () {},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Controller loads background and clears it on maintenance/revocation',
    () async {
      final port = _BackgroundPort();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(() async {
        model.dispose();
        await port.changes.close();
      });
      await model.load();
      expect(port.kinds, containsAll(['banner', 'background']));
      expect(model.image('background'), isNotNull);
      model.setImageMaintenancePaused(true);
      expect(model.image('background'), isNull);
      model.invalidate();
      expect(model.workspace, isNull);
    },
  );

  test('Only profile-save requests can exceed the ordinary Bridge limit', () {
    BridgeEnvelope envelope(String name) => BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'request',
      name: name,
      sessionGeneration: 1,
      correlationId: 'background',
      payload: {
        'changes': {'backgroundImageData': 'a' * (3 * 1024 * 1024)},
      },
    );
    final frame = BridgeFrameCodec.encode(envelope('communities.saveProfile'));
    expect(BridgeFrameCodec.decode(frame).name, 'communities.saveProfile');
    expect(
      () => BridgeFrameCodec.encode(envelope('communities.profile')),
      throwsA(isA<BridgeFormatException>()),
    );
  });
}

class _BackgroundPort extends WorkspaceTestPort {
  final kinds = <String>[];
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async => CommunityWorkspace.parse(
    workspacePayload()
      ..['hasBanner'] = true
      ..['hasBackground'] = true,
  );

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    kinds.add(kind);
    return mediaChunk(Uint8List.fromList([1, 2, 3]), offset, kind: kind);
  }
}
