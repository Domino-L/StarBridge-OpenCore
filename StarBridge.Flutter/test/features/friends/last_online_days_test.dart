import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_codec.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/last_online_days.dart';
import 'package:starbridge_flutter/features/common/organization_member_row.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/direct_messages/bridge_direct_messages.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_directory.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_directory_comparison.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_snapshot_decoder.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_models.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page.dart';

import '../../_support/restricted_files.dart';
import '../communities/community_workspace_test.dart' show workspacePayload;
import '../settings/friend_sharing_controller_test.dart' show Harness;
import 'friends_test.dart' as friends;

void main() {
  test('day text in all three locales and legacy local-calendar/cap', () {
    for (final locale in const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en'),
    ]) {
      final english = locale.languageCode == 'en';
      expect(lastOnlineDaysText(0, locale), english ? 'today' : '今天');
      expect(lastOnlineDaysText(1, locale), english ? 'yesterday' : '昨天');
      expect(lastOnlineDaysText(2, locale), english ? '2 days ago' : '2 天前');
      expect(lastOnlineDaysText(29, locale), english ? '29 days ago' : '29 天前');
      expect(
        lastOnlineDaysText(30, locale),
        english ? '30+ days ago' : '30 天以上',
      );
    }
    expect(
      lastOnlineDaysText(1, const Locale('zh', 'CN'), prefix: true),
      '上次在线 昨天',
    );
    // Local wall-clock instants: the calendar day, not 24-hour blocks.
    final morning = DateTime(2026, 11, 14, 9);
    expect(lastOnlineCalendarDays(DateTime(2026, 11, 14, 1), morning), 0);
    expect(lastOnlineCalendarDays(DateTime(2026, 11, 13, 23), morning), 1);
    expect(lastOnlineCalendarDays(DateTime(2026, 11, 12, 23), morning), 2);
    expect(lastOnlineCalendarDays(DateTime(2026, 11, 14, 20), morning), 0);
    final now = DateTime(2026, 11, 14, 12);
    expect(
      resolveLastOnlineDays({
        'lastOnlineAt': now
            .subtract(const Duration(hours: 47))
            .toUtc()
            .toIso8601String(),
      }, now: now),
      2,
    );
    expect(
      resolveLastOnlineDays({'lastOnlineAt': '2020-01-01T00:00:00Z'}, now: now),
      30,
    );
    expect(
      resolveLastOnlineDays({
        'lastOnlineAt': '2020-01-01T00:00:00Z',
        'lastOnlineDays': 0,
      }, now: now),
      0,
    );
    expect(resolveLastOnlineDays({}), isNull);
  });

  test(
    'strict shared decoder accepts omission/null and rejects other keys',
    () {
      FriendRow parse(Map<String, Object?> shared) => parseFriendsSnapshot(
        friends.directory()
          ..['friends'] = [
            {...friends.row('Fixture'), 'shared': shared},
          ],
      ).groups[FriendsSection.friends]!.single;
      for (final value in [null, 0, 1, 30]) {
        expect(
          parse({'lastOnlineDays': value}).shared['lastOnlineDays'],
          value,
        );
      }
      expect(parse({}).shared, isEmpty);
      for (final value in [-1, 31, 1.5, '3', true]) {
        expect(() => parse({'lastOnlineDays': value}), throwsFormatException);
      }
      expect(() => parse({'unexpected': 3}), throwsFormatException);
    },
  );

  const samplePath =
      '../shared/test-fixtures/last-online-conversations-v1.json';
  const sampleTest =
      'shared contract sample and detached conversation preserve days';
  test(sampleTest, () {
    final wire =
        jsonDecode(File(samplePath).readAsStringSync()) as Map<String, dynamic>;
    final rows = parseConversations(wire);
    expect(rows.map((r) => r.lastOnlineDays), [3, null, null]);
    final restored = decodeConversation(encodeConversation(rows.first));
    expect(restored.lastOnlineDays, 3);
    expect(restored.withoutPresence().lastOnlineDays, isNull);
    expect(
      sameDirectMessageDirectory([restored], [restored.withoutPresence()]),
      isFalse,
    );
  }, skip: restrictedFileSkip(sampleTest, 'sample', samplePath));

  test('community offline projection retains days and never derives from lastUpdated', () {
    final source = Map<String, Object?>.from(
      (workspacePayload()['members'] as List).single as Map,
    );
    for (final status in ['Offline', 'Invisible', 'ManualOffline', 'Paused']) {
      final row = CommunityWorkspaceMember.parse({
        ...source,
        'liveStatus': status,
        'lastOnlineDays': 3,
      });
      expect(row.publicPresence, 'offline');
      expect(row.lastOnlineDays, 3);
      expect(row.lastUpdated, isNull);
      expect(
        CommunityWorkspaceMember.parse({...source, 'liveStatus': status})
            .lastOnlineDays,
        isNull,
      );
    }
    for (final value in [-1, 31, 1.5, '3', true]) {
      expect(
        () => CommunityWorkspaceMember.parse({
          ...source,
          'lastOnlineDays': value,
        }),
        throwsFormatException,
      );
    }
  });

  for (final presence in ['Offline', 'InGame', 'AppOnline', 'Away', null]) {
    for (final days in [3, null]) {
      testWidgets('friends presence=$presence days=$days', (tester) async {
        final port = friends.PendingPort();
        await tester.pumpWidget(
          friends.page(const Locale('zh', 'CN'), () => port),
        );
        await tester.pump();
        port.requests.first.complete(
          FriendsReadResult(
            FriendsReadState.ready,
            snapshot: parseFriendsSnapshot(
              friends.directory()
                ..['friends'] = [
                  {
                    ...friends.row('Fixture'),
                    'shared': {'presence': presence, 'lastOnlineDays': days},
                  },
                ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('上次在线 3 天前'),
          days != null && (presence == 'Offline' || presence == null)
              ? findsOneWidget
              : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final presence in ['offline', 'online']) {
    for (final days in [3, null]) {
      testWidgets('directory and chat header presence=$presence days=$days', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = _ChatPort(presence, days);
        final module = DirectMessagesModule(port);
        await module.refresh();
        await tester.pumpWidget(
          _app(
            DirectMessageDirectory(
              module: module,
              search: '',
              onOpen: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = presence == 'online'
            ? AppStrings.resolve(const Locale('zh', 'CN'))
                  .text('direct.presence.online')
            : days == null
            ? '离线'
            : '离线 · 3 天前';
        expect(find.text(label), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        module.dispose();
        await tester.pumpWidget(
          _app(
            DirectMessagesPage(
              createPort: () => _ChatPort(presence, days),
              onBack: () {},
              initialConversation: port.row,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsWidgets);
        expect(
          find.textContaining('3 天前'),
          presence == 'offline' && days != null ? findsWidgets : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('member cell presence=$presence days=$days', (tester) async {
        await tester.pumpWidget(
          _app(
            OrganizationMemberRow(
              entry: OrganizationMemberEntry(
                reference: 'fixture',
                identity: const Text('Fixture'),
                role: 'Member',
                presence: presence == 'offline'
                    ? OrganizationMemberPresence.offline
                    : OrganizationMemberPresence.online,
                lastOnlineDays: days,
              ),
              columns: const OrganizationMemberColumns.all(),
              roleLabel: 'Role',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('离线 · 3 天前'),
          presence == 'offline' && days != null ? findsOneWidget : findsNothing,
        );
        if (presence == 'offline' && days == null) {
          expect(find.text('离线'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('sync page preserves saved presence-only until manual toggle', (
    tester,
  ) async {
    final initial = InMemorySyncPrivacyAdapter.forReview().current;
    final adapter = InMemorySyncPrivacyAdapter(
      initial: SyncPrivacySnapshot.available(
        revision: 7,
        settings: initial.settings!.copyWith(
          friendDefaults: initial.settings!.friendDefaults.copyWith(
            presence: true,
            lastOnline: false,
          ),
        ),
      ),
    );
    final module = createSyncPrivacyModule(adapter);
    await module.initialize();
    await tester.pumpWidget(_app(SyncPrivacyPage(module: module)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-friends-last-online')), findsNothing);
    final ship = find.byKey(const Key('privacy-friends-ship'));
    await tester.ensureVisible(ship);
    await tester.tap(ship);
    await tester.pumpAndSettle();
    expect(adapter.current.settings!.friendDefaults.presence, isTrue);
    expect(adapter.current.settings!.friendDefaults.lastOnline, isFalse);
    final presence = find.byKey(const Key('privacy-friends-presence'));
    for (final enabled in [false, true]) {
      await tester.ensureVisible(presence);
      await tester.tap(presence);
      await tester.pumpAndSettle();
      expect(adapter.current.settings!.friendDefaults.presence, enabled);
      expect(adapter.current.settings!.friendDefaults.lastOnline, enabled);
    }
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });

  testWidgets(
    'legacy friend draft save preserves bit32 until presence toggle',
    (tester) async {
      final h = Harness();
      h.snapshot = {
        'schemaVersion': 1,
        'revision': 7,
        'operationId': '0' * 32,
        'appliedAt': '2026-11-14T00:00:00Z',
        'fields': 1,
      };
      final drafts = PrivacyPageDrafts();
      await tester.pumpWidget(
        _app(
          PrivacyDraftScope(
            drafts: drafts,
            child: FriendSharingSetting(session: h.session),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('friend-sharing-lastOnline')), findsNothing);
      await tester.tap(find.byKey(const Key('friend-sharing-ship')).first);
      await tester.pumpAndSettle();
      final saving = drafts.save();
      await tester.pumpAndSettle();
      expect(await saving, isTrue);
      expect(h.snapshot['fields'], 9);
      for (final expected in [8, 41]) {
        await tester.tap(
          find.byKey(const Key('friend-sharing-presence')).first,
        );
        await tester.pumpAndSettle();
        final saving = drafts.save();
        await tester.pumpAndSettle();
        expect(await saving, isTrue);
        expect(h.snapshot['fields'], expected);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.close);
      drafts.dispose();
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    StyleRegistry()
        .resolve(StyleRegistry.fallbackStyleId, AppearanceMode.dark)
        .tokens,
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: child),
);

class _ChatPort implements DirectMessagesPort {
  _ChatPort(String presence, int? days)
    : row = Conversation(
        '0' * 32,
        'Fixture',
        '',
        DateTime.utc(2026),
        0,
        'friend',
        presence: presence,
        lastOnlineDays: days,
      );
  final Conversation row;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async => [row];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => DirectPage(ref, const [], 0, 0, false, 'friend');
  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}
