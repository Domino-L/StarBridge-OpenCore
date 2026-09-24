import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show MemoryPrivacy, app, viewport;

void main() {
  testWidgets(
    'section changes preserve unsaved scope edits without prompting',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final local = LocalPrivacyController(MemoryPrivacy());
      final sync = createSyncPrivacyModule(
        InMemorySyncPrivacyAdapter.forReview(),
      );
      addTearDown(local.dispose);
      addTearDown(sync.dispose);
      await sync.initialize();

      await tester.pumpWidget(
        app(PrivacySettingsPage(localPrivacy: local, syncPrivacy: sync)),
      );
      await tester.pumpAndSettle();

      expect(find.text('共享范围'), findsOneWidget);
      expect(find.text('好友与社交'), findsOneWidget);
      expect(find.byKey(const Key('local-privacy-page')), findsOneWidget);

      final roomShip = find.byKey(const Key('privacy-scope-room-field-ship'));
      await tester.ensureVisible(roomShip);
      await tester.tap(roomShip);
      await tester.pumpAndSettle();
      expect(local.dirty, isTrue);

      await tester.tap(find.byKey(const Key('privacy-section-account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
      expect(local.dirty, isTrue);
      expect(find.byKey(const Key('privacy-friends-presence')), findsOneWidget);
      expect(find.byKey(const Key('privacy-events-enabled')), findsOneWidget);
      expect(find.text('允许非好友发送好友申请'), findsOneWidget);
      expect(find.text('允许非好友发起私信'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable account privacy still shows the complete groups', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 900));
    final local = LocalPrivacyController(MemoryPrivacy());
    final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
    addTearDown(local.dispose);
    addTearDown(sync.dispose);
    await sync.initialize();

    await tester.pumpWidget(
      app(PrivacySettingsPage(localPrivacy: local, syncPrivacy: sync)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-section-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-privacy-unavailable')), findsOneWidget);
    expect(find.text('好友长期默认'), findsOneWidget);
    expect(find.text('协作活动事件'), findsOneWidget);
    expect(find.text('社交隐私'), findsOneWidget);
    expect(find.text('允许非好友发起私信'), findsOneWidget);
    expect(find.text('暂时无法读取私信接收设置。'), findsOneWidget);
    expect(find.text('允许非好友发送好友申请'), findsOneWidget);
    expect(find.text('暂时无法读取好友申请设置。'), findsOneWidget);
    expect(find.text('允许共同参与者在“最近同玩”中找到我'), findsOneWidget);
    expect(find.text('暂时无法读取最近同玩设置。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authoritative contact privacy settings remain independently editable',
    (tester) async {
      viewport(tester, const Size(1280, 900));
      final local = LocalPrivacyController(MemoryPrivacy());
      final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
      final port = MemoryDirectMessagePrivacy();
      final directMessages = DirectMessagePrivacyModule(port);
      final friendPort = MemoryFriendRequestPrivacy();
      final friendRequests = FriendRequestPrivacyModule(friendPort);
      final recentlyPlayedPort = MemoryRecentlyPlayedPrivacy();
      final recentlyPlayed = RecentlyPlayedPrivacyModule(recentlyPlayedPort);
      addTearDown(local.dispose);
      addTearDown(sync.dispose);
      addTearDown(directMessages.dispose);
      addTearDown(friendRequests.dispose);
      addTearDown(recentlyPlayed.dispose);
      await sync.initialize();
      await directMessages.initialize();
      await friendRequests.initialize();
      await recentlyPlayed.initialize();

      await tester.pumpWidget(
        app(
          PrivacySettingsPage(
            localPrivacy: local,
            syncPrivacy: sync,
            directMessagePrivacy: directMessages,
            friendRequestPrivacy: friendRequests,
            recentlyPlayedPrivacy: recentlyPlayed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-section-account')));
      await tester.pumpAndSettle();

      final setting = find.byKey(
        const Key('privacy-stranger-messages-authoritative'),
      );
      expect(setting, findsOneWidget);
      await tester.ensureVisible(setting);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      expect(port.value, isFalse);
      final friendSetting = find.byKey(
        const Key('privacy-friend-requests-authoritative'),
      );
      expect(friendSetting, findsOneWidget);
      await tester.ensureVisible(friendSetting);
      await tester.tap(friendSetting);
      await tester.pumpAndSettle();
      expect(friendPort.value, isTrue);
      final recentlyPlayedSetting = find.byKey(
        const Key('privacy-recently-played-authoritative'),
      );
      expect(recentlyPlayedSetting, findsOneWidget);
      expect(find.byKey(const Key('privacy-recently-played')), findsNothing);
      await tester.ensureVisible(recentlyPlayedSetting);
      await tester.tap(recentlyPlayedSetting);
      await tester.pumpAndSettle();
      expect(recentlyPlayedPort.value, isTrue);
      expect(recentlyPlayedPort.revision, 0);
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(port.value, isTrue);
      expect(friendPort.value, isFalse);
      expect(recentlyPlayedPort.value, isFalse);
      expect(recentlyPlayedPort.revision, 1);
      expect(find.textContaining('允许非好友发起私信 · 暂不可用'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final class MemoryRecentlyPlayedPrivacy implements RecentlyPlayedPrivacyPort {
  bool value = true;
  DateTime? enabledAt;
  DateTime? disabledAt;
  int revision = 0;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async =>
      RecentlyPlayedPrivacySnapshot.available(
        enabled: value,
        enabledAt: enabledAt,
        disabledAt: disabledAt,
        revision: revision,
      );

  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(
    bool enabled,
    int expectedRevision,
  ) async {
    if (expectedRevision != revision) {
      return const RecentlyPlayedPrivacyWriteResult.rejected(
        RecentlyPlayedPrivacyFailure.writeConflict,
      );
    }
    value = enabled;
    revision++;
    if (enabled) {
      enabledAt = DateTime.utc(2026, 9, 12, 12);
    } else {
      disabledAt = DateTime.utc(2026, 9, 12, 12);
    }
    return RecentlyPlayedPrivacyWriteResult.completed(
      RecentlyPlayedPrivacySnapshot.available(
        enabled: value,
        enabledAt: enabledAt,
        disabledAt: disabledAt,
        revision: revision,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class MemoryFriendRequestPrivacy implements FriendRequestPrivacyPort {
  bool value = true;
  DateTime? updatedAt;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<FriendRequestPrivacySnapshot> read() async =>
      FriendRequestPrivacySnapshot.available(
        allowFriendRequests: value,
        updatedAt: updatedAt,
      );

  @override
  Future<FriendRequestPrivacyWriteResult> save(bool allowFriendRequests) async {
    value = allowFriendRequests;
    updatedAt = DateTime.utc(2026, 9, 12, 12);
    return FriendRequestPrivacyWriteResult.completed(
      FriendRequestPrivacySnapshot.available(
        allowFriendRequests: value,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class MemoryDirectMessagePrivacy implements DirectMessagePrivacyPort {
  bool value = false;
  DateTime updatedAt = DateTime.utc(2026, 9, 12, 12);

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<DirectMessagePrivacySnapshot> read() async =>
      DirectMessagePrivacySnapshot.available(
        allowStrangerDirectMessages: value,
        updatedAt: updatedAt,
      );

  @override
  Future<DirectMessagePrivacyWriteResult> save(
    bool allowStrangerDirectMessages,
  ) async {
    value = allowStrangerDirectMessages;
    updatedAt = updatedAt.add(const Duration(seconds: 1));
    return DirectMessagePrivacyWriteResult.completed(
      DirectMessagePrivacySnapshot.available(
        allowStrangerDirectMessages: value,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<void> close() async {}
}
