import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/social_privacy_composition.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'local_privacy_page_test.dart' show MemoryPrivacy, app, viewport;

const _friendRead = 'friendRequests.privacyRead';
const _directRead = 'directMessages.privacyRead';
const _recentRead = 'recentlyPlayed.privacyRead';
const _readNames = [_friendRead, _directRead, _recentRead];
const _friendWrite = 'friendRequests.privacyWrite';

void main() {
  test('all three failed reads recover on the first 5-second retry', () {
    fakeAsync((clock) {
      final host = _SocialPrivacyHost()..failingReads.addAll(_readNames);
      unawaited(host.social.initialize());
      clock.flushMicrotasks();

      _expectUnavailable(host.social);
      expect(host.readCounts, [1, 1, 1]);
      host.failingReads.clear();
      clock.elapse(const Duration(seconds: 4));
      expect(host.readCounts, [1, 1, 1]);
      clock.elapse(const Duration(seconds: 1));
      _expectAvailable(host.social);
      expect(host.readCounts, [2, 2, 2]);
      clock.elapse(const Duration(minutes: 10));
      expect(host.readCounts, [2, 2, 2]);
      unawaited(host.close());
      clock.flushMicrotasks();
    });
  });

  test('read failure backs off by 5s, 15s, 60s, then repeats every 5m', () {
    fakeAsync((clock) {
      final host = _SocialPrivacyHost()..failingReads.addAll(_readNames);
      unawaited(host.social.initialize());
      clock.flushMicrotasks();

      var count = 1;
      for (final seconds in [5, 15, 60, 300, 300]) {
        clock.elapse(Duration(seconds: seconds - 1));
        expect(host.readCounts, [count, count, count]);
        clock.elapse(const Duration(seconds: 1));
        count++;
        expect(host.readCounts, [count, count, count]);
        _expectUnavailable(host.social);
      }
      host.failingReads.clear();
      clock.elapse(const Duration(minutes: 5));
      _expectAvailable(host.social);
      clock.elapse(const Duration(minutes: 10));
      expect(host.readCounts, [count + 1, count + 1, count + 1]);
      unawaited(host.close());
      clock.flushMicrotasks();
    });
  });

  test(
    'temporary host account unavailability retries, then reads settings',
    () {
      fakeAsync((clock) {
        final host = _SocialPrivacyHost()..accountTemporarilyUnavailable = true;
        unawaited(host.social.initialize());
        clock.flushMicrotasks();

        _expectUnavailable(host.social);
        expect(
          host.social.friendRequests.projection.value.snapshot.failure,
          FriendRequestPrivacyFailure.hostUnavailable,
        );
        expect(host.readCounts, [0, 0, 0]);
        host.accountTemporarilyUnavailable = false;
        clock.elapse(const Duration(seconds: 5));
        _expectAvailable(host.social);
        expect(host.readCounts, [1, 1, 1]);
        unawaited(host.close());
        clock.flushMicrotasks();
      });
    },
  );

  test('account change cancels old timers and starts a fresh backoff', () {
    fakeAsync((clock) {
      final host = _SocialPrivacyHost()..failingReads.addAll(_readNames);
      unawaited(host.social.initialize());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 7));
      expect(host.readCounts, [2, 2, 2]);

      unawaited(host.changeAccount());
      clock.flushMicrotasks();
      expect(host.readCounts, [3, 3, 3]);
      expect(clock.nonPeriodicTimerCount, 3);
      host.failingReads.clear();
      clock.elapse(const Duration(seconds: 4));
      expect(host.readCounts, [3, 3, 3]);
      clock.elapse(const Duration(seconds: 1));
      _expectAvailable(host.social);
      expect(host.readCounts, [4, 4, 4]);
      clock.elapse(const Duration(seconds: 30));
      expect(host.readCounts, [4, 4, 4]);
      unawaited(host.close());
      clock.flushMicrotasks();
    });
  });

  test('missing capabilities schedule no timer and skip page-entry reads', () {
    fakeAsync((clock) {
      final host = _SocialPrivacyHost(readCapabilities: const []);
      unawaited(host.social.initialize());
      clock.flushMicrotasks();

      _expectUnavailable(host.social);
      expect(
        host.social.friendRequests.projection.value.snapshot.failure,
        FriendRequestPrivacyFailure.capabilityMissing,
      );
      expect(
        host.social.directMessages.projection.value.snapshot.failure,
        DirectMessagePrivacyFailure.capabilityMissing,
      );
      expect(
        host.social.recentlyPlayed.projection.value.snapshot.failure,
        RecentlyPlayedPrivacyFailure.capabilityMissing,
      );
      expect(clock.nonPeriodicTimerCount, 0);

      // Changing the fixture's capabilities makes any accidental read visible.
      host.session.acceptHostCapabilities(_readNames);
      unawaited(host.social.friendRequests.refreshIfUnavailable());
      unawaited(host.social.directMessages.refreshIfUnavailable());
      unawaited(host.social.recentlyPlayed.refreshIfUnavailable());
      clock.elapse(const Duration(minutes: 15));
      expect(host.readCounts, [0, 0, 0]);
      unawaited(host.close());
      clock.flushMicrotasks();
    });
  });

  test('disposal cancels pending privacy reads', () {
    fakeAsync((clock) {
      final host = _SocialPrivacyHost()..failingReads.addAll(_readNames);
      unawaited(host.social.initialize());
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 3);

      unawaited(host.close());
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(minutes: 15));
      expect(host.readCounts, [1, 1, 1]);
    });
  });

  testWidgets('opening privacy rereads only the unavailable setting', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final host = _SocialPrivacyHost(
      readCapabilities: [_friendRead, _directRead],
    )..failingReads.add(_friendRead);
    final local = LocalPrivacyController(MemoryPrivacy());
    final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
    final gate = Completer<void>();
    await sync.initialize();
    await host.social.initialize();
    expect(host.readCounts, [1, 1, 0]);
    host.friendReadGate = gate.future;

    await tester.pumpWidget(_privacyPage(host.social, local, sync));
    await tester.pump();
    expect(host.readCounts, [2, 1, 0]);
    await tester.tap(find.byKey(const Key('privacy-section-account')));
    await tester.pumpAndSettle();
    expect(host.readCounts, [2, 1, 0]);

    host.failingReads.clear();
    gate.complete();
    await tester.pumpAndSettle();
    expect(host.social.friendRequests.projection.value.canEdit, isTrue);
    expect(host.readCounts, [2, 1, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
    // Stream cancellation can complete outside the widget test's fake zone.
    await tester.runAsync(host.close);
    sync.dispose();
    local.dispose();
  });

  testWidgets(
    'automatic recovery preserves the pending draft and manual save',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final host = _SocialPrivacyHost();
      final local = LocalPrivacyController(MemoryPrivacy());
      final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
      await sync.initialize();
      await host.social.initialize();
      await tester.pumpWidget(_privacyPage(host.social, local, sync));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-section-account')));
      await tester.pumpAndSettle();

      final setting = find.byKey(
        const Key('privacy-friend-requests-authoritative'),
      );
      await tester.ensureVisible(setting);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      expect(host.friendWrites, 0);

      host.failingReads.add(_friendRead);
      await host.social.friendRequests.refresh();
      await tester.pump();
      expect(setting, findsNothing);
      host.failingReads.clear();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        host
            .social
            .friendRequests
            .projection
            .value
            .snapshot
            .allowFriendRequests,
        isTrue,
      );
      final control = find.ancestor(
        of: setting,
        matching: find.byType(StarBridgeSwitch),
      );
      expect(tester.widget<StarBridgeSwitch>(control).value, isFalse);
      expect(host.friendWrites, 0);
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(host.friendWrites, 1);
      expect(host.allowFriendRequests, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      // Stream cancellation can complete outside the widget test's fake zone.
      await tester.runAsync(host.close);
      sync.dispose();
      local.dispose();
    },
  );
}

Widget _privacyPage(
  SocialPrivacyComposition social,
  LocalPrivacyController local,
  SyncPrivacyModule sync,
) => app(
  PrivacySettingsPage(
    localPrivacy: local,
    syncPrivacy: sync,
    friendRequestPrivacy: social.friendRequests,
    directMessagePrivacy: social.directMessages,
    recentlyPlayedPrivacy: social.recentlyPlayed,
  ),
);

void _expectUnavailable(SocialPrivacyComposition social) {
  expect(
    social.friendRequests.projection.value.snapshot.availability,
    FriendRequestPrivacyAvailability.unavailable,
  );
  expect(
    social.directMessages.projection.value.snapshot.availability,
    DirectMessagePrivacyAvailability.unavailable,
  );
  expect(
    social.recentlyPlayed.projection.value.snapshot.availability,
    RecentlyPlayedPrivacyAvailability.unavailable,
  );
}

void _expectAvailable(SocialPrivacyComposition social) {
  expect(social.friendRequests.projection.value.canEdit, isTrue);
  expect(social.directMessages.projection.value.canEdit, isTrue);
  expect(social.recentlyPlayed.projection.value.canEdit, isTrue);
}

final class _SocialPrivacyHost {
  _SocialPrivacyHost({List<String> readCapabilities = _readNames}) {
    final pair = InMemoryBridgeConnection.createPair();
    _connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities([...readCapabilities, _friendWrite]);
    social = SocialPrivacyComposition.connected(session);
    _subscription = _connection.incoming.listen((request) {
      if (request.name != 'bridge.cancel') unawaited(_reply(request));
    });
  }

  late final BridgeConnection _connection;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgeClientSession session;
  late final SocialPrivacyComposition social;
  final failingReads = <String>{};
  final _reads = <String, int>{};
  List<int> get readCounts => [
    for (final name in _readNames) _reads[name] ?? 0,
  ];
  Future<void>? friendReadGate;
  bool accountTemporarilyUnavailable = false;
  bool allowFriendRequests = true;
  int friendWrites = 0;
  int _generation = 4;

  Future<void> _reply(BridgeEnvelope request) async {
    final name = request.name;
    if (_readNames.contains(name)) {
      _reads.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
    if (name == _friendRead && friendReadGate != null) await friendReadGate;
    if (name == _friendWrite) {
      friendWrites++;
      allowFriendRequests = request.payload['allowFriendRequests']! as bool;
    }
    final failed = failingReads.contains(name);
    await _connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: BridgeAccountContext(
          environment: 'test',
          authority: 'scm',
          subject: 'test-subject-$_generation',
        ),
        status: failed ? 'error' : 'ok',
        error: failed
            ? const BridgeErrorBody(
                code: 'test.unavailable',
                message: 'Fixture read failed',
                retryable: true,
              )
            : null,
        payload: failed ? const {} : _payload(name),
      ),
    );
  }

  Map<String, Object?> _payload(String name) => switch (name) {
    'account.getCurrent' => {
      'schemaVersion': 1,
      'state': accountTemporarilyUnavailable
          ? 'credentialTemporarilyUnavailable'
          : 'signedIn',
    },
    _friendRead || _friendWrite => {
      'schemaVersion': 1,
      'allowFriendRequests': allowFriendRequests,
      'updatedAt': null,
    },
    _directRead => {
      'schemaVersion': 1,
      'allowStrangerDirectMessages': false,
      'updatedAt': '2026-09-12T12:00:00Z',
    },
    _recentRead => {
      'schemaVersion': 1,
      'enabled': true,
      'enabledAt': null,
      'disabledAt': null,
      'revision': 1,
    },
    _ => throw StateError('Unexpected fixture request: $name'),
  };

  Future<void> changeAccount() => _connection.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: ++_generation,
      sequence: 0,
      payload: const {},
    ),
  );

  Future<void> close() async {
    social.dispose();
    await _subscription.cancel();
    await session.close();
    await _connection.close();
  }
}
