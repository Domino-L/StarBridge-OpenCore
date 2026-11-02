import '../../_support/development_fixture_path.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/communities/community_activity_port.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/platform/window/taskbar_attention_binding.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/common/organization_communication_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_communication_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_feature.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../common/organization_announcement_management_session_test.dart'
    show FixtureManagementPort;
import '../friends/social_layout_test.dart' show loadFonts, size;
import '../communities/community_announcements_test.dart'
    show announcementPage, announcementRow, announcementAuthor;
import '../communities/community_chat_controller_test.dart' show page;

void main() {
  setUpAll(loadFonts);

  // The upper screen on a window tall enough for preview tiles.
  Future<OfficialFleetModule> pumpUpper(
    WidgetTester tester,
    _Harness host, {
    OrganizationAnnouncementManagementPort? management,
    Size window = const Size(2364, 1384),
  }) async {
    size(tester, window);
    final initial = await InMemoryOfficialFleetAdapter.forReview(
      signedIn: true,
    ).read();
    final module = createOfficialFleetModule(
      _Identity(initial),
      UnavailableOfficialFleetOverviewAdapter(),
      InMemoryOfficialFleetMembersAdapter.forReview(),
      UnavailableOfficialFleetShipsAdapter(),
      communicationFactory: (_) => host.adapter(),
    );
    if (management != null) {
      module.communication.configureAnnouncementManagement(
        owner: management,
        create: () => management,
      );
    }
    addTearDown(host.close);
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('zh', 'CN'),
        ),
        home: Scaffold(body: OfficialFleetPage(module: module)),
      ),
    );
    await tester.pumpAndSettle();
    return module;
  }

  final tile = find.byKey(const Key('official-fleet-tile-chat'));
  final announce = find.byKey(const Key('official-fleet-command-announce'));

  testWidgets('the channel tile previews read messages without their authors', (
    tester,
  ) async {
    final host = _Harness();
    final module = await pumpUpper(tester, host);
    expect(tile, findsOneWidget);
    expect(
      find.descendant(
        of: tile,
        matching: find.textContaining('Message 1', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Fixture pilot', findRichText: true),
      findsNothing,
      reason: 'An official author proof is not retained for the tile.',
    );
    expect(find.text('进入查看最近的消息'), findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('without chat access the tile keeps its plain note', (
    tester,
  ) async {
    final host = _Harness()..canChat = false;
    final module = await pumpUpper(tester, host);
    expect(tile, findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('a denied chat read shows no error mark and no messages', (
    tester,
  ) async {
    final host = _Harness()..chatFailure = 'notAllowed';
    final module = await pumpUpper(tester, host);
    expect(tile, findsNothing);
    expect(find.textContaining('Message 1', findRichText: true), findsNothing);
    expect(find.textContaining('待确认'), findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  group('author renewal is off unless the relay says otherwise', () {
    void support(_Harness host) => host.session.acceptHostCapabilities([
      'officialFleet.communication',
      'officialFleet.communication.authorIdentities',
      'officialFleet.communication.previewAuthors',
    ]);
    int renewals(_Harness host) =>
        host.actions.where((action) => action == 'chatAuthorRenewal').length;

    for (final (name, relay) in const [
      ('an older relay', null),
      ('the switch off', false),
    ]) {
      testWidgets('$name: the body shows, no renewal and no names', (
        tester,
      ) async {
        final host = _Harness()..previewAuthors = relay;
        support(host);
        final module = await pumpUpper(tester, host);
        expect(tile, findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(renewals(host), 0);
        expect(
          find.textContaining('Fixture pilot', findRichText: true),
          findsNothing,
        );
        module.communication.reset();
        await tester.pump();
      });
    }

    testWidgets('a Host without the capability never asks', (tester) async {
      final host = _Harness()..previewAuthors = true;
      final module = await pumpUpper(tester, host);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(renewals(host), 0);
      module.communication.reset();
      await tester.pump();
    });

    testWidgets('the relay saying yes renews with one exact request', (
      tester,
    ) async {
      final host = _Harness()..previewAuthors = true;
      support(host);
      final module = await pumpUpper(tester, host);
      expect(renewals(host), greaterThan(0));
      final request = host.requests.lastWhere(
        (row) => row.payload['action'] == 'chatAuthorRenewal',
      );
      expect(request.payload.keys.toSet(), {
        'schemaVersion',
        'sourceRef',
        'action',
        'targetRef',
        'after',
        'limit',
        'observeMessageRefs',
      });
      expect(request.payload['limit'], inInclusiveRange(1, 8));
      expect(host.actions.where((a) => a == 'markChatRead'), isEmpty);
      module.communication.reset();
      await tester.pump();
    });
  });

  test('chat renewal is one exact request on the real bridge', () async {
    final host = _Harness()..previewAuthors = false;
    host.session.acceptHostCapabilities([
      'officialFleet.communication',
      'officialFleet.communication.authorIdentities',
      'officialFleet.communication.chatAuthorRenewal',
    ]);
    final adapter = host.adapter();
    addTearDown(host.close);
    addTearDown(adapter.close);
    final context = await adapter.open();
    final port = adapter as CommunityChatAuthorRenewalPort;
    expect(port.chatAuthorRenewalAvailable, isTrue);
    final page = await port.renewChatAuthors(
      context.targetRef,
      after: 0,
      observeMessageRefs: const [],
    );
    expect(page.targetRef, context.targetRef);
    final request = host.requests.lastWhere(
      (row) => row.payload['action'] == 'chatAuthorRenewal',
    );
    expect(request.payload.keys.toSet(), {
      'schemaVersion',
      'sourceRef',
      'action',
      'targetRef',
      'surface',
      'after',
      'limit',
      'observeMessageRefs',
    });
    expect(request.payload['surface'], 'chat');
    expect(host.actions.where((a) => a == 'chat'), isEmpty);
    expect(host.actions.where((a) => a == 'markChatRead'), isEmpty);
  });

  test('without the capability the chat renewal is not offered', () async {
    final host = _Harness()..previewAuthors = false;
    host.session.acceptHostCapabilities([
      'officialFleet.communication',
      'officialFleet.communication.authorIdentities',
    ]);
    final adapter = host.adapter();
    addTearDown(host.close);
    addTearDown(adapter.close);
    await adapter.open();
    expect(
      (adapter as CommunityChatAuthorRenewalPort).chatAuthorRenewalAvailable,
      isFalse,
    );
  });

  testWidgets('a short window keeps the plain rail without a preview', (
    tester,
  ) async {
    final host = _Harness();
    final module = await pumpUpper(
      tester,
      host,
      window: const Size(1084, 744),
    );
    expect(tile, findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('the announce shortcut appears and leads to the activity page', (
    tester,
  ) async {
    final port = _AlignedManagement();
    final host = _Harness();
    final module = await pumpUpper(tester, host, management: port);
    expect(port.editorReads, 1);
    expect(announce, findsOneWidget);
    await tester.tap(announce);
    await tester.pumpAndSettle();
    expect(find.text('舰队活动'), findsOneWidget);
    final create = find.byKey(
      const ValueKey('community-announcement-create-entry'),
    );
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('announcement-title')),
      findsOneWidget,
      reason: 'It opens straight into a new announcement.',
    );
    expect(port.managed, isEmpty, reason: 'Opening it writes nothing.');
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('a viewer who may not manage sees the page without publishing', (
    tester,
  ) async {
    final port = _AlignedManagement()..editorFailure = true;
    final host = _Harness();
    final module = await pumpUpper(tester, host, management: port);
    await tester.tap(find.byKey(const Key('official-fleet-tab-broadcasts')));
    await tester.pumpAndSettle();
    expect(find.text('舰队活动'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('community-announcement-history-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('community-announcement-create-entry')),
      findsNothing,
    );
    expect(find.byKey(const Key('official-fleet-rally-start')), findsNothing);
    expect(find.textContaining('即将推出'), findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('a refused editor hides the shortcut, one read per open', (
    tester,
  ) async {
    final port = _AlignedManagement()..editorFailure = true;
    final host = _Harness();
    final module = await pumpUpper(tester, host, management: port);
    expect(port.editorReads, 1);
    expect(announce, findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(port.editorReads, 1, reason: 'No retry loop while nothing changes.');
    await module.communication.refresh('officialFleet:7');
    await tester.pumpAndSettle();
    expect(port.editorReads, 2, reason: 'A verified reopen asks once more.');
    expect(announce, findsNothing);
    expect(tester.takeException(), isNull);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('a passing editor failure recovers on the next verified open', (
    tester,
  ) async {
    final port = _AlignedManagement()..transientFailure = true;
    final host = _Harness();
    final module = await pumpUpper(tester, host, management: port);
    expect(announce, findsNothing);
    port.transientFailure = false;
    await module.communication.refresh('officialFleet:7');
    await tester.pumpAndSettle();
    expect(port.editorReads, 2);
    expect(announce, findsOneWidget);
    module.communication.reset();
    await tester.pump();
  });

  testWidgets('a Host without management is never asked for the editor', (
    tester,
  ) async {
    final port = _AlignedManagement()..managementAvailable = false;
    final host = _Harness();
    final module = await pumpUpper(tester, host, management: port);
    expect(port.editorReads, 0);
    expect(announce, findsNothing);
    module.communication.reset();
    await tester.pump();
  });
  test(
    'official adapter reuses wire models through only its scoped command',
    () async {
      final host = _Harness();
      addTearDown(host.close);
      final adapter = host.adapter();
      addTearDown(adapter.close);
      final context = await adapter.open();
      expect(context.targetRef, 'a' * 32);
      expect(adapter, isNot(isA<CommunityAnnouncementWritePort>()));
      expect(adapter, isNot(isA<CommunitiesPort>()));
      expect(
        (await adapter.readAnnouncements(context.targetRef)).canManage,
        isFalse,
      );
      final history = await adapter.readChat(context.targetRef);
      expect(history.messages.single.text, 'Message 1');
      expect(host.actions, ['open', 'announcements', 'chat']);
      final intent = CommunityChatSendIntent(
        targetRef: context.targetRef,
        requestId: 'e' * 32,
        text: 'Hello',
      );
      expect((await adapter.sendChat(intent)).status, 'accepted');
      expect(
        (await adapter.markChatRead(
          context.targetRef,
          history.messages.single,
        )).status,
        'accepted',
      );
      await adapter.readChatDetail(
        context.targetRef,
        history.messages.single.messageRef,
        0,
        null,
      );
      await adapter.readAnnouncementDetail(
        context.targetRef,
        'b' * 32,
        0,
        null,
      );
      expect(
        host.requests.where(
          (request) => request.name.startsWith('communities.'),
        ),
        isEmpty,
      );
      expect(
        host.requests
            .where((request) => request.name == 'officialFleet.communication')
            .every(
              (request) =>
                  request.payload['sourceRef'] == 'officialFleet:7' &&
                  request.accountContext?.subject == 'synthetic-viewer',
            ),
        isTrue,
      );
    },
  );

  test('service read-only capability prevents a send', () async {
    final host = _Harness()..canSend = false;
    final adapter = host.adapter();
    addTearDown(host.close);
    addTearDown(adapter.close);
    await adapter.open();
    expect(adapter.chatAvailable, isTrue);
    expect(adapter.chatSendAvailable, isFalse);
    expect(
      (await adapter.sendChat(
        CommunityChatSendIntent(
          targetRef: 'a' * 32,
          requestId: 'e' * 32,
          text: 'Hello',
        ),
      )).status,
      'rejected',
    );
    expect(host.actions, ['open']);
    host.canManage = true;
    await expectLater(
      adapter.readAnnouncements('a' * 32),
      throwsA(isA<CommunityFailure>()),
    );
  });

  test(
    'malformed activity capability cannot partially admit communication',
    () async {
      final host = _Harness()..officialActivity = 'true';
      final adapter = host.adapter();
      addTearDown(host.close);
      addTearDown(adapter.close);
      await expectLater(adapter.open(), throwsA(isA<CommunityFailure>()));
      expect(adapter.chatAvailable, isFalse);
      expect(adapter.chatSendAvailable, isFalse);
      expect(adapter.chatReadReceiptsAvailable, isFalse);
    },
  );

  test(
    'wrong fleet response is rejected and account change cancels late reads',
    () async {
      final host = _Harness()..wrongFleet = true;
      final adapter = host.adapter();
      addTearDown(host.close);
      addTearDown(adapter.close);
      await expectLater(adapter.open(), throwsA(isA<CommunityFailure>()));
      expect(adapter.chatAvailable, isFalse);
      host.wrongFleet = false;
      await adapter.open();
      host.hold = true;
      final pending = adapter.readChat('a' * 32);
      final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
      await host.held.future;
      await host.accountChanged();
      await rejected;
    },
  );

  test(
    'reset rejects an unfinished open instead of exposing the old viewer',
    () async {
      final host = _Harness()..hold = true;
      addTearDown(host.close);
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(communication.dispose);
      final opening = communication.open('officialFleet:7');
      await host.held.future;
      communication.reset();
      await opening;
      expect(communication.chatAvailable, isFalse);
      expect(communication.announcementsAvailable, isFalse);
    },
  );

  test(
    'a newer failed identity read fences a pending communication revalidation',
    () async {
      final host = _Harness();
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      final verified = communication.lastVerifiedAtUtc;
      communication.retainReadOnly();
      host.hold = true;
      final pending = communication.refresh('officialFleet:7');
      await host.heldOpen.future;
      final request = host.requests.lastWhere(
        (r) => r.payload['action'] == 'open',
      );
      communication.retainReadOnly();
      await host.releaseOpen(request);
      await pending;
      expect(communication.readOnly, isTrue);
      expect(communication.isRefreshing, isFalse);
      expect(communication.lastVerifiedAtUtc, verified);
      host.hold = false;
      await communication.refresh('officialFleet:7');
      expect(communication.readOnly, isFalse);
    },
  );

  test('fresh capability loss discards inaccessible chat instead of reviving it later', () async {
    final host = _Harness();
    final communication = OrganizationCommunication((_) => host.adapter());
    addTearDown(host.close);
    addTearDown(communication.dispose);
    await communication.open('officialFleet:7');
    final old =
        (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
    old.updateDraft('Scoped draft');
    host.canChat = false;
    await communication.refresh('officialFleet:7');
    expect(communication.chatAvailable, isFalse);
    host.canChat = true;
    await communication.refresh('officialFleet:7');
    final fresh =
        (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
    expect(identical(fresh, old), isFalse);
    expect(fresh.draft, isEmpty);
  });
  test(
    'verified reference renewal keeps a protected draft and loaded history',
    () async {
      final host = _Harness();
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      final old =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await old.enter();
      old.updateDraft('Scoped draft');
      final history = old.messages;
      host.targetRef = 'b' * 32;
      await communication.refresh('officialFleet:7');
      final renewed =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      expect(renewed, same(old));
      expect(renewed.targetRef, 'b' * 32);
      expect(renewed.draft, 'Scoped draft');
      expect(renewed.messages, history);
    },
  );

  testWidgets(
    'official mode admission forwards activity and preserves same-scope drafts across revalidation',
    (tester) async {
      final host = _Harness()..unread = 1;
      final mode = _CommunicationMode();
      final communication = OrganizationCommunication(
        (_) => host.adapter(mode: mode),
      );
      addTearDown(host.close);
      addTearDown(mode.dispose);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 1);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.updateDraft('Same owner, same fleet');
      chat.setReadingContext(visible: true, foreground: true);
      expect(chat.canSubmit, isTrue);
      expect(chat.canAcknowledge, isTrue);
      final reads = host.actions.length;
      mode.setOnline(false);
      await tester.pumpAndSettle();
      expect(communication.readOnly, isTrue);
      expect(communication.chatUnreadCount, 0);
      expect(chat.draft, 'Same owner, same fleet');
      expect(chat.canSubmit, isFalse);
      expect(chat.canAcknowledge, isFalse);
      await communication.refreshReadback();
      await tester.pumpAndSettle();
      expect(
        host.actions.length,
        reads,
        reason: 'Offline reconciliation must not dispatch organization traffic',
      );
      host.hold = true;
      host.targetRef = 'b' * 32;
      mode.setOnline(true);
      await tester.pump();
      await host.held.future;
      expect(communication.readOnly, isTrue);
      final port =
          (communication.chat(onBack: () {}) as CommunityChatPanel).port;
      expect((port as CommunityChatSendPort).chatSendAvailable, isFalse);
      expect(port.chatReadReceiptsAvailable, isFalse);
      expect(chat.canSubmit, isFalse);
      expect(chat.canAcknowledge, isFalse);
      host.hold = false;
      await host.releaseOpen(
        host.requests.lastWhere((r) => r.payload['action'] == 'open'),
      );
      await tester.pumpAndSettle();
      expect(communication.readOnly, isFalse);
      expect(
        (communication.chat(onBack: () {}) as CommunityChatPanel).controller,
        same(chat),
      );
      expect(chat.draft, 'Same owner, same fleet');
      expect(chat.targetRef, 'b' * 32);
      expect(communication.chatUnreadCount, 1);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
        reason: 'GET reconciliation is never a receipt or a send retry',
      );
      communication.reset();
      await tester.pump();
    },
  );

  testWidgets(
    'mode interruption retains the original uncertain send and never replays it on reconnect',
    (tester) async {
      final host = _Harness();
      final mode = _CommunicationMode();
      final communication = OrganizationCommunication(
        (_) => host.adapter(mode: mode),
      );
      addTearDown(host.close);
      addTearDown(mode.dispose);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.updateDraft('One intentional message');
      host.hold = true;
      final pending = chat.submit();
      await tester.pump();
      expect(host.actions.where((a) => a == 'sendChat').length, 1);
      final intent = chat.localMessages.single.intent;
      chat.updateDraft('Later unsent draft');
      mode.setOnline(false);
      await tester.pumpAndSettle();
      await pending;
      expect(chat.localMessages.single.intent.requestId, intent.requestId);
      expect(chat.localMessages.single.state, 'unknown');
      expect(chat.draft, 'Later unsent draft');
      host.hold = false;
      mode.setOnline(true);
      await tester.pumpAndSettle();
      expect(chat.localMessages.single.intent.requestId, intent.requestId);
      expect(chat.draft, 'Later unsent draft');
      expect(host.actions.where((a) => a == 'sendChat').length, 1);
      communication.reset();
      await tester.pump();
    },
  );

  testWidgets(
    'default-off service failure clears unread but only definite loss destroys the conversation',
    (tester) async {
      final host = _Harness()..unread = 1;
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.updateDraft('Preserve through service outage');
      expect(communication.chatUnreadCount, 1);
      host.chatFailure = 'communities.unavailable';
      await chat.refresh();
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 0);
      expect(communication.readOnly, isTrue);
      expect(chat.draft, 'Preserve through service outage');
      host.chatFailure = null;
      await communication.refreshReadback();
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 1);
      expect(communication.readOnly, isFalse);
      host.chatFailure = 'communities.notAllowed';
      await communication.refreshReadback();
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 0);
      expect(communication.chatAvailable, isFalse);
      expect(chat.draft, isEmpty);
      expect(chat.messages, isEmpty);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'new identity failure during recovery history keeps admission paused',
    (tester) async {
      final host = _Harness();
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.updateDraft('Do not send until identity is verified again');
      host.chatFailure = 'communities.unavailable';
      await chat.refresh();
      await tester.pumpAndSettle();
      final verified = communication.lastVerifiedAtUtc;
      host.chatFailure = null;
      host.holdChat = true;
      final pending = communication.refreshReadback();
      await tester.pumpAndSettle();
      final held = host.requests.lastWhere(
        (r) => r.payload['action'] == 'chat',
      );
      expect(communication.readOnly, isTrue);
      expect(chat.canSubmit, isFalse);
      // A newer membership observation fails after context authorization but
      // before the retained controller receives its successful history read.
      communication.retainReadOnly();
      await host.releaseChat(held);
      await pending;
      await tester.pumpAndSettle();
      expect(communication.readOnly, isTrue);
      expect(chat.canSubmit, isFalse);
      expect(communication.lastVerifiedAtUtc, verified);
      expect(chat.draft, 'Do not send until identity is verified again');
      expect(communication.chatUnreadCount, 0);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
      communication.reset();
      await tester.pump();
    },
  );

  testWidgets(
    'fresh context cannot revive a conversation denied by the recovery history read',
    (tester) async {
      final host = _Harness()..unread = 1;
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.updateDraft('Private draft survives only transient failure');
      host.chatFailure = 'communities.unavailable';
      await chat.refresh();
      await tester.pumpAndSettle();
      expect(communication.readOnly, isTrue);
      expect(chat.draft, isNotEmpty);
      final opensBefore = host.actions.where((a) => a == 'open').length;
      final readsBefore = host.actions.where((a) => a == 'chat').length;
      // The context is fresh, but access is revoked before the retained
      // controller can complete its required successful recovery read.
      host.chatFailure = 'communities.notAllowed';
      await communication.refreshReadback();
      await tester.pumpAndSettle();
      expect(host.actions.where((a) => a == 'open').length, opensBefore + 1);
      expect(host.actions.where((a) => a == 'chat').length, readsBefore + 1);
      expect(communication.chatAvailable, isFalse);
      expect(communication.chatUnreadCount, 0);
      expect(chat.draft, isEmpty);
      expect(chat.messages, isEmpty);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'account invalidation fences a held unread result and never revives its badge',
    (tester) async {
      final host = _Harness()..unread = 1;
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 1);
      host.hold = true;
      await communication.refreshReadback();
      await tester.pump();
      final held = host.requests.lastWhere(
        (r) => r.payload['action'] == 'chat',
      );
      await host.accountChanged();
      await tester.pumpAndSettle();
      await host.releaseChat(held);
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 0);
      expect(communication.chatAvailable, isFalse);
      expect(host.actions.where((a) => a == 'markChatRead'), isEmpty);
    },
  );

  testWidgets(
    'old read and receipt replies remain retired after same-owner reconnect renews its target',
    (tester) async {
      final host = _Harness()..unread = 1;
      final mode = _CommunicationMode();
      final communication = OrganizationCommunication(
        (_) => host.adapter(mode: mode),
      );
      addTearDown(host.close);
      addTearDown(mode.dispose);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      await chat.enter();
      chat.setReadingContext(visible: true, foreground: true);
      chat.updateDraft('Retained across reference renewal');
      host.hold = true;
      final read = chat.refresh(silent: true);
      await tester.pump();
      final oldRead = host.requests.lastWhere(
        (r) => r.payload['action'] == 'chat',
      );
      final receipt = chat.acknowledgeVisible(chat.messages.single.messageRef);
      await tester.pump();
      final oldReceipt = host.requests.lastWhere(
        (r) => r.payload['action'] == 'markChatRead',
      );
      mode.setOnline(false);
      await tester.pumpAndSettle();
      await Future.wait([read, receipt]);
      expect(
        chat.confirmedReadThrough,
        0,
        reason: 'Canceled acknowledgement is not locally confirmed',
      );
      host.hold = false;
      host.targetRef = 'b' * 32;
      host.unread = 0;
      mode.setOnline(true);
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 0);
      expect(chat.targetRef, 'b' * 32);
      expect(chat.draft, 'Retained across reference renewal');
      await host.releaseChat(oldRead);
      await host.releaseReceipt(oldReceipt);
      await tester.pumpAndSettle();
      expect(communication.chatUnreadCount, 0);
      expect(chat.confirmedReadThrough, 0);
      expect(chat.draft, 'Retained across reference renewal');
      expect(
        (communication.chat(onBack: () {}) as CommunityChatPanel).controller,
        same(chat),
      );
      communication.reset();
      await tester.pump();
    },
  );

  test(
    'official facade forwards existing activity without exposing management',
    () async {
      final host = _Harness();
      final adapter = host.adapter();
      addTearDown(host.close);
      addTearDown(adapter.close);
      expect(adapter, isA<CommunityActivityPort>());
      expect(adapter, isA<OrganizationCommunicationConnectionPort>());
      expect(adapter, isNot(isA<CommunityAnnouncementWritePort>()));
      final source = adapter as CommunityActivityPort;
      final changed = source.workspaceChanges.first;
      await host.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.presentationChanged',
          sessionGeneration: 4,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await changed;
      expect(
        host.actions,
        isEmpty,
        reason: 'An invalidation hint is not a read or permission grant',
      );
    },
  );

  testWidgets(
    'hidden official workspace keeps app-owned unread reconciliation without a duplicate page poll',
    (tester) async {
      size(tester, const Size(1280, 900));
      final host = _Harness()..unread = 1;
      final initial = await InMemoryOfficialFleetAdapter.forReview(
        signedIn: true,
      ).read();
      final module = createOfficialFleetModule(
        _Identity(initial),
        UnavailableOfficialFleetOverviewAdapter(),
        InMemoryOfficialFleetMembersAdapter.forReview(),
        UnavailableOfficialFleetShipsAdapter(),
        communicationFactory: (_) => host.adapter(),
      );
      final active = ValueNotifier(true);
      addTearDown(host.close);
      addTearDown(module.dispose);
      addTearDown(active.dispose);
      await module.initialize();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en'),
          ),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (_, visible, _) => TickerMode(
                enabled: visible,
                child: OfficialFleetPage(module: module),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommunityChatPanel), findsNothing);
      expect(module.communication.chatUnreadCount, 1);
      active.value = false;
      await tester.pump();
      final reads = host.actions.where((a) => a == 'chat').length;
      host.unread = 0;
      await host.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.presentationChanged',
          sessionGeneration: 4,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        host.actions.where((a) => a == 'chat').length,
        reads + 1,
        reason: 'The app-owned unread reader remains active off-page',
      );
      expect(module.communication.attentionCount.value, 0);
      host.unread = 1;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(host.actions.where((a) => a == 'chat').length, reads + 2);
      expect(module.communication.attentionCount.value, 1);
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pumpAndSettle();
      expect(host.actions.where((a) => a == 'chat').length, reads + 2);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      module.communication.reset();
      await tester.pump();
    },
  );

  testWidgets(
    'official activity updates the fleet badge without any mounted fleet page and revocation clears it',
    (tester) async {
      final host = _Harness()..officialActivity = true;
      host.session.acceptHostCapabilities([
        'officialFleet.communication',
        'officialFleet.wait',
      ]);
      final initial = await InMemoryOfficialFleetAdapter.forReview(
        signedIn: true,
      ).read();
      final module = createOfficialFleetModule(
        _Identity(initial),
        UnavailableOfficialFleetOverviewAdapter(),
        InMemoryOfficialFleetMembersAdapter.forReview(),
        UnavailableOfficialFleetShipsAdapter(),
        communicationFactory: (_) => host.adapter(),
      );
      addTearDown(host.close);
      addTearDown(module.dispose);
      final taskbarEvents = <Map<String, Object?>>[];
      final taskbar = TaskbarAttentionBinding(
        scope: TaskbarAttentionScope(),
        changes: [module.communication.attentionCount],
        pending: () => module.communication.attentionCount.value > 0,
        reduceMotion: () => false,
        publish: (value) async => taskbarEvents.add(value),
      );
      addTearDown(taskbar.dispose);
      await module.initialize();
      await tester.pumpAndSettle();
      expect(find.byType(OfficialFleetPage), findsNothing);
      expect(
        host.activityWaits,
        hasLength(1),
        reason: 'The app-owned communication scope observes its real official wait off-page',
      );
      await host.releaseActivity(host.activityWaits.last, 0);
      await tester.pump(const Duration(milliseconds: 151));
      host.unread = 1;
      await host.releaseActivity(host.activityWaits.last, 1);
      await tester.pumpAndSettle();
      expect(module.communication.chatUnreadCount, 1);
      final feature = createOfficialFleetFeature(module);
      expect(feature.attentionCount, isNotNull);
      expect(feature.attentionCount!.value, 1);
      expect(taskbarEvents.last['pending'], isTrue);
      expect(
        host.actions.where((a) => a == 'markChatRead' || a == 'sendChat'),
        isEmpty,
      );
      size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en'),
          ),
          routes: {feature.route: feature.buildDestination},
          home: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                width: 180,
                child: ShellNavigationItem(
                  descriptor: feature,
                  mode: ShellLayoutMode.wide,
                  selected: false,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(feature.route),
                  onKeyboardPressed: () {},
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AttentionCount>(find.byType(AttentionCount)).count,
        1,
      );
      await tester.tap(find.byType(ShellNavigationItem));
      await tester.pumpAndSettle();
      expect(find.byType(OfficialFleetPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(OfficialFleetPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(OfficialFleetPage), findsNothing);
      await tester.pump(const Duration(milliseconds: 151));
      await host.releaseActivity(host.activityWaits.last, 2, denied: true);
      await tester.pumpAndSettle();
      expect(module.communication.chatUnreadCount, 0);
      expect(feature.attentionCount!.value, 0);
      expect(taskbarEvents.last['pending'], isFalse);
      expect(module.communication.chatAvailable, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final legacy in [
    (name: 'old Host', cap: false, relay: true),
    (name: 'old Relay', cap: true, relay: false),
  ]) {
    testWidgets('${legacy.name} explicitly uses the same off-page fallback', (
      tester,
    ) async {
      final host = _Harness()
        ..officialActivity = true
        ..activityFieldPresent = legacy.relay;
      host.session.acceptHostCapabilities([
        'officialFleet.communication',
        if (legacy.cap) 'officialFleet.wait',
      ]);
      final communication = OrganizationCommunication((_) => host.adapter());
      addTearDown(host.close);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      expect(host.activityWaits, isEmpty);
      final reads = host.actions.where((a) => a == 'chat').length;
      host.unread = 1;
      await tester.pump(const Duration(seconds: 14));
      expect(host.actions.where((a) => a == 'chat').length, reads);
      expect(communication.attentionCount.value, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(host.actions.where((a) => a == 'chat').length, reads + 1);
      expect(communication.attentionCount.value, 1);
      expect(host.activityWaits, isEmpty);
      expect(
        host.actions.where((a) => a == 'sendChat' || a == 'markChatRead'),
        isEmpty,
      );
      communication.reset();
      await tester.pump();
    });
  }

  testWidgets(
    'official wait cancellation and late hints cannot cross a fleet source',
    (tester) async {
      final first = _Harness()
        ..officialActivity = true
        ..unread = 1;
      final next = _Harness()
        ..officialActivity = true
        ..sourceRef = 'officialFleet:8';
      for (final host in [first, next]) {
        host.session.acceptHostCapabilities([
          'officialFleet.communication',
          'officialFleet.wait',
        ]);
        addTearDown(host.close);
      }
      final communication = OrganizationCommunication(
        (source) => (source == 'officialFleet:7' ? first : next).adapter(),
      );
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final oldWait = first.activityWaits.single;
      final old =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      old.updateDraft('Private to the first source');
      expect(communication.attentionCount.value, 1);
      await communication.open('officialFleet:8');
      await tester.pumpAndSettle();
      expect(communication.attentionCount.value, 0);
      expect(old.draft, isEmpty);
      final fresh =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      expect(fresh, isNot(same(old)));
      expect(fresh.draft, isEmpty);
      expect(
        first.requests.where(
          (request) =>
              request.name == 'bridge.cancel' &&
              request.payload['targetCorrelationId'] == oldWait.correlationId,
        ),
        hasLength(1),
      );
      final reads = next.actions.where((a) => a == 'chat').length;
      await first.releaseActivity(oldWait, 100);
      await tester.pumpAndSettle();
      expect(next.actions.where((a) => a == 'chat').length, reads);
      expect(communication.attentionCount.value, 0);
      expect(next.activityWaits.single.payload['sourceRef'], 'officialFleet:8');
      next.unread = 2;
      await next.releaseActivity(next.activityWaits.single, 1);
      await tester.pumpAndSettle();
      expect(communication.attentionCount.value, 2);
      communication.reset();
      await tester.pump();
    },
  );

  testWidgets(
    'offline retires the official wait and fresh context gates recovery',
    (tester) async {
      final host = _Harness()
        ..officialActivity = true
        ..unread = 1;
      host.session.acceptHostCapabilities([
        'officialFleet.communication',
        'officialFleet.wait',
      ]);
      final mode = _CommunicationMode();
      final communication = OrganizationCommunication(
        (_) => host.adapter(mode: mode),
      );
      addTearDown(host.close);
      addTearDown(mode.dispose);
      addTearDown(communication.dispose);
      await communication.open('officialFleet:7');
      await tester.pumpAndSettle();
      final oldWait = host.activityWaits.single;
      final chat =
          (communication.chat(onBack: () {}) as CommunityChatPanel).controller!;
      chat.updateDraft('Retain only for this verified owner');
      mode.setOnline(false);
      await tester.pumpAndSettle();
      expect(communication.attentionCount.value, 0);
      final requests = host.requests.length;
      host.unread = 2;
      await host.releaseActivity(oldWait, 100);
      await tester.pump(const Duration(seconds: 16));
      expect(host.requests.length, requests);
      expect(communication.attentionCount.value, 0);
      expect(
        host.requests.where(
          (request) =>
              request.name == 'bridge.cancel' &&
              request.payload['targetCorrelationId'] == oldWait.correlationId,
        ),
        hasLength(1),
      );
      host.hold = true;
      mode.setOnline(true);
      await tester.pumpAndSettle();
      expect(communication.readOnly, isTrue);
      expect(chat.canSubmit, isFalse);
      expect(chat.canAcknowledge, isFalse);
      await host.releaseActivity(host.activityWaits.last, 1);
      await tester.pumpAndSettle();
      expect(communication.attentionCount.value, 0);
      expect(communication.readOnly, isTrue);
      host.hold = false;
      await host.releaseOpen(
        host.requests.lastWhere((r) => r.payload['action'] == 'open'),
      );
      await tester.pumpAndSettle();
      expect(communication.readOnly, isFalse);
      expect(communication.attentionCount.value, 2);
      expect(chat.draft, 'Retain only for this verified owner');
      expect(
        host.actions.where((a) => a == 'sendChat' || a == 'markChatRead'),
        isEmpty,
      );
      communication.reset();
      await tester.pump();
    },
  );

  for (final viewport in [const Size(1280, 900), const Size(480, 900)]) {
    // One real controller must survive refresh and temporary read-only mode.
    testWidgets('same organization announcement and retained chat at $viewport', (
      tester,
    ) async {
      size(tester, viewport);
      final host = _Harness()..unread = 1;
      final initial = await InMemoryOfficialFleetAdapter.forReview(
        signedIn: true,
      ).read();
      final identity = _Identity(initial);
      final module = createOfficialFleetModule(
        identity,
        UnavailableOfficialFleetOverviewAdapter(),
        InMemoryOfficialFleetMembersAdapter.forReview(),
        UnavailableOfficialFleetShipsAdapter(),
        communicationFactory: (_) => host.adapter(),
      );
      addTearDown(host.close);
      addTearDown(module.dispose);
      await module.initialize();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(body: OfficialFleetPage(module: module)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The holo header shows the announcement unless the room is too small.
      final expand = find.byKey(const Key('official-fleet-header-expand'));
      if (expand.evaluate().isNotEmpty) {
        await tester.tap(expand);
        await tester.pumpAndSettle();
      }
      expect(find.byType(CommunityAnnouncementEntry), findsOneWidget);
      expect(find.textContaining('Announcement'), findsWidgets);
      expect(find.byType(AttentionCount), findsOneWidget);
      expect(
        tester.widget<AttentionCount>(find.byType(AttentionCount)).count,
        1,
      );
      expect(host.actions.where((a) => a == 'markChatRead'), isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('community-announcement-entry')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommunityAnnouncementsDialog), findsOneWidget);
      expect(find.byKey(const Key('announcement-create')), findsNothing);
      await tester.tap(find.byKey(const Key('announcement-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-channel')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityChatPanel), findsOneWidget);
      expect(find.text('Message 1'), findsOneWidget);
      for (final avatar in tester.widgetList<UserAvatarMenu>(
        find.byType(UserAvatarMenu),
      )) {
        expect(avatar.target, isNull);
      }
      final draft = find.descendant(
        of: find.byType(CommunityChatPanel),
        matching: find.byType(TextField),
      );
      await tester.enterText(draft, '舰队草稿');
      final scopedController = tester
          .widget<CommunityChatPanel>(find.byType(CommunityChatPanel))
          .controller;
      host.targetRef = 'b' * 32;
      await module.refresh();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      expect(
        tester
            .widget<CommunityChatPanel>(find.byType(CommunityChatPanel))
            .controller,
        same(scopedController),
      );
      expect(scopedController!.targetRef, 'b' * 32);
      host.targetRef = 'a' * 32;
      await module.refresh();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-channel')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      final previousPortOpens = host.actions
          .where((action) => action == 'open')
          .length;
      final draftElement = tester.element(draft);
      final originalDraftTop = tester.getTopLeft(draft);
      identity.pending = Completer<OfficialFleetSnapshot>();
      final refreshing = module.refresh();
      await tester.pumpAndSettle();
      expect(identical(tester.element(draft), draftElement), isTrue);
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      expect(tester.getTopLeft(draft), originalDraftTop);
      expect(
        find.byKey(const Key('official-fleet-refreshing')),
        findsOneWidget,
      );
      expect(find.text('正在同步，当前仍显示上次读取的数据。'), findsOneWidget);
      identity.pending!.complete(initial);
      await refreshing;
      identity.pending = null;
      await tester.pumpAndSettle();
      expect(identical(tester.element(draft), draftElement), isTrue);
      expect(tester.getTopLeft(draft), originalDraftTop);
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      expect(
        host.actions.where((action) => action == 'open').length,
        previousPortOpens + 1,
      );
      final chatModel = tester
          .widget<CommunityChatPanel>(find.byType(CommunityChatPanel))
          .controller!;
      identity.snapshot = const OfficialFleetSnapshot.unavailable(
        failureKey: 'officialFleet.error.transient',
        transientFailure: true,
      );
      await module.refresh();
      await tester.pumpAndSettle();
      expect(identical(tester.element(draft), draftElement), isTrue);
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      expect(module.communication.readOnly, isTrue);
      expect(chatModel.canSubmit, isFalse);
      expect(chatModel.canAcknowledge, isFalse);
      expect(find.textContaining('更新失败，仍显示'), findsOneWidget);
      host.canSend = false;
      identity.snapshot = initial;
      await module.refresh();
      await tester.pumpAndSettle();
      expect(module.communication.readOnly, isFalse);
      expect(
        tester
            .widget<CommunityChatPanel>(find.byType(CommunityChatPanel))
            .controller,
        same(chatModel),
      );
      expect(
        chatModel.canSubmit,
        isFalse,
        reason:
            'Fresh communication capabilities override cached send permission.',
      );
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      host.canSend = true;
      await module.refresh();
      await tester.pumpAndSettle();
      expect(chatModel.canSubmit, isTrue);
      identity.snapshot = const OfficialFleetSnapshot.unavailable(
        failureKey: 'officialFleet.error.unavailable',
      );
      await module.refresh();
      await tester.pumpAndSettle();
      // An unexplained failure right after a good read keeps the last view,
      // read only, instead of blanking it (user report 2026-10-29).
      expect(module.communication.readOnly, isTrue);
      expect(find.textContaining('更新失败，仍显示'), findsOneWidget);
      identity.snapshot = initial;
      await module.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-channel')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, '舰队草稿');
      expect(tester.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_FLEET_COMMUNICATION'] ==
          '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory(
            developmentFixturePath('StarBridge-Reviews/official-fleet-collaboration-20261014/screenshots'),
          );
          await output.create(recursive: true);
          await File('${output.path}/chat-${viewport.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      identity.snapshot = OfficialFleetSnapshot.notMember(
        freshness: OfficialFleetFreshness.live,
        observedAtUtc: DateTime.utc(2026, 10, 14),
      );
      await module.refresh();
      await tester.pumpAndSettle();
      identity.snapshot = initial;
      await module.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-channel')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
      await tester.enterText(draft, '另一个草稿');
      // Account changes invalidate the same controllers used by community chat.
      await host.accountChanged();
      await tester.pumpAndSettle();
      expect(find.byType(CommunityChatPanel), findsNothing);
      expect(module.communication.chatUnreadCount, 0);
      await module.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-tab-channel')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      module.communication.reset();
      await tester.pump();
    });
  }
}

const _renewalRef = 'c1111111111111111111111111111111';
const _renewalSender = 'd2222222222222222222222222222222';

final class _Harness {
  _Harness() {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(['officialFleet.communication']);
    subscription = host.incoming.listen((request) async {
      requests.add(request);
      const context = BridgeAccountContext(
        environment: 'development',
        authority: 'scm-development',
        subject: 'synthetic-viewer',
      );
      if (request.name == 'officialFleet.wait') {
        activityWaits.add(request);
        return;
      }
      final action = request.payload['action'];
      if (action == 'chat' && chatFailure != null) {
        await host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: context,
            payload: const {},
            status: 'error',
            error: BridgeErrorBody(
              code: chatFailure!,
              message: 'Synthetic read denial',
              retryable: false,
            ),
          ),
        );
        return;
      }
      if (action == 'markChatRead') unread = 0;
      if ((hold || holdChat && action == 'chat') &&
          request.name == 'officialFleet.communication') {
        if (!held.isCompleted) held.complete();
        if (action == 'open' && !heldOpen.isCompleted) heldOpen.complete();
        return;
      }
      // The real client may reconcile incrementally after a retained read
      // failure. Honor the existing cursor contract instead of returning the
      // same already-received sequence and manufacturing dataInvalid.
      final after = request.payload['after'] as int? ?? 0;
      final before = request.payload['before'] as int? ?? 0;
      final includeMessage = after < 1 && (before == 0 || before > 1);
      final payload = request.name == 'account.getCurrent'
          ? <String, Object?>{
              'schemaVersion': 1,
              'state': 'signedIn',
              'displayName': 'Fixture',
              'avatarUrl': null,
            }
          : switch (action) {
              'open' => <String, Object?>{
                'schemaVersion': 1,
                'sourceRef': wrongFleet ? 'officialFleet:8' : sourceRef,
                'targetRef': targetRef,
                'name': 'Fleet fixture',
                'announcementsAvailable': true,
                if (previewAuthors != null) ...{
                  'authorIdentitySchemaVersion': 1,
                  'previewAuthorsAvailable': previewAuthors,
                },
                'chatAvailable': canChat,
                'chatSendAvailable': canSend,
                'readReceiptsAvailable': true,
                if (activityFieldPresent) 'activityAvailable': officialActivity,
              },
              'announcements' => {
                ...announcementPage(),
                'canManage': canManage,
                'current': {
                  ...announcementRow(),
                  'author': announcementAuthor(hasAvatar: false),
                  'editor': announcementAuthor(hasAvatar: false),
                },
              },
              'chat' => <String, Object?>{
                'schemaVersion': 1,
                'targetRef': targetRef,
                'unreadCount': unread,
                'latestSequence': 1,
                'oldestSequence': includeMessage ? 1 : 0,
                'canSend': canSend,
                'hasOlder': false,
                'serverTime': '2026-10-14T00:00:00Z',
                'messages': includeMessage
                    ? page([1], latest: 1, unread: 0, older: false).messages
                          .map(
                            (message) => <String, Object?>{
                              'sequence': 1,
                              'messageRef': message.messageRef,
                              'senderRef': 'd' * 32,
                              'senderCallsign': 'Fixture pilot',
                              'senderGameId': '',
                              'senderRoleTitle': '',
                              'senderRoleColor': '#9DAAB3',
                              'text': message.text,
                              'createdAt': '2026-10-14T00:00:00Z',
                              'isSelf': false,
                              'hasAvatar': false,
                              'hasAttachment': false,
                            },
                          )
                          .toList()
                    : <Object?>[],
              },
              'chatAuthorRenewal' => <String, Object?>{
                'schemaVersion': 1,
                'targetRef': targetRef,
                'unreadCount': 0,
                'latestSequence': 1,
                'oldestSequence': 1,
                'canSend': false,
                'hasOlder': false,
                'serverTime': '2026-10-14T00:00:00Z',
                'authorIdentitySchemaVersion': 1,
                'authorRefreshRequired': false,
                'authorUpdates': <Object?>[],
                'messages': [
                  {
                    'sequence': 1,
                    'messageRef': _renewalRef,
                    'senderRef': _renewalSender,
                    'senderCallsign': 'Fixture pilot',
                    'senderGameId': '',
                    'senderRoleTitle': '',
                    'senderRoleColor': '#9DAAB3',
                    'text': 'Message 1',
                    'createdAt': '2026-10-14T00:00:00Z',
                    'isSelf': false,
                    'hasAvatar': false,
                    'avatarVersion': null,
                    'hasAttachment': false,
                    'authorIdentityState': 'visible',
                    'authorIdentityVersion': 'b' * 64,
                    'identityObservedAtUtc': DateTime.now().toUtc().toIso8601String(),
                    'identityValidUntilUtc': DateTime.now()
                        .toUtc()
                        .add(const Duration(seconds: 5))
                        .toIso8601String(),
                  },
                ],
              },
              'sendChat' => <String, Object?>{
                'schemaVersion': 1,
                'targetRef': request.payload['targetRef'],
                'requestId': request.payload['requestId'],
                'status': 'accepted',
                'sequence': 2,
              },
              'markChatRead' => <String, Object?>{
                'schemaVersion': 1,
                'targetRef': request.payload['targetRef'],
                'messageRef': request.payload['messageRef'],
                'status': 'accepted',
                'readThroughSequence': 1,
              },
              _ => <String, Object?>{'schemaVersion': 1},
            };
      await host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: context,
          payload: payload,
          status: 'ok',
        ),
      );
    });
  }
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  bool? previewAuthors;
  bool canSend = true,
      canManage = false,
      wrongFleet = false,
      hold = false,
      holdChat = false,
      canChat = true;
  String targetRef = 'a' * 32;
  int unread = 0;
  String? chatFailure;
  Object? officialActivity = false;
  bool activityFieldPresent = true;
  String sourceRef = 'officialFleet:7';
  final activityWaits = <BridgeEnvelope>[];
  Future<void> releaseActivity(
    BridgeEnvelope request,
    int version, {
    bool denied = false,
  }) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: request.accountContext,
      status: denied ? 'error' : 'ok',
      error: denied
          ? const BridgeErrorBody(
              code: 'communities.notAllowed',
              message: 'Synthetic revoked membership',
              retryable: false,
            )
          : null,
      payload: denied
          ? const {}
          : {
              'schemaVersion': 1,
              'sourceRef': sourceRef,
              'instance': 'a' * 32,
              'version': version,
              'chatEvents': true,
            },
    ),
  );
  final held = Completer<void>();
  final heldOpen = Completer<void>();
  final requests = <BridgeEnvelope>[];
  List<Object?> get actions => requests
      .where((request) => request.name == 'officialFleet.communication')
      .map((request) => request.payload['action'])
      .toList();
  OrganizationCommunicationPort adapter({ConnectionModeControl? mode}) =>
      createOfficialFleetCommunicationAdapter(
        session,
        sourceRef,
        connectionMode: mode,
      );
  Future<void> releaseChat(BridgeEnvelope request) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: request.accountContext,
      status: 'ok',
      payload: {
        'schemaVersion': 1,
        'targetRef': request.payload['targetRef'],
        'unreadCount': 1,
        'latestSequence': 1,
        'oldestSequence': 0,
        'canSend': true,
        'hasOlder': false,
        'serverTime': '2026-10-14T00:00:00Z',
        'messages': <Object?>[],
      },
    ),
  );
  Future<void> releaseReceipt(BridgeEnvelope request) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: request.accountContext,
      status: 'ok',
      payload: {
        'schemaVersion': 1,
        'targetRef': request.payload['targetRef'],
        'messageRef': request.payload['messageRef'],
        'status': 'accepted',
        'readThroughSequence': 1,
      },
    ),
  );
  Future<void> releaseOpen(BridgeEnvelope request) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: request.accountContext,
      status: 'ok',
      payload: {
        'schemaVersion': 1,
        'sourceRef': 'officialFleet:7',
        'targetRef': targetRef,
        'name': 'Fleet fixture',
        'announcementsAvailable': true,
        'chatAvailable': true,
        'chatSendAvailable': canSend,
        'readReceiptsAvailable': true,
        if (activityFieldPresent) 'activityAvailable': officialActivity,
      },
    ),
  );
  Future<void> accountChanged() => host.send(
    const BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 5,
      sequence: 1,
      payload: {'schemaVersion': 1},
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

final class _Identity implements OfficialFleetPort {
  _Identity(this.snapshot);
  OfficialFleetSnapshot snapshot;
  Completer<OfficialFleetSnapshot>? pending;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetSnapshot> read() async => pending?.future ?? snapshot;
  @override
  Future<void> close() async {}
}

final class _CommunicationMode extends ChangeNotifier
    implements ConnectionModeControl {
  bool _online = true;
  int _revision = 1;
  void setOnline(bool value) {
    _online = value;
    _revision++;
    notifyListeners();
  }

  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    scope: 'same-synthetic-owner',
    revision: _revision,
    state: _online
        ? ConnectionModeState.online
        : ConnectionModeState.unavailable,
  );
  @override
  bool get busy => false;
  @override
  bool get failed => !_online;
  @override
  bool get allowsOnlineTraffic => _online;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

/// An editor that matches the harness's current announcement, as the Host's
/// would for a viewer who may manage it.
final class _AlignedManagement extends FixtureManagementPort {
  bool transientFailure = false;
  @override
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef) async {
    editorReads++;
    if (editorFailure) throw const CommunityFailure('notAllowed');
    if (transientFailure) throw const CommunityFailure('unavailable');
    final row = announcementRow();
    return OrganizationAnnouncementEditor.parse({
      'schemaVersion': 1,
      'state': 'available',
      'sourceRef': sourceRef,
      'editRef': 'e' * 32,
      'revision': announcementPage()['revision'],
      'allowedActions': const ['publish', 'edit', 'withdraw'],
      'current': {
        'announcementRef': row['announcementRef'],
        'title': row['title'],
        'content': row['content'],
      },
    }, sourceRef);
  }
}
