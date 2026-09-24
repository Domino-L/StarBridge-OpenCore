import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show MemoryPrivacy, app, viewport;

import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';

import 'privacy_settings_page_test.dart'
    show
        MemoryFriendRequestPrivacy,
        MemoryDirectMessagePrivacy,
        MemoryRecentlyPlayedPrivacy;

void main() {
  testWidgets('social refresh preserves draft, section navigation and saving', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final local = LocalPrivacyController(MemoryPrivacy());
    final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
    final port = HeldFriendRequest();
    final friends = FriendRequestPrivacyModule(port);
    addTearDown(local.dispose);
    addTearDown(sync.dispose);
    addTearDown(friends.dispose);
    await sync.initialize();
    await friends.initialize();
    await tester.pumpWidget(
      app(
        PrivacySettingsPage(
          localPrivacy: local,
          syncPrivacy: sync,
          friendRequestPrivacy: friends,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-section-account')));
    await tester.pumpAndSettle();
    final setting = find.byKey(
      const Key('privacy-friend-requests-authoritative'),
    );
    await tester.ensureVisible(setting);
    await tester.tap(setting);
    await tester.pumpAndSettle();
    port.gate = Completer<void>();
    final refresh = friends.refresh();
    await tester.pump();
    expect(
      find.byKey(const Key('friend-request-privacy-loading')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('privacy-section-scopes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-privacy-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacy-section-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
    await tester.tap(find.byKey(const Key('privacy-save')));
    await tester.pumpAndSettle();
    expect(port.delegate.value, isFalse);
    port.gate!.complete();
    await tester.pumpAndSettle();
    await refresh;
    expect(friends.projection.value.snapshot.allowFriendRequests, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'FriendRequest save during background refresh survives a late read',
    () async {
      final port = HeldFriendRequest();
      final module = FriendRequestPrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value.snapshot.allowFriendRequests;
      port.gate = Completer<void>();
      final refresh = module.refresh();
      await port.started.future;
      expect(module.projection.value.canEdit, isTrue);
      expect(await module.save(!before!), isTrue);
      port.gate!.complete();
      await refresh;
      expect(module.projection.value.snapshot.allowFriendRequests, !before);
    },
  );

  test(
    'FriendRequest identity invalidation clears cached authority immediately',
    () async {
      final port = HeldFriendRequest();
      final module = FriendRequestPrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      port.gate = Completer<void>();
      port.events.add(null);
      await port.started.future;
      expect(module.projection.value.canEdit, isFalse);
      expect(await module.save(false), isFalse);
      port.gate!.complete();
    },
  );

  test(
    'DirectMessage save during background refresh survives a late read',
    () async {
      final port = HeldDirectMessage();
      final module = DirectMessagePrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final before =
          module.projection.value.snapshot.allowStrangerDirectMessages;
      port.gate = Completer<void>();
      final refresh = module.refresh();
      await port.started.future;
      expect(module.projection.value.canEdit, isTrue);
      expect(await module.save(!before!), isTrue);
      port.gate!.complete();
      await refresh;
      expect(
        module.projection.value.snapshot.allowStrangerDirectMessages,
        !before,
      );
    },
  );

  test(
    'DirectMessage identity invalidation clears cached authority immediately',
    () async {
      final port = HeldDirectMessage();
      final module = DirectMessagePrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      port.gate = Completer<void>();
      port.events.add(null);
      await port.started.future;
      expect(module.projection.value.canEdit, isFalse);
      expect(await module.save(false), isFalse);
      port.gate!.complete();
    },
  );

  test(
    'RecentlyPlayed save during background refresh survives a late read',
    () async {
      final port = HeldRecentlyPlayed();
      final module = RecentlyPlayedPrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value.snapshot.enabled;
      port.gate = Completer<void>();
      final refresh = module.refresh();
      await port.started.future;
      expect(module.projection.value.canEdit, isTrue);
      expect(await module.save(!before!), isTrue);
      port.gate!.complete();
      await refresh;
      expect(module.projection.value.snapshot.enabled, !before);
    },
  );

  test(
    'RecentlyPlayed identity invalidation clears cached authority immediately',
    () async {
      final port = HeldRecentlyPlayed();
      final module = RecentlyPlayedPrivacyModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      port.gate = Completer<void>();
      port.events.add(null);
      await port.started.future;
      expect(module.projection.value.canEdit, isFalse);
      expect(await module.save(false), isFalse);
      port.gate!.complete();
    },
  );
}

class HeldFriendRequest implements FriendRequestPrivacyPort {
  final delegate = MemoryFriendRequestPrivacy();
  final events = StreamController<void>.broadcast(sync: true);
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendRequestPrivacySnapshot> read() async {
    final snapshot = await delegate.read();
    if (gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
    }
    return snapshot;
  }

  @override
  Future<FriendRequestPrivacyWriteResult> save(bool value) =>
      delegate.save(value);
  @override
  Future<void> close() => events.close();
}

class HeldDirectMessage implements DirectMessagePrivacyPort {
  final delegate = MemoryDirectMessagePrivacy();
  final events = StreamController<void>.broadcast(sync: true);
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<DirectMessagePrivacySnapshot> read() async {
    final snapshot = await delegate.read();
    if (gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
    }
    return snapshot;
  }

  @override
  Future<DirectMessagePrivacyWriteResult> save(bool value) =>
      delegate.save(value);
  @override
  Future<void> close() => events.close();
}

class HeldRecentlyPlayed implements RecentlyPlayedPrivacyPort {
  final delegate = MemoryRecentlyPlayedPrivacy();
  final events = StreamController<void>.broadcast(sync: true);
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async {
    final snapshot = await delegate.read();
    if (gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
    }
    return snapshot;
  }

  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(bool value, int revision) =>
      delegate.save(value, revision);
  @override
  Future<void> close() => events.close();
}
