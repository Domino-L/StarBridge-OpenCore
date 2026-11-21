import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show MemoryPrivacy, app, viewport;
import 'event_sharing_controller_test.dart' as events show Harness;
import 'friend_sharing_controller_test.dart' as friends show Harness;

void main() {
  for (final action in [
    'open',
    'cancel',
    'adopt',
    'friend switch',
    'event switch',
  ]) {
    testWidgets('first-use privacy suggestions: $action', (tester) async {
      viewport(tester, const Size(1280, 1000));
      final local = LocalPrivacyController(MemoryPrivacy());
      final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
      final friendHost = friends.Harness();
      final eventHost = events.Harness(
        onFriendRequest: (request, connection) =>
            friendHost.reply(request, responseConnection: connection),
      )..subject = friendHost.subject;
      addTearDown(local.dispose);
      addTearDown(sync.dispose);
      await sync.initialize();
      await tester.pumpWidget(
        app(
          PrivacySettingsPage(
            localPrivacy: local,
            syncPrivacy: sync,
            eventSession: eventHost.session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final drafts = tester
          .widget<PrivacyDraftScope>(find.byType(PrivacyDraftScope))
          .notifier!;
      final save = find.byKey(const Key('privacy-save'));
      final suggestion = find.text('建议：全部开启，尚未保存');

      Future<void> tap(String key) async {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> adopt(String card, List<String> items) async {
        final dirtyBefore = drafts.dirty;
        await tap('$card-sharing-adopt-suggestion');
        final dialog = find.byKey(
          const Key('privacy-sharing-suggestion-dialog'),
        );
        expect(dialog, findsOneWidget);
        for (final item in items) {
          expect(
            find.descendant(of: dialog, matching: find.text(item)),
            findsOneWidget,
          );
        }
        expect(drafts.dirty, dirtyBefore);
        await tap(
          'privacy-sharing-suggestion-${action == 'cancel' ? 'cancel' : 'confirm'}',
        );
        expect(dialog, findsNothing);
      }

      try {
        expect(drafts.dirty, isFalse);
        expect(save, findsNothing);
        await tap('privacy-section-account');
        expect(suggestion, findsOneWidget);
        expect(find.text('未向好友共享状态。'), findsOneWidget);
        expect(save, findsNothing);
        const fields = [
          'presence',
          'serverRelation',
          'serverDetails',
          'ship',
          'location',
          'lastOnline',
        ];
        for (final field in fields) {
          expect(
            tester
                .widget<SwitchListTile>(
                  find.byKey(Key('friend-sharing-$field')),
                )
                .value,
            isFalse,
          );
        }
        if (action == 'adopt' || action == 'cancel') {
          await adopt('friend', [
            '在线与游戏中',
            '最小服务器关系',
            '服务器详情',
            '当前舰船',
            '当前位置',
            '最后在线时间',
          ]);
          if (action == 'cancel') {
            for (final field in fields) {
              expect(
                tester
                    .widget<SwitchListTile>(
                      find.byKey(Key('friend-sharing-$field')),
                    )
                    .value,
                isFalse,
              );
            }
          }
        } else if (action == 'friend switch') {
          await tap('friend-sharing-ship');
        }

        await tap('privacy-section-events');
        expect(suggestion, findsOneWidget);
        expect(find.textContaining('尚未开启事件共享。'), findsOneWidget);
        if (action == 'adopt' || action == 'cancel') {
          await adopt('event', ['房间事件共享', 'A', 'B', '全部事件类型']);
        } else if (action == 'event switch') {
          await tap('privacy-scope-event-room-audience-events-enabled');
        }

        expect(friendHost.writes, isEmpty);
        expect(eventHost.writes, isEmpty);
        if (action == 'open' || action == 'cancel') {
          expect(
            tester
                .widgetList<EventScopeEditor>(find.byType(EventScopeEditor))
                .map((scope) => scope.choice),
            List.filled(3, EventSharingChoice.unconfirmed),
          );
          expect(drafts.dirty, isFalse);
          expect(save, findsNothing);
          expect(find.byKey(const Key('privacy-discard')), findsNothing);
          expect(find.text('有未保存的更改'), findsNothing);
          final leave = confirmLocalPrivacyLeave(
            tester.element(find.byType(PrivacySettingsPage)),
            local,
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
          expect(await leave, isTrue);
          return;
        }

        expect(drafts.dirty, isTrue);
        expect(find.text('有未保存的更改'), findsOneWidget);
        await tap('privacy-save');
        expect(drafts.dirty, isFalse);
        if (action == 'event switch') {
          expect(friendHost.writes, isEmpty);
        } else {
          final payload = friendHost.writes.single.payload;
          expect(payload['expectedRevision'], 0);
          expect(payload['fields'], action == 'adopt' ? 63 : 8);
        }
        if (action == 'friend switch') {
          expect(eventHost.writes, isEmpty);
        } else {
          final payload = eventHost.writes.single.payload;
          expect(payload['expectedRevision'], 0);
          expect(payload['publicationEnabled'], isTrue);
          final settings = payload['settings'] as Map;
          expect(settings['room'], {'enabled': true, 'selectedTypes': 47});
          final communities = settings['communities'] as List;
          expect(
            communities.map((row) => row['code']),
            action == 'adopt' ? ['A', 'B'] : isEmpty,
          );
          for (final row in communities) {
            expect(row['choice'], {'enabled': true, 'selectedTypes': 47});
            expect(row['joinedAt'], events.Harness.joined);
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await eventHost.close();
          await friendHost.close();
        });
      }
    });
  }

  for (final scenario in ['friend', 'membership', 'discard', 'unconfirmed']) {
    final friendConflict = scenario == 'friend';
    final discard = scenario == 'discard';
    final unconfirmed = scenario == 'unconfirmed';
    testWidgets(
      'privacy $scenario conflict preserves the other card and allows a fresh edit',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final local = LocalPrivacyController(MemoryPrivacy());
        final sync = createSyncPrivacyModule(
          HostUnavailableSyncPrivacyAdapter(),
        );
        final friendHost = friends.Harness();
        final eventHost = events.Harness(
          onFriendRequest: (request, connection) =>
              friendHost.reply(request, responseConnection: connection),
        )..subject = friendHost.subject;
        addTearDown(local.dispose);
        addTearDown(sync.dispose);
        await sync.initialize();

        Future<void> tap(String key) async {
          final target = find.byKey(Key(key));
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        Future<void> adopt(String card) async {
          await tap('$card-sharing-adopt-suggestion');
          await tap('privacy-sharing-suggestion-confirm');
        }

        try {
          await tester.pumpWidget(
            app(
              PrivacySettingsPage(
                localPrivacy: local,
                syncPrivacy: sync,
                eventSession: eventHost.session,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final drafts = tester
              .widget<PrivacyDraftScope>(find.byType(PrivacyDraftScope))
              .notifier!;
          const friendKey = 'friend-fields';
          const eventKey = 'event-choices';
          Map<String?, EventSharingChoice>? eventDraft() =>
              drafts.value<Map<String?, EventSharingChoice>?>(eventKey, null);
          const firstUseEvent = EventSharingChoice(
            enabled: true,
            selectedTypes: EventSharingChoice.allTypes,
          );

          if (friendConflict) {
            await tap('privacy-section-events');
            await adopt('event');
            await tap('privacy-section-account');
            await adopt('friend');
            friendHost.snapshot = {
              'schemaVersion': 1,
              'revision': 1,
              'operationId': '0' * 32,
              'appliedAt': '2026-01-01T00:00:00Z',
              'fields': 0,
            };
          } else {
            await tap('privacy-section-account');
            await adopt('friend');
            await tap('privacy-section-events');
            await adopt('event');
            if (discard) {
              eventHost.codes.add('C');
            } else if (unconfirmed) {
              eventHost.publicationState = 'unconfirmed';
              eventHost.snapshot = {
                ...eventHost.snapshot,
                'revision': 1,
                'operationId': '0' * 32,
                'appliedAt': '2026-01-01T00:00:00Z',
                'settings': {
                  'room': EventSharingChoice.unconfirmed.toJson(),
                  'communities': <Object>[],
                },
              };
            } else {
              eventHost.joinedAt = '2026-10-16T00:00:00.1234567+00:00';
            }
          }
          expect(drafts.value<int?>(friendKey, null), 63);
          expect(eventDraft(), {
            null: firstUseEvent,
            'A': firstUseEvent,
            'B': firstUseEvent,
          });
          await tester.pump(const Duration(seconds: 15));
          await tester.pumpAndSettle();
          await tap('privacy-save');

          expect(friendHost.writes, isEmpty);
          expect(eventHost.writes, isEmpty);
          expect(drafts.dirty, isTrue);
          expect(find.text('部分设置有更新，请查看对应卡片。'), findsOneWidget);
          if (friendConflict) {
            expect(drafts.value<int?>(friendKey, null), isNull);
            expect(eventDraft(), {
              null: firstUseEvent,
              'A': firstUseEvent,
              'B': firstUseEvent,
            });
            expect(find.textContaining('这张卡片的设置已在别处更新'), findsOneWidget);
            final ship = tester.widget<SwitchListTile>(
              find.byKey(const Key('friend-sharing-ship')),
            );
            expect(ship.value, isFalse);
            expect(ship.onChanged, isNotNull);
            await tap('friend-sharing-ship');
          } else {
            expect(eventDraft(), isNull);
            expect(drafts.value<int?>(friendKey, null), 63);
            final notice = find.textContaining(
              unconfirmed ? '这张卡片的设置已在别处更新' : '社区成员关系已变化',
            );
            expect(notice, findsOneWidget);
            EventScopeEditor scope(String id) =>
                tester.widget<EventScopeEditor>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is EventScopeEditor && widget.scopeKey == id,
                  ),
                );
            expect(scope('event-room').choice, EventSharingChoice.unconfirmed);
            expect(scope('event-room').canEdit, isTrue);
            const roomSwitch =
                'privacy-scope-event-room-audience-events-enabled';
            if (discard) {
              expect(scope('event-C').choice.enabled, isFalse);
              await tap('privacy-discard');
              expect(drafts.dirty, isFalse);
              expect(scope('event-room').choice.enabled, isFalse);
            }
            await tap(roomSwitch);
          }

          await tap('privacy-save');
          expect(drafts.dirty, isFalse);
          if (discard) {
            expect(friendHost.writes, isEmpty);
          } else {
            expect(
              friendHost.writes.single.payload['expectedRevision'],
              friendConflict ? 1 : 0,
            );
            expect(
              friendHost.writes.single.payload['fields'],
              friendConflict ? 8 : 63,
            );
          }
          final eventWrite = eventHost.writes.single.payload;
          expect(eventWrite['expectedRevision'], unconfirmed ? 1 : 0);
          final settings = eventWrite['settings'] as Map;
          expect(settings['room'], firstUseEvent.toJson());
          final communities = settings['communities'] as List;
          expect(
            communities.map((row) => row['code']),
            friendConflict || unconfirmed ? ['A', 'B'] : isEmpty,
          );
          for (final row in communities) {
            expect(row['joinedAt'], eventHost.joinedAt);
            expect(row['choice'], {
              'enabled': friendConflict,
              'selectedTypes': EventSharingChoice.allTypes,
            });
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await eventHost.close();
            await friendHost.close();
          });
        }
      },
    );
  }

  testWidgets('silent account readback clears both sharing drafts and allows fresh edits', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final local = LocalPrivacyController(MemoryPrivacy());
    final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
    final friendHost = friends.Harness();
    final eventHost = events.Harness(
      onFriendRequest: (request, connection) =>
          friendHost.reply(request, responseConnection: connection),
    )..subject = friendHost.subject;
    addTearDown(local.dispose);
    addTearDown(sync.dispose);
    await sync.initialize();

    Future<void> tap(String key) async {
      final target = find.byKey(Key(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    try {
      await tester.pumpWidget(
        app(
          PrivacySettingsPage(
            localPrivacy: local,
            syncPrivacy: sync,
            eventSession: eventHost.session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final drafts = tester
          .widget<PrivacyDraftScope>(find.byType(PrivacyDraftScope))
          .notifier!;
      const friendKey = 'friend-fields';
      const eventKey = 'event-choices';
      Map<String?, EventSharingChoice>? eventDraft() =>
          drafts.value<Map<String?, EventSharingChoice>?>(eventKey, null);
      const on = EventSharingChoice(enabled: true, selectedTypes: 47);
      await tap('privacy-section-account');
      await tap('friend-sharing-ship');
      await tap('privacy-section-events');
      await tap('privacy-scope-event-room-audience-events-enabled');
      expect(drafts.value<int?>(friendKey, null), 8);
      expect(eventDraft()?[null], on);

      // The new account has the same values as the old drafts. Equality must
      // never acknowledge a draft across accounts.
      friendHost.subject = eventHost.subject = 'second-synthetic-owner';
      friendHost.snapshot = {
        ...friendHost.snapshot,
        'revision': 7,
        'operationId': '0' * 32,
        'appliedAt': '2026-01-01T00:00:00Z',
        'fields': 8,
      };
      eventHost.snapshot = {
        ...eventHost.snapshot,
        'revision': 11,
        'operationId': '0' * 32,
        'appliedAt': '2026-01-01T00:00:00Z',
        'publicationEnabled': true,
        'settings': {'room': on.toJson(), 'communities': []},
      };
      // The first poll detects the retired account. The next poll successfully
      // reads both settings for the new account without any account event.
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(drafts.value<int?>(friendKey, null), 8);
      expect(eventDraft()?[null], on);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(drafts.value<int?>(friendKey, null), isNull);
      expect(eventDraft(), isNull);
      expect(drafts.dirty, isFalse);
      expect(friendHost.writes, isEmpty);
      expect(eventHost.writes, isEmpty);

      final conflict = find.text('这张卡片的设置已在别处更新。请查看最新设置后重新编辑。');
      expect(conflict, findsOneWidget);
      await tap('privacy-scope-event-room-field-ship');
      expect(eventDraft()?[null]?.selectedTypes, 43);
      await tap('privacy-section-account');
      expect(conflict, findsOneWidget);
      await tap('friend-sharing-location');
      expect(drafts.value<int?>(friendKey, null), 24);
      expect(friendHost.writes, isEmpty);
      expect(eventHost.writes, isEmpty);
      await tap('privacy-save');
      expect(friendHost.writes.single.payload['expectedRevision'], 7);
      expect(friendHost.writes.single.payload['fields'], 24);
      final eventWrite = eventHost.writes.single.payload;
      expect(eventWrite['expectedRevision'], 11);
      expect((eventWrite['settings'] as Map)['room'], {
        'enabled': true,
        'selectedTypes': 43,
      });
      expect(drafts.dirty, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await eventHost.close();
        await friendHost.close();
      });
    }
  });

  testWidgets(
    'privacy footer shows local loading after first suggestions arrive',
    (tester) async {
      viewport(tester, const Size(1280, 1000));
      final port = _PendingLocalPrivacy();
      final local = LocalPrivacyController(port);
      final sync = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
      final host = events.Harness();
      addTearDown(local.dispose);
      addTearDown(sync.dispose);
      await sync.initialize();

      try {
        await tester.pumpWidget(
          app(
            PrivacySettingsPage(
              localPrivacy: local,
              syncPrivacy: sync,
              eventSession: host.session,
            ),
          ),
        );
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          find.byKey(
            const Key('event-sharing-adopt-suggestion'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(local.status, LocalPrivacyStatus.loading);
        expect(local.draft, isNull);
        final loading = find.text('隐私设置还没读出来，读出来以后才能修改。');
        expect(loading, findsOneWidget);
        expect(find.byKey(const Key('privacy-save')), findsOneWidget);

        port.readGate.complete(port.snapshot);
        await tester.pumpAndSettle();
        expect(local.status, LocalPrivacyStatus.ready);
        expect(loading, findsNothing);
        expect(find.byKey(const Key('privacy-save')), findsNothing);
      } finally {
        if (!port.readGate.isCompleted) port.readGate.complete(port.snapshot);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(host.close);
      }
    },
  );

  for (final fail in [false, true]) {
    for (final editLocal in [false, true]) {
      testWidgets(
        'unsaved local privacy with account save: fail=$fail/editLocal=$editLocal',
        (tester) async {
          viewport(tester, const Size(1280, 900));
          final port = MemoryPrivacy();
          final local = LocalPrivacyController(port);
          final sync = createSyncPrivacyModule(
            HostUnavailableSyncPrivacyAdapter(),
          );
          final accountPort = _AccountPrivacy(fail: fail);
          final account = DirectMessagePrivacyModule(accountPort);
          addTearDown(local.dispose);
          addTearDown(sync.dispose);
          addTearDown(account.dispose);
          await sync.initialize();
          await account.initialize();
          await tester.pumpWidget(
            app(
              PrivacySettingsPage(
                localPrivacy: local,
                syncPrivacy: sync,
                directMessagePrivacy: account,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(local.hasSaved, isFalse);
          expect(local.dirty, isFalse);
          if (editLocal) {
            local.edit(local.draft!.copyWith(roomFields: 0));
            await tester.pumpAndSettle();
            expect(local.dirty, isTrue);
          }
          await tester.tap(find.byKey(const Key('privacy-section-account')));
          await tester.pumpAndSettle();
          final toggle = find.byKey(
            const Key('privacy-stranger-messages-authoritative'),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('privacy-save')));
          await tester.pumpAndSettle();
          expect(accountPort.writes, 1);
          // Only an explicit local edit is saved, independently of account
          // acknowledgement. Untouched defaults must never become saved.
          expect(port.writes, editLocal ? 1 : 0);
          expect(local.hasSaved, editLocal);
          expect(local.dirty, isFalse);
          if (fail) expect(find.text('部分更改未能确认保存，草稿已保留。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final discardChanges in [false, true]) {
    testWidgets(
      discardChanges
          ? 'privacy footer shows no unsaved changes after discarding an edit'
          : 'privacy footer shows no unsaved changes on open',
      (tester) async {
        viewport(tester, const Size(1280, 900));
        final port = MemoryPrivacy();
        final local = LocalPrivacyController(port);
        final sync = createSyncPrivacyModule(
          HostUnavailableSyncPrivacyAdapter(),
        );
        addTearDown(local.dispose);
        addTearDown(sync.dispose);
        await sync.initialize();

        await tester.pumpWidget(
          app(PrivacySettingsPage(localPrivacy: local, syncPrivacy: sync)),
        );
        await tester.pumpAndSettle();

        if (discardChanges) {
          final roomShip = find.byKey(
            const Key('privacy-scope-room-field-ship'),
          );
          await tester.ensureVisible(roomShip);
          await tester.tap(roomShip);
          await tester.pumpAndSettle();
          expect(find.text('有未保存的更改'), findsOneWidget);

          await tester.tap(find.text('放弃更改'));
          await tester.pumpAndSettle();
        }

        expect(find.text('没有未保存的更改'), findsOneWidget);
        expect(find.text('所有更改已保存'), findsNothing);
        expect(local.dirty, isFalse);
        expect(port.writes, 0);
      },
    );
  }

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

final class _PendingLocalPrivacy extends MemoryPrivacy {
  final readGate = Completer<LocalPrivacySnapshot>();

  @override
  Future<LocalPrivacySnapshot> read() => readGate.future;
}

class _AccountPrivacy implements DirectMessagePrivacyPort {
  _AccountPrivacy({required this.fail});
  final bool fail;
  bool value = false;
  int writes = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<DirectMessagePrivacySnapshot> read() async =>
      DirectMessagePrivacySnapshot.available(
        allowStrangerDirectMessages: value,
        updatedAt: null,
      );
  @override
  Future<DirectMessagePrivacyWriteResult> save(bool next) async {
    writes++;
    if (fail) {
      return const DirectMessagePrivacyWriteResult.rejected(
        DirectMessagePrivacyFailure.writeFailed,
      );
    }
    value = next;
    return DirectMessagePrivacyWriteResult.completed(await read());
  }

  @override
  Future<void> close() async {}
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
