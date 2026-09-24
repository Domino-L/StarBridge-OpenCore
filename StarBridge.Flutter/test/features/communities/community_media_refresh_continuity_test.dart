import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_shared_media_test.dart' show SharedMediaPort;
import 'community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload, mediaChunk;

void main() {
  test(
    'accepted snapshot removes a pending logo; late bytes stay discarded',
    () async {
      final port = WorkspaceTestPort();
      final payload = workspacePayload()..['hasLogo'] = true;
      port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
      final media = Completer<Map<String, Object?>>();
      port.mediaReader = (_, _) => media.future;
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final first = model.load();
      await Future<void>.delayed(Duration.zero);
      payload['hasLogo'] = false;
      await model.load();
      expect(model.imageLoading('logo'), isFalse);
      media.complete(mediaChunk(Uint8List.fromList([1, 2, 3]), 0));
      await first;
      expect(model.workspace, isNotNull);
      expect(model.image('logo'), isNull);
      expect(model.error, isNull);
    },
  );

  test(
    'new avatar version cannot be overwritten by the old pending read',
    () async {
      final port = WorkspaceTestPort();
      final payload = workspacePayload();
      final member = (payload['members'] as List).single as Map;
      member['hasAvatar'] = true;
      member['avatarVersion'] = 'a' * 64;
      port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
      final oldMedia = Completer<Map<String, Object?>>();
      var reads = 0;
      final newBytes = Uint8List.fromList([4, 5, 6]);
      port.mediaReader = (_, _) {
        reads++;
        return reads == 1
            ? oldMedia.future
            : Future.value(
                mediaChunk(newBytes, 0, kind: 'avatar', memberRef: 'b' * 32),
              );
      };
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final first = model.load();
      await Future<void>.delayed(Duration.zero);
      member['avatarVersion'] = 'b' * 64;
      await model.load();
      expect(model.image('b' * 32), newBytes);
      oldMedia.complete(
        mediaChunk(
          Uint8List.fromList([1, 2, 3]),
          0,
          kind: 'avatar',
          memberRef: 'b' * 32,
        ),
      );
      await first;
      expect(model.image('b' * 32), newBytes);
      expect(model.imageLoading('b' * 32), isFalse);
      expect(model.error, isNull);
    },
  );

  for (final metadataFails in [false, true]) {
    test(
      'avatar finishes during metadata refresh; failure=$metadataFails',
      () async {
        final port = SharedMediaPort()
          ..heldMember = 'd' * 32
          ..mediaGate = Completer<void>();
        final model = CommunityWorkspaceController(port, 'a' * 32);
        addTearDown(model.dispose);
        addTearDown(port.changes.close);
        final first = model.load();
        await Future<void>.delayed(Duration.zero);
        final read = port.reader!;
        final metadata = Completer<CommunityWorkspace>();
        port.reader = (_, _, _) => metadata.future;
        final refresh = model.load();
        expect(model.imageLoading('d' * 32), isTrue);
        port.mediaGate!.complete();
        await first;
        expect(model.busy, isTrue);
        expect(model.image('d' * 32), isNotNull);
        expect(model.imageLoading('d' * 32), isFalse);
        final image = model.image('d' * 32);
        if (metadataFails) {
          metadata.completeError(const CommunityFailure('unavailable'));
        } else {
          metadata.complete(await read('a' * 32, '', 0));
        }
        await refresh;
        expect(model.image('d' * 32), same(image));
        expect(port.avatarReads, 3);
        expect(model.busy, isFalse);
      },
    );
  }

  for (final mediaFails in [false, true]) {
    test(
      'logo settles after failed metadata refresh; failure=$mediaFails',
      () async {
        final port = WorkspaceTestPort();
        final payload = workspacePayload()..['hasLogo'] = true;
        port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
        final media = Completer<Map<String, Object?>>();
        port.mediaReader = (_, _) => media.future;
        final model = CommunityWorkspaceController(port, 'a' * 32);
        addTearDown(model.dispose);
        addTearDown(port.changes.close);
        final first = model.load();
        await Future<void>.delayed(Duration.zero);
        port.reader = (_, _, _) async =>
            throw const CommunityFailure('unavailable');
        await model.load();
        expect(model.imageLoading('logo'), isTrue);
        if (mediaFails) {
          media.completeError(const CommunityFailure('unavailable'));
        } else {
          media.complete(mediaChunk(Uint8List.fromList([1, 2, 3]), 0));
        }
        await first;
        expect(model.imageLoading('logo'), isFalse);
        expect(model.imageFailed('logo'), mediaFails);
        expect(model.image('logo') != null, !mediaFails);
        expect(model.error, 'unavailable');
      },
    );
  }

  test(
    'media permission loss invalidates an in-flight metadata refresh',
    () async {
      final port = WorkspaceTestPort();
      final payload = workspacePayload()..['hasLogo'] = true;
      port.reader = (_, _, _) async => CommunityWorkspace.parse(payload);
      final media = Completer<Map<String, Object?>>();
      port.mediaReader = (_, _) => media.future;
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final first = model.load();
      await Future<void>.delayed(Duration.zero);
      final metadata = Completer<CommunityWorkspace>();
      port.reader = (_, _, _) => metadata.future;
      final refresh = model.load();
      media.completeError(const CommunityFailure('notAllowed'));
      await first;
      expect(model.workspace, isNull);
      expect(model.imageLoading('logo'), isFalse);
      metadata.complete(CommunityWorkspace.parse(payload));
      await refresh;
      expect(model.workspace, isNull);
      expect(model.error, 'notAllowed');
    },
  );
}
