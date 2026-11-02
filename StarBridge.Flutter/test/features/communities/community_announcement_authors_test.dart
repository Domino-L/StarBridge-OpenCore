import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_details.dart';

import '../friends/social_layout_test.dart' show app;

import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

import '../official_fleet/official_fleet_author_wire_test.dart'
    show AuthorWireHost, wire;

void main() {
  test('unnegotiated official announcements keep content and neutralize both people', () async {
    final host = AuthorWireHost(announcementWire: true);
    addTearDown(host.close);
    addTearDown(host.adapter.close);
    final context = await host.adapter.open();
    final raw = wire('ann-mixed-current');
    final current = raw['current'] as Map;
    expect((current['author'] as Map)['callsign'], 'Bridge wire-visible');
    expect((current['editor'] as Map)['identityState'], 'hidden');
    final page = await host.adapter.readAnnouncements(context.targetRef);
    expect(page.targetRef, raw['targetRef']);
    expect(page.revision, raw['revision']);
    expect(page.current!.title, current['title']);
    expect(page.current!.content, current['content']);
    expect(page.totalHistoryCount, raw['totalHistoryCount']);
    expect(page.history.length, (raw['history'] as List).length);
    expect(page.canManage, isFalse);
    expect(
      page.current!.author.callsign,
      isEmpty,
      reason: 'An old/unsupported official lane cannot reuse dynamic or persisted display names.',
    );
    expect(page.current!.editor.callsign, isEmpty);
    expect(page.current!.author.hasAvatar, isFalse);
    expect(page.current!.editor.hasAvatar, isFalse);
    expect(page.current!.author.gameId, isEmpty);
    expect(page.current!.author.roleTitle, isEmpty);
    final request = host.requests
        .where((request) => request.payload['action'] == 'announcements')
        .single;
    expect(request.payload.containsKey('authorIdentitySchemaVersion'), isFalse);
    expect(request.payload.containsKey('observeAnnouncementRefs'), isFalse);
  });

  test('unnegotiated official history people are neutral while community people stay unchanged', () async {
    // The 20-history response is the unchanged actual producer payload. Only
    // the independent open fixture's opaque target is aligned by AuthorWireHost.
    final raw = wire('host-max-ann');
    final originalHistory = raw['history'] as List;
    expect(originalHistory, hasLength(20));
    expect(raw['totalHistoryCount'], 41);
    expect(
      ((originalHistory.first as Map)['author'] as Map)['identityState'],
      'visible',
    );
    final official = AuthorWireHost(
      announcementWire: true,
      announcementFixture: 'host-max-ann',
    );
    addTearDown(official.close);
    addTearDown(official.adapter.close);
    final context = await official.adapter.open();
    final page = await official.adapter.readAnnouncements(context.targetRef);
    _expectContent(page, raw);
    expect(page.canManage, isFalse);
    for (final record in [?page.current, ...page.history]) {
      for (final person in [record.author, record.editor]) {
        expect(person.callsign, isEmpty);
        expect(person.gameId, isEmpty);
        expect(person.roleTitle, isEmpty);
        expect(person.hasAvatar, isFalse);
      }
    }
    final request = official.requests
        .where((request) => request.payload['action'] == 'announcements')
        .single;
    expect(request.payload.containsKey('authorIdentitySchemaVersion'), isFalse);
    expect(request.payload.containsKey('observeAnnouncementRefs'), isFalse);

    // Positive control through the production community adapter; no official
    // facade or new identity permission is substituted for its existing rules.
    final community = CommunityHarness(
      capabilities: [
        'communities.announcements',
        'communities.announcementDetail',
      ],
      responses: {'communities.announcements': raw},
    );
    addTearDown(community.close);
    final ordinary = await community.adapter.readAnnouncements(
      raw['targetRef'] as String,
    );
    _expectContent(ordinary, raw);
    final originalRecords = [
      raw['current'] as Map,
      ...originalHistory.cast<Map>(),
    ];
    final ordinaryRecords = [?ordinary.current, ...ordinary.history];
    for (var index = 0; index < originalRecords.length; index++) {
      final original = originalRecords[index];
      final actual = ordinaryRecords[index];
      for (final pair in [
        (actual.author, original['author'] as Map),
        (actual.editor, original['editor'] as Map),
      ]) {
        expect(pair.$1.callsign, pair.$2['callsign']);
        expect(pair.$1.gameId, pair.$2['gameId']);
        expect(pair.$1.roleTitle, pair.$2['roleTitle']);
        expect(pair.$1.roleColor, pair.$2['roleColor']);
        expect(pair.$1.hasAvatar, pair.$2['hasAvatar']);
        expect(pair.$1.memberRef, pair.$2['memberRef']);
      }
    }
  });

  test(
    'negotiated official announcement worker uses the typed author lane',
    () async {
      // Controlled future cap x open=1 composition, not the current Server's
      // default context 0. No request or response UTC timestamp is freshened.
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      final context = await host.adapter.open();
      final model = CommunityAnnouncementsController(
        host.adapter,
        context.targetRef,
        now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
      );
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.error, isNull);
      expect(model.page, isNotNull);
      _expectContent(model.page!, wire('ann-mixed-current'));
      expect(model.canManage, isFalse);
      final request = host.requests
          .where((request) => request.payload['action'] == 'announcements')
          .single;
      expect(
        request.payload['authorIdentitySchemaVersion'],
        1,
        reason: 'The existing controller must consume the negotiated optional author reader.',
      );
      expect(request.payload['observeAnnouncementRefs'], isEmpty);
      expect(model.page!.current!.author.callsign, 'Bridge wire-visible');
      expect(model.page!.current!.editor.callsign, isEmpty);
      expect(
        host.requests.where(
          (request) => {
            'sendChat',
            'markChatRead',
            'announcementDetail',
          }.contains(request.payload['action']),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'retained official announcement people are neutral in the first details frame',
    (tester) async {
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        holdActions: {'announcementDetail'},
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(entry.author.hasAvatar, isTrue);
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(model.history, hasLength(1));
        expect(model.canManage, isFalse);
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.byType(CommunityAnnouncementDetails), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Compilation, theme, localization and content layout must succeed before the privacy assertion.',
        );
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'An original observation is not admission to a newly visible announcement surface.',
        );
        expect(model.history, hasLength(1));
        expect(model.page!.current!.content, 'Authorized body');
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'current official announcement surface recovers only after its fresh author read',
    (tester) async {
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        holdActions: {'announcementDetail'},
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(1),
        );
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['targetRef'], context.targetRef);
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A pending original-worker read is not a completed surface observation.',
        );
        expect(model.loading, isTrue);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'The same surface must recover from the completed real typed read, not stay permanently neutral.',
        );
        final presented = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        expect(presented.entry.author.callsign, 'Bridge wire-visible');
        expect(
          presented.entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          presented.entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(presented.entry.editor.callsign, isEmpty);
        expect(presented.entry.editor.hasAvatar, isFalse);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, wire('ann-mixed-current'));
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'official announcement author expires without another read or content loss',
    (tester) async {
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        holdActions: {'announcementDetail'},
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        var now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(1),
        );
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['targetRef'], context.targetRef);
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A pending original-worker read is not a completed surface observation.',
        );
        expect(model.loading, isTrue);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'The same surface must recover from the completed real typed read, not stay permanently neutral.',
        );
        final presented = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        expect(presented.entry.author.callsign, 'Bridge wire-visible');
        expect(
          presented.entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          presented.entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(presented.entry.editor.callsign, isEmpty);
        expect(presented.entry.editor.hasAvatar, isFalse);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, wire('ann-mixed-current'));
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        final announcementReads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .length;
        final detailReads = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .length;
        expect(announcementReads, 2);
        expect(detailReads, 1);
        // Only the injected observation clock and fake elapsed time change.
        // The held original detail request has a 15-second transport deadline.
        now = DateTime.utc(2026, 10, 17, 12, 0, 6);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, wire('ann-mixed-current'));
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(announcementReads),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(detailReads),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'The original identity deadline must actively repaint this visible surface without another read.',
        );
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'official announcement author and editor retire at their independent original deadlines',
    (tester) async {
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: _staggeredAnnouncementDomainPage,
        holdActions: {'announcementDetail'},
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        var now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(1),
        );
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['targetRef'], context.targetRef);
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A pending original-worker read is not a completed surface observation.',
        );
        expect(model.loading, isTrue);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'The same surface must recover from the completed real typed read, not stay permanently neutral.',
        );
        final presented = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        expect(presented.entry.author.callsign, 'Bridge wire-visible');
        expect(
          presented.entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          presented.entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(presented.entry.editor.callsign, 'Bridge staggered-second');
        expect(find.textContaining('Bridge staggered-second'), findsOneWidget);
        expect(
          presented.entry.editor.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12, 0, 3),
        );
        expect(
          presented.entry.editor.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 8),
        );
        expect(
          presented.entry.author.identity!.validUntil!.difference(
            presented.entry.author.identity!.observedAt!,
          ),
          const Duration(seconds: 5),
        );
        expect(
          presented.entry.editor.identity!.validUntil!.difference(
            presented.entry.editor.identity!.observedAt!,
          ),
          const Duration(seconds: 5),
        );
        expect(presented.entry.editor.hasAvatar, isTrue);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, _staggeredAnnouncementDomainPage());
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        now = DateTime.utc(2026, 10, 17, 12, 0, 5);
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.textContaining('Bridge staggered-second'), findsOneWidget);
        now = DateTime.utc(2026, 10, 17, 12, 0, 8);
        await tester.pump(const Duration(seconds: 3));
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.textContaining('Bridge staggered-second'), findsNothing);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, _staggeredAnnouncementDomainPage());
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'expired official announcement proof stays neutral after the observation clock rolls back',
    (tester) async {
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        holdActions: {'announcementDetail'},
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        var now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(1),
        );
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['targetRef'], context.targetRef);
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A pending original-worker read is not a completed surface observation.',
        );
        expect(model.loading, isTrue);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'The same surface must recover from the completed real typed read, not stay permanently neutral.',
        );
        final presented = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        expect(presented.entry.author.callsign, 'Bridge wire-visible');
        expect(
          presented.entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          presented.entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(presented.entry.editor.callsign, isEmpty);
        expect(presented.entry.editor.hasAvatar, isFalse);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, wire('ann-mixed-current'));
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        final announcementReads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .length;
        final detailReads = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .length;
        expect(announcementReads, 2);
        expect(detailReads, 1);
        // Only the injected observation clock and fake elapsed time change.
        // The held original detail request has a 15-second transport deadline.
        now = DateTime.utc(2026, 10, 17, 12, 0, 6);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, wire('ann-mixed-current'));
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(announcementReads),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(detailReads),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'The original identity deadline must actively repaint this visible surface without another read.',
        );
        now = DateTime.utc(2026, 10, 17, 12, 0, 2);
        model.refreshTimeLabels();
        await tester.pump();
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A retired proof cannot reappear when a presentation-only repaint sees an earlier clock.',
        );
        final retired = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        expect(retired.entry.author.callsign, isEmpty);
        expect(retired.entry.author.identity!.state.name, 'unavailable');
        expect(find.text('Authorized body'), findsOneWidget);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(announcementReads),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(detailReads),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'retired announcement surface rejects its late read and original deadline callback',
    (tester) async {
      final heldActions = <String>{'announcementDetail'};
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        holdActions: heldActions,
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        var now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        Widget details() => app(
          SingleChildScrollView(
            child: CommunityAnnouncementDetails(model: model, entry: entry),
          ),
        );
        await tester.pumpWidget(details());
        await tester.idle();
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        host.holdNextAnnouncementRead();
        var lateReadDone = false;
        model.refresh(background: true).then((_) => lateReadDone = true);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        expect(lateReadDone, isFalse);
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpWidget(details());
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        // The old request already passed its admission gate. Only the new
        // surface's later original-worker read remains explicitly unresolved.
        heldActions.add('announcements');
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        expect(lateReadDone, isTrue);
        expect(
          find.textContaining('Bridge wire-visible'),
          findsNothing,
          reason: 'A valid but late old-surface response is not new-surface admission.',
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(4),
        );
        var notifications = 0;
        void changed() => notifications++;
        model.addListener(changed);
        try {
          now = DateTime.utc(2026, 10, 17, 12, 0, 6);
          await tester.pump(const Duration(seconds: 5));
          expect(
            notifications,
            0,
            reason: 'The retired surface deadline cannot publish into a replacement surface.',
          );
        } finally {
          model.removeListener(changed);
        }
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(4),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        // Only the original verified surface can read a typed avatar. Its
        // replacement still awaits fresh admission and must not read legacy data.
        final originalDetail = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .single
            .payload;
        expect(originalDetail['targetRef'], context.targetRef);
        expect(originalDetail['announcementRef'], entry.announcementRef);
        expect(originalDetail['authorIdentitySchemaVersion'], 1);
        expect(
          originalDetail['expectedAuthorIdentityVersion'],
          entry.author.identity!.version,
        );
        expect(
          originalDetail.containsKey('expectedEditorIdentityVersion'),
          isTrue,
        );
        expect(
          originalDetail['expectedEditorIdentityVersion'],
          entry.editor.identity!.version,
        );
        expect(originalDetail['offset'], 0);
        expect(originalDetail['version'], isNull);
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'ordinary community announcement people keep their existing presentation past official proof times',
    (tester) async {
      final raw = wire('ann-mixed-current');
      final host = CommunityHarness(
        capabilities: [
          'communities.announcements',
          'communities.announcementDetail',
        ],
        responses: {'communities.announcements': raw},
        holdNames: {'communities.announcementDetail'},
      );
      addTearDown(host.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        var now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          raw['targetRef'] as String,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        expect(entry.author.identity, isNull);
        expect(model.usesOfficialAuthorProjection, isFalse);
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        now = DateTime.utc(2026, 10, 17, 12, 0, 6);
        await tester.pump(const Duration(seconds: 5));
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, raw);
        expect(model.history, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.name == 'communities.announcements',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => request.name == 'communities.announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'communities.sendChat',
              'communities.markChatRead',
            }.contains(request.name),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'official announcement typed detail binds current people and decodes both producer avatars',
    (tester) async {
      // Controlled future cap x open=1, with an explicit typed-domain page.
      // Content/history are from ann-mixed-current; the independent detail's
      // opaque target/ref and its two unchanged people align this consumer.
      // The 37 actual producer/provenance files and all original UTCs stay intact.
      final raw = _typedAnnouncementDetailDomainPage();
      final detailWire = wire('ann-detail-hint-true');
      final wireAuthor = detailWire['author'] as Map;
      final wireEditor = detailWire['editor'] as Map;
      final images = jsonDecode(
        utf8.decode(base64Decode(detailWire['data'] as String)),
      ) as Map;
      final authorUri = images['authorAvatarImageData'] as String;
      final editorUri = images['editorAvatarImageData'] as String;
      final authorPng = base64Decode(authorUri.split(',').last);
      final editorPng = base64Decode(editorUri.split(',').last);
      expect(
        sha256.convert(utf8.encode(authorUri)).toString(),
        wireAuthor['avatarVersion'],
      );
      expect(
        sha256.convert(utf8.encode(editorUri)).toString(),
        wireEditor['avatarVersion'],
      );
      expect(
        sha256.convert(authorPng).toString(),
        '510dd2a22344e8b1d0498fc0cf297ab766fa6777f923a1bd21cc5e4c52992726',
      );
      expect(
        editorPng,
        orderedEquals(authorPng),
        reason: 'The actual producer uses the same synthetic PNG in two distinct person slots.',
      );
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: _typedAnnouncementDetailDomainPage,
        announcementDetailFixture: 'ann-detail-hint-true',
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        for (final person in [entry.author, entry.editor]) {
          expect(person.callsign, 'Bridge wire-visible');
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
        final fresh = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(fresh.entry.author.callsign, 'Bridge wire-visible');
        expect(fresh.entry.editor.callsign, 'Bridge wire-visible');
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        for (final person in [fresh.entry.author, fresh.entry.editor]) {
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'A fresh current surface, content and both actual identities must succeed before the typed-detail assertion.',
        );
        final details = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .toList();
        expect(
          details,
          hasLength(1),
          reason: 'Only the current admitted surface needs one detail read, not a neutral legacy read plus a second owner.',
        );
        final request = details.single.payload;
        expect(request['targetRef'], detailWire['targetRef']);
        expect(request['announcementRef'], detailWire['announcementRef']);
        expect(
          request['authorIdentitySchemaVersion'],
          1,
          reason: 'The original detail owner must consume its negotiated typed identity lane.',
        );
        expect(
          request['expectedAuthorIdentityVersion'],
          wireAuthor['identityVersion'],
        );
        expect(
          request['expectedEditorIdentityVersion'],
          wireEditor['identityVersion'],
        );
        expect(request['offset'], 0);
        expect(request['version'], isNull);
        expect(fresh.author, orderedEquals(authorPng));
        expect(fresh.editor, orderedEquals(editorPng));
        // Decode the unchanged producer PNG independently. This also drains real
        // engine image work without advancing the injected UTC/fake deadline.
        final expectedImage = (await tester.runAsync(
          () => decodeCommunityImage(authorPng, 96),
        ))!;
        try {
          final expectedPixels = (await tester.runAsync(
            () => expectedImage.toByteData(),
          ))!;
          final imageFinder = find.descendant(
            of: bodyFinder,
            matching: find.byType(RawImage),
          );
          for (
            var attempt = 0;
            attempt < 8 && imageFinder.evaluate().length < 2;
            attempt++
          ) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
          }
          expect(
            imageFinder,
            findsNWidgets(2),
            reason: 'Both person slots must actually decode, not merely retain data URI strings.',
          );
          for (final image in tester.widgetList<RawImage>(imageFinder)) {
            expect(image.image, isNotNull);
            expect(image.image!.width, expectedImage.width);
            expect(image.image!.height, expectedImage.height);
            final pixels = (await tester.runAsync(
              () => image.image!.toByteData(),
            ))!;
            expect(
              pixels.buffer.asUint8List(),
              orderedEquals(expectedPixels.buffer.asUint8List()),
            );
          }
        } finally {
          expectedImage.dispose();
        }
        _expectContent(model.page!, raw);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'official announcement retirement clears only its local person bytes without another detail read',
    (tester) async {
      // Controlled future cap x open=1, with an explicit typed-domain page.
      // Content/history are from ann-mixed-current; the independent detail's
      // opaque target/ref and its two unchanged people align this consumer.
      // The 37 actual producer/provenance files and all original UTCs stay intact.
      var domainPage = _typedAnnouncementDetailDomainPage();
      final raw = domainPage;
      final detailWire = wire('ann-detail-hint-true');
      final wireAuthor = detailWire['author'] as Map;
      final wireEditor = detailWire['editor'] as Map;
      final images = jsonDecode(
        utf8.decode(base64Decode(detailWire['data'] as String)),
      ) as Map;
      final authorUri = images['authorAvatarImageData'] as String;
      final editorUri = images['editorAvatarImageData'] as String;
      final authorPng = base64Decode(authorUri.split(',').last);
      final editorPng = base64Decode(editorUri.split(',').last);
      expect(
        sha256.convert(utf8.encode(authorUri)).toString(),
        wireAuthor['avatarVersion'],
      );
      expect(
        sha256.convert(utf8.encode(editorUri)).toString(),
        wireEditor['avatarVersion'],
      );
      expect(
        sha256.convert(authorPng).toString(),
        '510dd2a22344e8b1d0498fc0cf297ab766fa6777f923a1bd21cc5e4c52992726',
      );
      expect(
        editorPng,
        orderedEquals(authorPng),
        reason: 'The actual producer uses the same synthetic PNG in two distinct person slots.',
      );
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: () => domainPage,
        announcementDetailFixture: 'ann-detail-hint-true',
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        for (final person in [entry.author, entry.editor]) {
          expect(person.callsign, 'Bridge wire-visible');
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
        final fresh = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(fresh.entry.author.callsign, 'Bridge wire-visible');
        expect(fresh.entry.editor.callsign, 'Bridge wire-visible');
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        for (final person in [fresh.entry.author, fresh.entry.editor]) {
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'A fresh current surface, content and both actual identities must succeed before the typed-detail assertion.',
        );
        final details = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .toList();
        expect(
          details,
          hasLength(1),
          reason: 'Only the current admitted surface needs one detail read, not a neutral legacy read plus a second owner.',
        );
        final request = details.single.payload;
        expect(request['targetRef'], detailWire['targetRef']);
        expect(request['announcementRef'], detailWire['announcementRef']);
        expect(
          request['authorIdentitySchemaVersion'],
          1,
          reason: 'The original detail owner must consume its negotiated typed identity lane.',
        );
        expect(
          request['expectedAuthorIdentityVersion'],
          wireAuthor['identityVersion'],
        );
        expect(
          request['expectedEditorIdentityVersion'],
          wireEditor['identityVersion'],
        );
        expect(request['offset'], 0);
        expect(request['version'], isNull);
        expect(fresh.author, orderedEquals(authorPng));
        expect(fresh.editor, orderedEquals(editorPng));
        // Decode the unchanged producer PNG independently. This also drains real
        // engine image work without advancing the injected UTC/fake deadline.
        final expectedImage = (await tester.runAsync(
          () => decodeCommunityImage(authorPng, 96),
        ))!;
        try {
          final expectedPixels = (await tester.runAsync(
            () => expectedImage.toByteData(),
          ))!;
          final imageFinder = find.descendant(
            of: bodyFinder,
            matching: find.byType(RawImage),
          );
          for (
            var attempt = 0;
            attempt < 8 && imageFinder.evaluate().length < 2;
            attempt++
          ) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
          }
          expect(
            imageFinder,
            findsNWidgets(2),
            reason: 'Both person slots must actually decode, not merely retain data URI strings.',
          );
          for (final image in tester.widgetList<RawImage>(imageFinder)) {
            expect(image.image, isNotNull);
            expect(image.image!.width, expectedImage.width);
            expect(image.image!.height, expectedImage.height);
            final pixels = (await tester.runAsync(
              () => image.image!.toByteData(),
            ))!;
            expect(
              pixels.buffer.asUint8List(),
              orderedEquals(expectedPixels.buffer.asUint8List()),
            );
          }
        } finally {
          expectedImage.dispose();
        }
        final state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        expect(state.author, orderedEquals(authorPng));
        expect(state.editor, orderedEquals(editorPng));
        final retainedEditorBytes = state.editor;
        final announcementReads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .length;
        final detailReads = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .length;
        expect(announcementReads, 2);
        expect(detailReads, 1);
        // Explicit test-only privacy change; not a producer response or new UTC.
        // The editor's original visible observation00->05 remains unchanged.
        final current = Map<String, Object?>.from(raw['current'] as Map);
        final beforeAuthor = Map<String, Object?>.from(
          current['author'] as Map,
        );
        domainPage = {
          ...raw,
          'current': {
            ...current,
            'author': {
              ...beforeAuthor,
              'callsign': '',
              'gameId': '',
              'roleTitle': '',
              'roleColor': '#9DAAB3',
              'hasAvatar': false,
              'avatarVersion': null,
              'identityState': 'hidden',
              'identityVersion': null,
              'identityObservedAtUtc': null,
              'identityValidUntilUtc': null,
            },
          },
        };
        await model.refresh(background: true);
        await tester.idle();
        await tester.pump();
        expect(model.error, isNull);
        final retired = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(retired.entry.author.callsign, isEmpty);
        expect(retired.entry.author.identity!.state.name, 'hidden');
        expect(retired.author, isNull);
        expect(retired.entry.editor.callsign, 'Bridge wire-visible');
        expect(retired.editor, orderedEquals(editorPng));
        expect(
          retired.entry.editor.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          retired.entry.editor.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(
          find.descendant(of: bodyFinder, matching: find.byType(RawImage)),
          findsOneWidget,
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(announcementReads + 1),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(detailReads),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Privacy/source fixture and existing pixel retirement must succeed before checking local byte ownership.',
        );
        expect(
          state.author,
          isNull,
          reason: 'A retired author must release the widget-owned Uint8List, not only pass null to the visible Body.',
        );
        expect(
          state.editor,
          same(retainedEditorBytes),
          reason: 'Retiring one person must retain the other original avatar without another detail read.',
        );
        model.refreshTimeLabels();
        await tester.pump();
        expect(state.author, isNull);
        expect(state.editor, same(retainedEditorBytes));
        expect(
          find.descendant(of: bodyFinder, matching: find.byType(RawImage)),
          findsOneWidget,
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(detailReads),
        );
        _expectContent(model.page!, raw);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(3),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'retired official announcement pixels cannot be stored by a late detail completion',
    (tester) async {
      // This controls a real completion boundary, not a synthetic success:
      // the held response is the unchanged actual ann-detail-hint-true wire.
      final raw = _typedAnnouncementDetailDomainPage();
      final detailWire = wire('ann-detail-hint-true');
      final images = jsonDecode(
        utf8.decode(base64Decode(detailWire['data'] as String)),
      ) as Map;
      for (final key in ['authorAvatarImageData', 'editorAvatarImageData']) {
        final uri = images[key] as String;
        expect(
          sha256.convert(utf8.encode(uri)).toString(),
          'dc6cb7edc1e309bc85ce94ac4e1d8a0895a2b978ebddb782a27df5c9689d399c',
        );
        expect(
          sha256.convert(base64Decode(uri.split(',').last)).toString(),
          '510dd2a22344e8b1d0498fc0cf297ab766fa6777f923a1bd21cc5e4c52992726',
        );
      }
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: _typedAnnouncementDetailDomainPage,
        announcementDetailFixture: 'ann-detail-hint-true',
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      VoidCallback? cleanupObserver;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        if (cleanupObserver != null) {
          cleanupModel?.removeListener(cleanupObserver);
        }
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        host.holdNextAnnouncementRead();
        host.holdNextAnnouncementDetail();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
        final state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        final authorPort =
            host.adapter as CommunityAnnouncementAuthorProjectionPort;
        expect(host.announcementDetailReadHeld, isTrue);
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        expect(state.loading, isTrue);
        expect(state.author, isNull);
        expect(state.editor, isNull);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        final presented = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        for (final person in [presented.entry.author, presented.entry.editor]) {
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        final detailRequest = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .single;
        expect(detailRequest.payload['authorIdentitySchemaVersion'], 1);
        expect(
          detailRequest.payload['expectedAuthorIdentityVersion'],
          (detailWire['author'] as Map)['identityVersion'],
        );
        expect(
          detailRequest.payload['expectedEditorIdentityVersion'],
          (detailWire['editor'] as Map)['identityVersion'],
        );
        expect(authorPort.authorIdentitiesAvailable, isTrue);
        var armed = true, completionRetirements = 0;
        final stages = <String>['fresh-surface', 'actual-typed-detail-held'];
        void retireAtCompletedDetailNotification() {
          if (!armed) return;
          armed = false;
          completionRetirements++;
          stages.add('model-completion-before-widget-store');
          // With this actual all-valid metadata no optional-person narrowing
          // notifies. The original Controller.detail completion notify occurs
          // after its assembler/cache checks and before returning to this Widget.
          expect(host.announcementDetailReadHeld, isFalse);
          expect(model.loading, isFalse);
          expect(model.error, isNull);
          expect(state.loading, isTrue);
          expect(state.author, isNull);
          expect(state.editor, isNull);
          expect(authorPort.authorIdentitiesAvailable, isTrue);
          host.session.acceptHostCapabilities(['officialFleet.communication']);
          stages.add('cap-withdrawn-before-await-continuation');
          expect(
            host.session.hostCapabilities.contains(
              'officialFleet.communication.authorIdentities',
            ),
            isFalse,
          );
          expect(authorPort.authorIdentitiesAvailable, isFalse);
        }

        cleanupObserver = retireAtCompletedDetailNotification;
        model.addListener(retireAtCompletedDetailNotification);
        stages.add('release-unchanged-actual-detail');
        host.releaseAnnouncementDetail();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        stages.add('widget-continuation-observed');
        expect(completionRetirements, 1);
        expect(stages, [
          'fresh-surface',
          'actual-typed-detail-held',
          'release-unchanged-actual-detail',
          'model-completion-before-widget-store',
          'cap-withdrawn-before-await-continuation',
          'widget-continuation-observed',
        ]);
        expect(state.loading, isFalse);
        expect(
          state.failed,
          isFalse,
          reason: 'Retired optional people must not turn the authorized content into an image error.',
        );
        expect(
          state.author,
          isNull,
          reason: 'A late Widget continuation cannot store the old now-unlicensed author bytes.',
        );
        expect(state.editor, isNull);
        final retired = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(retired.author, isNull);
        expect(retired.editor, isNull);
        expect(retired.entry.author.callsign, isEmpty);
        expect(retired.entry.editor.callsign, isEmpty);
        expect(find.byType(RawImage), findsNothing);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, raw);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'official announcement pixels retire independently and stay retired after clock rollback',
    (tester) async {
      // Controlled future cap x open=1, with an explicit typed-domain page.
      // Content/history are from ann-mixed-current; the independent detail's
      // opaque target/ref and its two unchanged people align this consumer.
      // The 37 actual producer/provenance files and all original UTCs stay intact.
      final raw = _independentAnnouncementPixelPage();
      final detailWire = _independentAnnouncementPixelDetail();
      final wireAuthor = detailWire['author'] as Map;
      final wireEditor = detailWire['editor'] as Map;
      final images = jsonDecode(
        utf8.decode(base64Decode(detailWire['data'] as String)),
      ) as Map;
      final authorUri = images['authorAvatarImageData'] as String;
      final editorUri = images['editorAvatarImageData'] as String;
      final authorPng = base64Decode(authorUri.split(',').last);
      final editorPng = base64Decode(editorUri.split(',').last);
      expect(
        sha256.convert(utf8.encode(authorUri)).toString(),
        wireAuthor['avatarVersion'],
      );
      expect(
        sha256.convert(utf8.encode(editorUri)).toString(),
        wireEditor['avatarVersion'],
      );
      expect(
        sha256.convert(authorPng).toString(),
        '510dd2a22344e8b1d0498fc0cf297ab766fa6777f923a1bd21cc5e4c52992726',
      );
      expect(
        editorPng,
        orderedEquals(authorPng),
        reason: 'The actual producer uses the same synthetic PNG in two distinct person slots.',
      );
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: _independentAnnouncementPixelPage,
        announcementDetailFixture: 'ann-detail-hint-true',
        announcementDetailPage: _independentAnnouncementPixelDetail,
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        var now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        expect(entry.author.callsign, 'Bridge wire-visible');
        expect(
          entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(entry.editor.callsign, 'Bridge staggered-second');
        expect(
          entry.editor.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12, 0, 3),
        );
        expect(
          entry.editor.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 8),
        );
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
        final fresh = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(fresh.entry.author.callsign, 'Bridge wire-visible');
        expect(fresh.entry.editor.callsign, 'Bridge staggered-second');
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.textContaining('Bridge staggered-second'), findsOneWidget);
        expect(
          fresh.entry.author.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          fresh.entry.author.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(
          fresh.entry.editor.identity!.observedAt,
          DateTime.utc(2026, 10, 17, 12, 0, 3),
        );
        expect(
          fresh.entry.editor.identity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 8),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'A fresh current surface, content and both actual identities must succeed before the typed-detail assertion.',
        );
        final details = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .toList();
        expect(
          details,
          hasLength(1),
          reason: 'Only the current admitted surface needs one detail read, not a neutral legacy read plus a second owner.',
        );
        final request = details.single.payload;
        expect(request['targetRef'], detailWire['targetRef']);
        expect(request['announcementRef'], detailWire['announcementRef']);
        expect(
          request['authorIdentitySchemaVersion'],
          1,
          reason: 'The original detail owner must consume its negotiated typed identity lane.',
        );
        expect(
          request['expectedAuthorIdentityVersion'],
          wireAuthor['identityVersion'],
        );
        expect(
          request['expectedEditorIdentityVersion'],
          wireEditor['identityVersion'],
        );
        expect(request['offset'], 0);
        expect(request['version'], isNull);
        expect(fresh.author, orderedEquals(authorPng));
        expect(fresh.editor, orderedEquals(editorPng));
        // Decode the unchanged producer PNG independently. This also drains real
        // engine image work without advancing the injected UTC/fake deadline.
        final expectedImage = (await tester.runAsync(
          () => decodeCommunityImage(authorPng, 96),
        ))!;
        try {
          final expectedPixels = (await tester.runAsync(
            () => expectedImage.toByteData(),
          ))!;
          final imageFinder = find.descendant(
            of: bodyFinder,
            matching: find.byType(RawImage),
          );
          for (
            var attempt = 0;
            attempt < 8 && imageFinder.evaluate().length < 2;
            attempt++
          ) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
          }
          expect(
            imageFinder,
            findsNWidgets(2),
            reason: 'Both person slots must actually decode, not merely retain data URI strings.',
          );
          for (final image in tester.widgetList<RawImage>(imageFinder)) {
            expect(image.image, isNotNull);
            expect(image.image!.width, expectedImage.width);
            expect(image.image!.height, expectedImage.height);
            final pixels = (await tester.runAsync(
              () => image.image!.toByteData(),
            ))!;
            expect(
              pixels.buffer.asUint8List(),
              orderedEquals(expectedPixels.buffer.asUint8List()),
            );
          }
        } finally {
          expectedImage.dispose();
        }
        final state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        expect(state.author, orderedEquals(authorPng));
        expect(state.editor, orderedEquals(editorPng));
        final retainedEditor = state.editor;
        now = DateTime.utc(2026, 10, 17, 12, 0, 5);
        await tester.pump(const Duration(seconds: 1));
        expect(state.author, isNull);
        expect(state.editor, same(retainedEditor));
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.textContaining('Bridge staggered-second'), findsOneWidget);
        expect(
          find.descendant(of: bodyFinder, matching: find.byType(RawImage)),
          findsOneWidget,
        );
        now = DateTime.utc(2026, 10, 17, 12, 0, 8);
        await tester.pump(const Duration(seconds: 3));
        expect(state.author, isNull);
        expect(state.editor, isNull);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Bridge staggered-second'), findsNothing);
        now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        model.refreshTimeLabels();
        await tester.pump();
        expect(state.author, isNull);
        expect(state.editor, isNull);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.textContaining('Bridge staggered-second'), findsNothing);
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, raw);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(2),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'loaded official announcement people require new surface and capability admission',
    (tester) async {
      // Controlled future cap x open=1, with an explicit typed-domain page.
      // Content/history are from ann-mixed-current; the independent detail's
      // opaque target/ref and its two unchanged people align this consumer.
      // The 37 actual producer/provenance files and all original UTCs stay intact.
      final raw = _typedAnnouncementDetailDomainPage();
      final detailWire = wire('ann-detail-hint-true');
      final wireAuthor = detailWire['author'] as Map;
      final wireEditor = detailWire['editor'] as Map;
      final images = jsonDecode(
        utf8.decode(base64Decode(detailWire['data'] as String)),
      ) as Map;
      final authorUri = images['authorAvatarImageData'] as String;
      final editorUri = images['editorAvatarImageData'] as String;
      final authorPng = base64Decode(authorUri.split(',').last);
      final editorPng = base64Decode(editorUri.split(',').last);
      expect(
        sha256.convert(utf8.encode(authorUri)).toString(),
        wireAuthor['avatarVersion'],
      );
      expect(
        sha256.convert(utf8.encode(editorUri)).toString(),
        wireEditor['avatarVersion'],
      );
      expect(
        sha256.convert(authorPng).toString(),
        '510dd2a22344e8b1d0498fc0cf297ab766fa6777f923a1bd21cc5e4c52992726',
      );
      expect(
        editorPng,
        orderedEquals(authorPng),
        reason: 'The actual producer uses the same synthetic PNG in two distinct person slots.',
      );
      final host = AuthorWireHost(
        authorCapability: true,
        announcementWire: true,
        announcementPage: _typedAnnouncementDetailDomainPage,
        announcementDetailFixture: 'ann-detail-hint-true',
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityAnnouncementsController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        final entry = model.page!.current!;
        final historyRefs = model.history
            .map((item) => item.announcementRef)
            .toList();
        expect(historyRefs, hasLength(1));
        for (final person in [entry.author, entry.editor]) {
          expect(person.callsign, 'Bridge wire-visible');
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Authorized body'), findsOneWidget);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'announcements')
            .toList();
        expect(reads, hasLength(2));
        expect(reads.last.payload['authorIdentitySchemaVersion'], 1);
        expect(reads.last.payload['observeAnnouncementRefs'], [
          entry.announcementRef,
        ]);
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
        final fresh = tester.widget<CommunityAnnouncementDetailsBody>(
          bodyFinder,
        );
        expect(fresh.entry.author.callsign, 'Bridge wire-visible');
        expect(fresh.entry.editor.callsign, 'Bridge wire-visible');
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        for (final person in [fresh.entry.author, fresh.entry.editor]) {
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'A fresh current surface, content and both actual identities must succeed before the typed-detail assertion.',
        );
        final details = host.requests
            .where(
              (request) => request.payload['action'] == 'announcementDetail',
            )
            .toList();
        expect(
          details,
          hasLength(1),
          reason: 'Only the current admitted surface needs one detail read, not a neutral legacy read plus a second owner.',
        );
        final request = details.single.payload;
        expect(request['targetRef'], detailWire['targetRef']);
        expect(request['announcementRef'], detailWire['announcementRef']);
        expect(
          request['authorIdentitySchemaVersion'],
          1,
          reason: 'The original detail owner must consume its negotiated typed identity lane.',
        );
        expect(
          request['expectedAuthorIdentityVersion'],
          wireAuthor['identityVersion'],
        );
        expect(
          request['expectedEditorIdentityVersion'],
          wireEditor['identityVersion'],
        );
        expect(request['offset'], 0);
        expect(request['version'], isNull);
        expect(fresh.author, orderedEquals(authorPng));
        expect(fresh.editor, orderedEquals(editorPng));
        // Decode the unchanged producer PNG independently. This also drains real
        // engine image work without advancing the injected UTC/fake deadline.
        final expectedImage = (await tester.runAsync(
          () => decodeCommunityImage(authorPng, 96),
        ))!;
        try {
          final expectedPixels = (await tester.runAsync(
            () => expectedImage.toByteData(),
          ))!;
          final imageFinder = find.descendant(
            of: bodyFinder,
            matching: find.byType(RawImage),
          );
          for (
            var attempt = 0;
            attempt < 8 && imageFinder.evaluate().length < 2;
            attempt++
          ) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
          }
          expect(
            imageFinder,
            findsNWidgets(2),
            reason: 'Both person slots must actually decode, not merely retain data URI strings.',
          );
          for (final image in tester.widgetList<RawImage>(imageFinder)) {
            expect(image.image, isNotNull);
            expect(image.image!.width, expectedImage.width);
            expect(image.image!.height, expectedImage.height);
            final pixels = (await tester.runAsync(
              () => image.image!.toByteData(),
            ))!;
            expect(
              pixels.buffer.asUint8List(),
              orderedEquals(expectedPixels.buffer.asUint8List()),
            );
          }
        } finally {
          expectedImage.dispose();
        }
        host.holdNextAnnouncementRead();
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        var state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(state.author, isNull);
        expect(state.editor, isNull);
        await tester.idle();
        expect(host.announcementReadHeld, isTrue);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(3),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(1),
        );
        host.releaseAnnouncementRead();
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        await _expectAnnouncementPixelSlots(tester, authorPng, editorPng);
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(3),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(2),
        );
        final authorPort =
            host.adapter as CommunityAnnouncementAuthorProjectionPort;
        host.session.acceptHostCapabilities(['officialFleet.communication']);
        expect(
          host.session.hostCapabilities.contains(
            'officialFleet.communication.authorIdentities',
          ),
          isFalse,
        );
        expect(authorPort.authorIdentitiesAvailable, isFalse);
        await tester.idle();
        await tester.pump();
        expect(state.author, isNull);
        expect(state.editor, isNull);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        host.session.acceptHostCapabilities([
          'officialFleet.communication',
          'officialFleet.communication.authorIdentities',
        ]);
        await tester.idle();
        await tester.pump();
        expect(
          authorPort.authorIdentitiesAvailable,
          isFalse,
          reason:
              'Adding the semantic cap is not a fresh source-open admission.',
        );
        expect(find.byType(RawImage), findsNothing);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(3),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(2),
        );
        final reopened = await host.adapter.open();
        expect(reopened.targetRef, context.targetRef);
        await tester.idle();
        expect(authorPort.authorIdentitiesAvailable, isTrue);
        await model.refresh(background: true);
        await tester.idle();
        await tester.pump();
        await tester.idle();
        await tester.pump();
        await _expectAnnouncementPixelSlots(tester, authorPng, editorPng);
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        expect(state.author, orderedEquals(authorPng));
        expect(state.editor, orderedEquals(editorPng));
        final restored = tester.widget<CommunityAnnouncementDetailsBody>(
          find.byType(CommunityAnnouncementDetailsBody),
        );
        for (final person in [restored.entry.author, restored.entry.editor]) {
          expect(person.identity!.observedAt, DateTime.utc(2026, 10, 17, 12));
          expect(
            person.identity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        expect(
          host.requests.where((request) => request.payload['action'] == 'open'),
          hasLength(2),
        );
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, raw);
        expect(model.history.map((item) => item.announcementRef), historyRefs);
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcements',
          ),
          hasLength(4),
        );
        expect(
          host.requests.where(
            (request) => request.payload['action'] == 'announcementDetail',
          ),
          hasLength(3),
        );
        expect(
          host.requests.where(
            (request) => {
              'sendChat',
              'markChatRead',
            }.contains(request.payload['action']),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'ordinary announcement avatars keep their original detail and decode behavior',
    (tester) async {
      final raw = _typedAnnouncementDetailDomainPage();
      final detail = wire('ann-detail-hint-true');
      final images = jsonDecode(
        utf8.decode(base64Decode(detail['data'] as String)),
      ) as Map;
      final authorPng = base64Decode(
        (images['authorAvatarImageData'] as String).split(',').last,
      );
      final editorPng = base64Decode(
        (images['editorAvatarImageData'] as String).split(',').last,
      );
      final host = CommunityHarness(
        capabilities: [
          'communities.announcements',
          'communities.announcementDetail',
        ],
        responses: {
          'communities.announcements': raw,
          'communities.announcementDetail': detail,
        },
      );
      addTearDown(host.close);
      CommunityAnnouncementsController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        var now = DateTime.utc(2026, 10, 17, 12, 0, 1);
        final model = CommunityAnnouncementsController(
          host.adapter,
          raw['targetRef'] as String,
          now: () => now,
        );
        cleanupModel = model;
        await model.refresh();
        expect(model.error, isNull);
        expect(model.usesOfficialAuthorProjection, isFalse);
        final entry = model.page!.current!;
        expect(entry.author.identity, isNull);
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: CommunityAnnouncementDetails(model: model, entry: entry),
            ),
          ),
        );
        await tester.idle();
        await tester.pump();
        await _expectAnnouncementPixelSlots(tester, authorPng, editorPng);
        final state =
            tester.state(find.byType(CommunityAnnouncementDetails)) as dynamic;
        final originalAuthor = state.author, originalEditor = state.editor;
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        now = DateTime.utc(2026, 10, 17, 12, 0, 6);
        await tester.pump(const Duration(seconds: 5));
        model.refreshTimeLabels();
        await tester.pump();
        expect(state.author, same(originalAuthor));
        expect(state.editor, same(originalEditor));
        expect(find.byType(RawImage), findsNWidgets(2));
        expect(find.textContaining('Bridge wire-visible'), findsNWidgets(2));
        expect(find.text('Authorized body'), findsOneWidget);
        _expectContent(model.page!, raw);
        expect(model.history, hasLength(1));
        expect(model.canManage, isFalse);
        expect(
          host.requests.where(
            (request) => request.name == 'communities.announcements',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => request.name == 'communities.announcementDetail',
          ),
          hasLength(1),
        );
        expect(
          host.requests.where(
            (request) => {
              'communities.sendChat',
              'communities.markChatRead',
            }.contains(request.name),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
}

void _expectContent(CommunityAnnouncementsPage page, Map<String, Object?> raw) {
  expect(page.targetRef, raw['targetRef']);
  expect(page.revision, raw['revision']);
  expect(page.canManage, raw['canManage']);
  expect(page.offset, raw['offset']);
  expect(page.next, raw['next']);
  expect(page.totalHistoryCount, raw['totalHistoryCount']);
  expect(
    page.refreshedAt.toUtc(),
    DateTime.parse(raw['refreshedAt'] as String).toUtc(),
  );
  expect(page.history.length, (raw['history'] as List).length);
  final expected = [
    if (raw['current'] != null) raw['current'] as Map,
    ...(raw['history'] as List).cast<Map>(),
  ];
  final actual = [?page.current, ...page.history];
  expect(actual.length, expected.length);
  for (var index = 0; index < expected.length; index++) {
    final before = expected[index], after = actual[index];
    expect(after.announcementRef, before['announcementRef']);
    expect(after.title, before['title']);
    expect(after.content, before['content']);
    expect(after.state, before['state']);
    expect(after.revision, before['revision']);
    expect(
      after.publishedAt.toUtc(),
      DateTime.parse(before['publishedAt'] as String).toUtc(),
    );
    expect(
      after.updatedAt.toUtc(),
      DateTime.parse(before['updatedAt'] as String).toUtc(),
    );
    expect(
      after.archivedAt?.toUtc(),
      before['archivedAt'] == null
          ? null
          : DateTime.parse(before['archivedAt'] as String).toUtc(),
    );
    expect(
      after.withdrawnAt?.toUtc(),
      before['withdrawnAt'] == null
          ? null
          : DateTime.parse(before['withdrawnAt'] as String).toUtc(),
    );
  }
}

// Test-only typed domain composition, not an actual producer response:
// author00->05 comes from ann-mixed-current; editor03->08 comes unchanged
// from the independently produced ann-detail-late-per-row-expiry scenario.
Map<String, Object?> _staggeredAnnouncementDomainPage() {
  final page = wire('ann-mixed-current');
  final current = Map<String, Object?>.from(page['current'] as Map);
  final detail = wire('ann-detail-late-per-row-expiry');
  return {
    ...page,
    'current': {
      ...current,
      'editor': Map<String, Object?>.from(detail['editor'] as Map),
    },
  };
}

// Explicit test-only typed domain composition, not an actual page producer:
// retain ann-mixed-current content/history, align only its current record's
// opaque addresses and two people to the unchanged independent detail wire.
Map<String, Object?> _typedAnnouncementDetailDomainPage() {
  final page = wire('ann-mixed-current');
  final current = Map<String, Object?>.from(page['current'] as Map);
  final detail = wire('ann-detail-hint-true');
  return {
    ...page,
    'targetRef': detail['targetRef'],
    'current': {
      ...current,
      'announcementRef': detail['announcementRef'],
      'author': Map<String, Object?>.from(detail['author'] as Map),
      'editor': Map<String, Object?>.from(detail['editor'] as Map),
    },
  };
}

// Explicit typed-domain metadata composition only: actual independent editor
// observation03->08, actual author00->05, unchanged two-PNG body/version/data.
Map<String, Object?> _independentAnnouncementPixelDetail() => {
  ...wire('ann-detail-hint-true'),
  'editor': wire('ann-detail-late-per-row-expiry')['editor'],
};
Map<String, Object?> _independentAnnouncementPixelPage() {
  final page = _typedAnnouncementDetailDomainPage();
  return {
    ...page,
    'current': {
      ...Map<String, Object?>.from(page['current'] as Map),
      'editor': _independentAnnouncementPixelDetail()['editor'],
    },
  };
}

Future<void> _expectAnnouncementPixelSlots(
  WidgetTester tester,
  List<int> author,
  List<int> editor,
) async {
  final bodyFinder = find.byType(CommunityAnnouncementDetailsBody);
  final body = tester.widget<CommunityAnnouncementDetailsBody>(bodyFinder);
  expect(body.author, orderedEquals(author));
  expect(body.editor, orderedEquals(editor));
  final expected = (await tester.runAsync(
    () => decodeCommunityImage(base64Decode(base64Encode(author)), 96),
  ))!;
  try {
    final expectedPixels = (await tester.runAsync(
      () => expected.toByteData(),
    ))!;
    final imageFinder = find.descendant(
      of: bodyFinder,
      matching: find.byType(RawImage),
    );
    for (
      var attempt = 0;
      attempt < 8 && imageFinder.evaluate().length < 2;
      attempt++
    ) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(imageFinder, findsNWidgets(2));
    expect(
      editor,
      orderedEquals(author),
      reason: 'These original producer person slots use one synthetic PNG.',
    );
    for (final widget in tester.widgetList<RawImage>(imageFinder)) {
      final pixels = (await tester.runAsync(() => widget.image!.toByteData()))!;
      expect(
        pixels.buffer.asUint8List(),
        orderedEquals(expectedPixels.buffer.asUint8List()),
      );
    }
  } finally {
    expected.dispose();
  }
}
