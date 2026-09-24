import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_own_avatar.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_navigation_cache_test.dart' show NavigationPort, card;
import 'community_workspace_test.dart' show workspacePayload, mediaChunk;

class PortraitPort extends NavigationPort implements CommunityOwnAvatarSource {
  final reads = <String>[];
  Completer<void>? hold;
  String? failure;
  int memberCount = 2;
  int active = 0, maximumActive = 0;
  @override
  String? ownAvatarImageData;

  PortraitPort() {
    reader = (target, query, offset) async {
      final payload = workspacePayload(target: target);
      final member =
          (payload['members'] as List).single as Map<String, Object?>;
      payload['hasLogo'] = true;
      payload['hasBanner'] = true;
      payload['totalCount'] = memberCount;
      payload['matchedCount'] = memberCount;
      payload['members'] = [
        {
          ...member,
          'hasAvatar': true,
          if (ownAvatarImageData != null)
            'avatarVersion': sha256
                .convert(utf8.encode(ownAvatarImageData!))
                .toString(),
        },
        for (var index = 1; index < memberCount; index++)
          {
            ...member,
            'memberRef': (index + 11).toRadixString(16).padLeft(32, '0'),
            'isSelf': false,
            'hasAvatar': true,
          },
      ];
      return CommunityWorkspace.parse(payload);
    };
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    reads.add(memberRef ?? kind);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (hold != null) await hold!.future;
      if (failure != null) throw CommunityFailure(failure!);
      return mediaChunk(
        Uint8List.fromList([1, 2, 3]),
        offset,
        kind: kind,
        memberRef: memberRef,
      );
    } finally {
      active--;
    }
  }
}

void main() {
  test('access revocation during remaining idle media clears the prepared workspace', () async {
    final port = PortraitPort();
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    await module.prefetchWorkspace();
    final model = module.workspaceSession.obtain(port, card.targetRef, card.key);
    expect(model.needsMediaPreparation, true);
    port.failure = 'notAllowed';
    await model.prepareRemainingMedia();
    expect(model.error, 'notAllowed');
    expect(model.workspace, isNull);
    expect(model.image('logo'), isNull);
  });
  test(
    'login preparation makes portraits ready before entering organization',
    () async {
      final port = PortraitPort();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      await module.prefetchWorkspace();
      final model = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      expect(model.workspace, isNotNull);
      expect(
        model.image('b' * 32),
        isNotNull,
        reason: 'Self portrait must not wait until the route is opened.',
      );
      expect(model.image('c'.padLeft(32, '0')), isNotNull);
      expect(model.image('logo'), isNotNull);
      expect(port.reads, isNot(contains('banner')));
      expect(module.selected, isNull);
      await model.enter(card.targetRef);
      expect(port.reads.where((key) => key == 'b' * 32), hasLength(1));
      expect(
        port.reads.where((key) => key == 'c'.padLeft(32, '0')),
        hasLength(1),
      );
      expect(port.reads.where((key) => key == 'logo'), hasLength(1));
      expect(port.reads.where((key) => key == 'banner'), hasLength(1));
    },
  );

  test('entry during portrait preparation shares workers and never locks navigation', () async {
    final port = PortraitPort()..hold = Completer<void>();
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    final preparing = module.prefetchWorkspace();
    await Future<void>.delayed(Duration.zero);
    final model = module.workspaceSession.obtain(
      port,
      card.targetRef,
      card.key,
    );
    expect(model.workspace, isNotNull);
    expect(model.busy, false);
    expect(model.showProgress, false);
    final entering = model.enter(card.targetRef);
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, hasLength(3));
    port.hold!.complete();
    await Future.wait([preparing, entering]);
    expect(port.reads, hasLength(4));
    expect(port.reads.toSet(), hasLength(4));
    expect(port.maximumActive, lessThanOrEqualTo(3));
    expect(model.imageLoading('logo'), false);
  });

  test(
    'warmup is bounded and does not read banners or additional member pages',
    () async {
      final port = PortraitPort()..memberCount = 20;
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      await module.prefetchWorkspace();
      expect(port.reads, hasLength(9)); // Eight portraits plus one logo.
      expect(port.reads.first, 'b' * 32);
      expect(port.reads[1], 'logo');
      expect(port.reads, isNot(contains('banner')));
      final model = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      await model.enter(card.targetRef);
      expect(port.reads, hasLength(22));
      expect(port.reads.toSet(), hasLength(22));
      expect(port.maximumActive, lessThanOrEqualTo(3));
    },
  );

  test(
    'verified self portrait is ready while network pictures are still pending',
    () async {
      final port = PortraitPort()
        ..ownAvatarImageData = 'data:image/png;base64,AQID'
        ..hold = Completer<void>();
      final module = CommunitiesModule(port);
      addTearDown(module.dispose);
      final preparing = module.prefetchWorkspace();
      await Future<void>.delayed(Duration.zero);
      final model = module.workspaceSession.obtain(
        port,
        card.targetRef,
        card.key,
      );
      expect(model.image('b' * 32), orderedEquals([1, 2, 3]));
      expect(port.reads, isNot(contains('b' * 32)));
      expect(model.image('logo'), isNull);
      port.hold!.complete();
      await preparing;
    },
  );

  for (final revoked in [false, true]) {
    test(
      'late prepared images cannot survive ${revoked ? 'revoked access' : 'account change'}',
      () async {
        final port = PortraitPort()..hold = Completer<void>();
        final module = CommunitiesModule(port);
        addTearDown(module.dispose);
        final preparing = module.prefetchWorkspace();
        await Future<void>.delayed(Duration.zero);
        final model = module.workspaceSession.obtain(
          port,
          card.targetRef,
          card.key,
        );
        if (revoked) {
          port.failure = 'notAllowed';
        } else {
          port.changes.add(null);
        }
        port.hold!.complete();
        await preparing;
        expect(model.workspace, isNull);
        expect(model.image('b' * 32), isNull);
        expect(model.image('logo'), isNull);
      },
    );
  }

  test('failed speculative images retry on refresh without a navigation retry storm', () async {
    final port = PortraitPort()..failure = 'unavailable';
    final module = CommunitiesModule(port);
    addTearDown(module.dispose);
    await module.prefetchWorkspace();
    final model = module.workspaceSession.obtain(
      port,
      card.targetRef,
      card.key,
    );
    expect(model.workspace, isNotNull);
    expect(model.mediaFailed, true);
    await model.enter(card.targetRef);
    await model.enter(card.targetRef);
    expect(port.reads, hasLength(4));
    port.failure = null;
    await model.load();
    expect(model.image('b' * 32), isNotNull);
    expect(model.image('logo'), isNotNull);
    expect(model.mediaFailed, false);
  });
}
