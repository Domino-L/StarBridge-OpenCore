import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';

import '../friends/social_layout_test.dart' show app;
import 'community_chat_controller_test.dart' show FakeChat, page;
import '../official_fleet/official_fleet_author_wire_test.dart'
    show AuthorWireHost, wire;

void main() {
  testWidgets(
    'reference recovery rejects changed content and missing root records without looping',
    (tester) async {
      for (final missing in [false, true]) {
        final port = RecoveryDomainPort();
        addTearDown(port.close);
        final model = CommunityChatController(
          port,
          'a' * 32,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        Future<void>? pending;
        try {
          await primeRecoveryWindow(model, tester);
          final refs = model.messages
              .take(3)
              .map((row) => row.messageRef)
              .toList();
          final contents = model.messages
              .map((row) => (row.sequence, row.text))
              .toList();
          const viewport = CommunityChatViewport(
            pixels: 320,
            followLatest: false,
            observedLatest: 55,
            anchorSequence: 2,
            anchorOffset: 8,
          );
          model.rememberViewport(viewport);
          model.updateDraft('Keep mismatched root draft');
          port.retired = true;
          pending = model.refresh(silent: true);
          await tester.pump();
          expect(port.rootHeld, isTrue);
          port.releaseRoot(port.rootPage(missing: missing, changed: !missing));
          await pending;
          expect(model.error, isNull);
          expect(port.rootReads, 1);
          expect(model.messages.take(3).map((row) => row.messageRef), refs);
          expect(
            model.messages
                .take(3)
                .every((row) => model.presentAuthor(row).callsign.isEmpty),
            isTrue,
          );
          expect(
            model.messages.map((row) => (row.sequence, row.text)),
            contents,
          );
          expect(model.viewport, same(viewport));
          expect(model.draft, 'Keep mismatched root draft');
          await model.refresh(silent: true);
          expect(port.rootReads, 1);
          expect(model.messages.take(3).map((row) => row.messageRef), refs);
          expect(model.latestSequence, 55);
          expect(model.confirmedReadThrough, 0);
          expect(port.marks, 0);
        } finally {
          model.dispose();
          port.cancelRoot();
          if (pending != null) await pending;
          await tester.idle();
        }
      }
    },
  );

  testWidgets(
    'a late root cannot replace references after the logical visible window changes',
    (tester) async {
      final port = RecoveryDomainPort();
      addTearDown(port.close);
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
      );
      Future<void>? pending;
      try {
        await primeRecoveryWindow(model, tester);
        final old = model.messages
            .take(3)
            .map((row) => row.messageRef)
            .toList();
        model.updateDraft('Keep changed window draft');
        port.retired = true;
        pending = model.refresh(silent: true);
        await tester.pump();
        expect(port.rootHeld, isTrue);
        model.observeAuthors(model.messages.skip(3).take(3));
        port.releaseRoot(port.rootPage());
        await pending;
        for (var index = 0; index < 12 && model.loading; index++) {
          await tester.pump();
        }
        expect(model.messages.take(3).map((row) => row.messageRef), old);
        expect(
          model.messages
              .take(3)
              .every((row) => model.presentAuthor(row).callsign.isEmpty),
          isTrue,
        );
        expect(model.messages, hasLength(55));
        expect(model.draft, 'Keep changed window draft');
        expect(model.latestSequence, 55);
        expect(model.confirmedReadThrough, 0);
        expect(port.marks, 0);
        expect(
          port.rootReads,
          lessThanOrEqualTo(2),
          reason: 'Only the new logical window may get its own bounded root attempt.',
        );
      } finally {
        model.dispose();
        port.cancelRoot();
        if (pending != null) await pending;
        await tester.idle();
      }
    },
  );

  testWidgets(
    'a held reference root cannot survive target renewal or lifetime invalidation',
    (tester) async {
      for (final invalidate in [false, true]) {
        final port = RecoveryDomainPort();
        addTearDown(port.close);
        final model = CommunityChatController(
          port,
          'a' * 32,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        Future<void>? pending;
        try {
          await primeRecoveryWindow(model, tester);
          final refs = model.messages
              .take(3)
              .map((row) => row.messageRef)
              .toList();
          model.updateDraft('Same-owner retained target draft');
          port.retired = true;
          pending = model.refresh(silent: true);
          await tester.pump();
          expect(port.rootHeld, isTrue);
          if (invalidate) {
            port.changes.add(null);
            expect(model.invalidated, isTrue);
          } else {
            // Existing owner entrypoint requires an already verified same account
            // and same organization. This fixture is not a membership grant.
            model.renewVerifiedReference('b' * 32);
            expect(model.targetRef, 'b' * 32);
          }
          port.releaseRoot(port.rootPage());
          await pending;
          expect(port.rootReads, 1);
          expect(port.marks, 0);
          if (invalidate) {
            expect(model.messages, isEmpty);
            expect(model.draft, isEmpty);
          } else {
            expect(model.messages.take(3).map((row) => row.messageRef), refs);
            expect(
              model.messages
                  .take(3)
                  .every((row) => model.presentAuthor(row).callsign.isEmpty),
              isTrue,
            );
            expect(model.messages, hasLength(55));
            expect(model.draft, 'Same-owner retained target draft');
            expect(model.latestSequence, 55);
          }
        } finally {
          model.dispose();
          port.cancelRoot();
          if (pending != null) await pending;
          await tester.idle();
        }
      }
    },
  );

  testWidgets(
    'stale author references recover once from the retained visible window without jumping latest',
    (tester) async {
      // Explicit consumer-domain composition, not an exported 55-row response.
      // Original wire files and each person's 00->05 observation stay unchanged.
      // The fixture retires opaque refs while now=01; it does not simulate a
      // five-minute wait by extending any identity deadline.
      final original = wire('chat-current-visible');
      final originalPerson = Map<String, Object?>.from(
        (original['messages'] as List).single as Map,
      );
      final originalUpdate = Map<String, Object?>.from(
        (wire('chat-empty-page-observed-update')['authorUpdates'] as List)
                .single
            as Map,
      );
      final hinted = wire('chat-hint-true');
      expect(hinted['authorRefreshRequired'], isTrue);
      // The producer provenance labels this as a controlled HTTP hint variant.
      var referencesRetired = false;
      var staleReads = 0;
      final rootRequests = <Map<String, Object?>>[];
      String reference(int sequence, {bool fresh = false}) =>
          ((fresh ? 2000 : 1000) + sequence).toRadixString(16).padLeft(32, '0');
      Map<String, Object?> person(int sequence, {bool fresh = false}) => {
        ...originalPerson,
        'sequence': sequence,
        'messageRef': reference(sequence, fresh: fresh),
        'text': 'Retained body $sequence',
      };
      Map<String, Object?> response(
        List<int> sequences, {
        bool fresh = false,
        bool older = false,
        bool hint = false,
        List<String> observed = const [],
      }) => {
        ...(hint ? hinted : original),
        'targetRef': original['targetRef'],
        'messages': [
          for (final sequence in sequences) person(sequence, fresh: fresh),
        ],
        'latestSequence': 55,
        'oldestSequence': sequences.firstOrNull ?? 0,
        'hasOlder': older,
        'unreadCount': 55,
        'authorRefreshRequired': hint,
        'authorUpdates': [
          for (final ref in observed)
            {
              ...originalUpdate,
              'messageRef': ref,
              'senderRef': originalPerson['senderRef'],
              'sequence': int.parse(ref, radix: 16) % 1000,
              'recordState': hint ? 'notRetained' : 'found',
              if (hint) ...{
                'senderCallsign': '',
                'hasAvatar': false,
                'avatarVersion': null,
                'authorIdentityState': 'unavailable',
                'authorIdentityVersion': null,
                'identityObservedAtUtc': null,
                'identityValidUntilUtc': null,
              },
            },
        ],
      };
      final host = AuthorWireHost(
        authorCapability: true,
        chatPage: (request) {
          final after = request.payload['after'] as int? ?? 0;
          final before = request.payload['before'] as int? ?? 0;
          final observed =
              (request.payload['observeMessageRefs'] as List? ?? [])
                  .cast<String>();
          if (referencesRetired && before == 4 && after == 0) {
            rootRequests.add(Map<String, Object?>.from(request.payload));
            return response([1, 2, 3], fresh: true);
          }
          if (before == 6) return response([1, 2, 3, 4, 5]);
          if (after == 0 && before == 0) {
            return response(
              List.generate(50, (index) => index + 6),
              older: true,
            );
          }
          if (referencesRetired) staleReads++;
          return response(
            const [],
            hint: referencesRetired,
            observed: observed,
          );
        },
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityChatController? cleanupModel;
      var retiredFixture = false;
      Future<void> retireFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        cleanupModel?.dispose();
        host.session.advanceGeneration(host.session.activeGeneration + 1);
        await tester.idle();
      }

      addTearDown(retireFixture);
      try {
        final context = await host.adapter.open();
        final model = CommunityChatController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        await model.refresh();
        await model.loadOlder();
        expect(model.error, isNull);
        expect(model.messages, hasLength(55));
        expect(model.messages.first.sequence, 1);
        expect(model.messages.last.sequence, 55);
        final contents = [
          for (final message in model.messages)
            (
              message.sequence,
              message.text,
              message.createdAt,
              message.isSelf,
              message.localRequestId,
              message.hasAttachment,
            ),
        ];
        const viewport = CommunityChatViewport(
          pixels: 320,
          followLatest: false,
          observedLatest: 55,
          anchorSequence: 2,
          anchorOffset: 8,
        );
        model.rememberViewport(viewport);
        model.updateDraft('Keep the retained window draft');
        model.setReadingContext(visible: true, foreground: true);
        // This is a Controller-window tracer, not a physical viewport claim.
        model.observeAuthors(model.messages.take(3));
        for (var index = 0; index < 12 && model.loading; index++) {
          await tester.pump();
        }
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        for (final message in model.messages.take(3)) {
          expect(model.presentAuthor(message).callsign, 'Bridge wire-visible');
          expect(
            message.authorIdentity!.observedAt,
            DateTime.utc(2026, 10, 17, 12),
          );
          expect(
            message.authorIdentity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        final oldReferences = model.messages
            .take(3)
            .map((message) => message.messageRef)
            .toList();
        expect(rootRequests, isEmpty);
        referencesRetired = true;
        await model.refresh(silent: true);
        for (var index = 0; index < 12 && model.loading; index++) {
          await tester.pump();
        }
        expect(model.error, isNull);
        expect(
          staleReads,
          1,
          reason: 'The typed stale-window response must actually be consumed.',
        );
        expect(
          rootRequests,
          hasLength(1),
          reason: 'authorRefreshRequired must use one before:lastVisible+1 root read, not stay neutral forever.',
        );
        expect(rootRequests.single['authorIdentitySchemaVersion'], 1);
        expect(rootRequests.single['after'], 0);
        expect(rootRequests.single['before'], 4);
        expect(rootRequests.single['observeMessageRefs'], isEmpty);
        expect(model.messages.take(3).map((message) => message.messageRef), [
          for (var sequence = 1; sequence <= 3; sequence++)
            reference(sequence, fresh: true),
        ]);
        expect(
          model.messages.take(3).map((message) => message.messageRef),
          isNot(oldReferences),
        );
        expect(model.messages, hasLength(55));
        expect([
          for (final message in model.messages)
            (
              message.sequence,
              message.text,
              message.createdAt,
              message.isSelf,
              message.localRequestId,
              message.hasAttachment,
            ),
        ], contents);
        expect(model.viewport, same(viewport));
        expect(model.latestSequence, 55);
        expect(model.confirmedReadThrough, 0);
        expect(model.unreadCount, 55);
        expect(model.draft, 'Keep the retained window draft');
        for (final message in model.messages.take(3)) {
          expect(model.presentAuthor(message).callsign, 'Bridge wire-visible');
          expect(
            message.authorIdentity!.observedAt,
            DateTime.utc(2026, 10, 17, 12),
          );
          expect(
            message.authorIdentity!.validUntil,
            DateTime.utc(2026, 10, 17, 12, 0, 5),
          );
        }
        // A persistent hint must not create another recovery for this window.
        await model.refresh(silent: true);
        await tester.pump();
        expect(staleReads, 2);
        expect(rootRequests, hasLength(1));
        expect(model.messages, hasLength(55));
        expect(model.viewport, same(viewport));
        expect(model.draft, 'Keep the retained window draft');
        expect(
          host.requests.where((request) => request.payload['action'] == 'open'),
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
        await retireFixture();
      }
    },
  );

  testWidgets(
    'retained official author is neutral in the first mounted frame',
    (tester) async {
      final host = AuthorWireHost(authorCapability: true);
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      final context = await host.adapter.open();
      final model = CommunityChatController(
        host.adapter,
        context.targetRef,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.messages.single.callsign, 'Bridge wire-visible');
      model.updateDraft('Keep this draft');
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: host.adapter,
            targetRef: context.targetRef,
            name: 'Official fixture',
            controller: model,
            onBack: () {},
          ),
        ),
      );
      expect(find.byType(CommunityChatPanel), findsOneWidget);
      expect(find.text('authorized body'), findsOneWidget);
      expect(
        find.textContaining('Bridge wire-visible'),
        findsNothing,
        reason: 'Retained metadata is not permission for a new visible window.',
      );
      expect(model.draft, 'Keep this draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the original visible worker renews author on an empty content page',
    (tester) async {
      final host = AuthorWireHost(authorCapability: true);
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      final context = await host.adapter.open();
      final model = CommunityChatController(
        host.adapter,
        context.targetRef,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      await model.refresh();
      model.updateDraft('Keep this draft');
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: host.adapter,
            targetRef: context.targetRef,
            name: 'Official fixture',
            controller: model,
            onBack: () {},
          ),
        ),
      );
      expect(find.textContaining('Bridge wire-visible'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final reference = model.messages.single.messageRef;
      expect(
        host.requests
            .where((request) => request.payload['action'] == 'chat')
            .any(
              (request) =>
                  (request.payload['observeMessageRefs'] as List? ?? [])
                      .contains(reference),
            ),
        isTrue,
        reason: 'The real measured window must reach the existing read worker.',
      );
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      expect(find.text('authorized body'), findsOneWidget);
      expect(model.messages.length, 1);
      expect(model.draft, 'Keep this draft');
      expect(
        host.requests.where((r) => r.payload['action'] == 'sendChat'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'all 55 genuinely visible rows are observed fairly in batches of 50',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = WindowAuthorPort();
      addTearDown(port.changes.close);
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      await model.refresh();
      await model.loadOlder();
      expect(model.messages.length, 55);
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: port,
            targetRef: 'a' * 32,
            name: 'Fair window',
            controller: model,
            onBack: () {},
          ),
        ),
      );
      expect(find.textContaining('Bridge wire-visible'), findsNothing);
      await tester.pumpAndSettle();
      final observed = port.observations
          .where((batch) => batch.isNotEmpty)
          .toList();
      expect(observed.every((batch) => batch.length <= 50), isTrue);
      expect(
        observed.expand((batch) => batch).toSet(),
        model.messages.map((message) => message.messageRef).toSet(),
      );
      expect(find.textContaining('Bridge wire-visible'), findsNWidgets(55));
      expect(model.messages.length, 55);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'losing the author capability retires displayed names before any next read',
    (tester) async {
      final host = AuthorWireHost(authorCapability: true);
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      final context = await host.adapter.open();
      final model = CommunityChatController(
        host.adapter,
        context.targetRef,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      await model.refresh();
      model.updateDraft('Capability draft');
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: host.adapter,
            targetRef: context.targetRef,
            name: 'Capability window',
            controller: model,
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      final beforeLoss = host.requests
          .where((r) => r.payload['action'] == 'chat')
          .length;
      host.session.acceptHostCapabilities(['officialFleet.communication']);
      // Drain the existing asynchronous capability event before its first frame.
      await tester.idle();
      expect(
        host.session.hostCapabilities.contains(
          'officialFleet.communication.authorIdentities',
        ),
        isFalse,
      );
      expect(
        (host.adapter as CommunityAuthorProjectionPort)
            .authorIdentitiesAvailable,
        isFalse,
      );
      await tester.pump();
      expect(
        find.textContaining('Bridge wire-visible'),
        findsNothing,
        reason: 'A negotiated old projection cannot outlive current capability support.',
      );
      expect(find.text('authorized body'), findsOneWidget);
      expect(model.draft, 'Capability draft');
      expect(
        host.requests.where((r) => r.payload['action'] == 'chat').length,
        beforeLoss,
        reason: 'Support retirement must not create another read worker.',
      );
      host.session.acceptHostCapabilities([
        'officialFleet.communication',
        'officialFleet.communication.authorIdentities',
      ]);
      await tester.idle();
      await tester.pump();
      expect(
        find.textContaining('Bridge wire-visible'),
        findsNothing,
        reason: 'Returning support does not reauthorize an old source open.',
      );
      await host.adapter.open();
      await tester.pump();
      expect(
        find.textContaining('Bridge wire-visible'),
        findsNothing,
        reason: 'Fresh context alone is not fresh author permission.',
      );
      await model.refresh(silent: true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      expect(model.draft, 'Capability draft');
      expect(
        host.requests.where((r) => r.payload['action'] == 'sendChat'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'scrolling back shows last-seen names until its new window read and excludes cache extent',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = WindowAuthorPort();
      addTearDown(port.changes.close);
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      await model.refresh();
      await model.loadOlder();
      model.updateDraft('Scroll draft');
      final panel = find.byType(CommunityChatPanel);
      final rows = find.descendant(
        of: panel,
        matching: find.byType(CommunityChatMessageTile),
      );
      Set<String> visibleRefs() {
        final viewport = find.descendant(
          of: panel,
          matching: find.byType(Viewport),
        );
        if (viewport.evaluate().isEmpty) return {};
        final clip = tester.getRect(viewport);
        return {
          for (final element in rows.evaluate())
            if (tester
                        .getRect(find.byKey(element.widget.key!))
                        .intersect(clip)
                        .height >=
                    16 &&
                tester.getRect(find.byKey(element.widget.key!)).overlaps(clip))
              (element.widget as CommunityChatMessageTile).message.messageRef,
        };
      }

      port.onObserve = (refs) {
        if (refs.isNotEmpty) {
          expect(
            visibleRefs().containsAll(refs),
            isTrue,
            reason: 'Mounted cache extent rows are not author observations.',
          );
        }
      };
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: port,
            targetRef: 'a' * 32,
            name: 'Scroll window',
            controller: model,
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visible = visibleRefs();
      expect(visible, isNotEmpty);
      expect(rows.evaluate().length, greaterThan(visible.length));
      for (final element in rows.evaluate()) {
        final message = (element.widget as CommunityChatMessageTile).message;
        // Only rows on screen are confirmed; others may show a seen name.
        expect(
          message.authorIdentity?.visible == true,
          visible.contains(message.messageRef),
        );
      }
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: panel, matching: find.byType(Scrollable)).first,
      );
      final bottom = scrollable.position.pixels;
      port.authorsGate = Completer<void>();
      await tester.drag(
        find.descendant(of: panel, matching: find.byType(ListView)),
        const Offset(0, 300),
      );
      await tester.pump();
      // User decision 2026-10-30: no flicker, but nothing confirmed yet either.
      expect(find.textContaining('Bridge wire-visible'), findsWidgets);
      for (final element in rows.evaluate()) {
        final message = (element.widget as CommunityChatMessageTile).message;
        expect(message.authorIdentity?.visible, isFalse);
      }
      scrollable.position.jumpTo(bottom);
      await tester.pump();
      // Returning to retained rows is a new window: shown, still unconfirmed.
      expect(find.textContaining('Bridge wire-visible'), findsWidgets);
      for (final element in rows.evaluate()) {
        final message = (element.widget as CommunityChatMessageTile).message;
        expect(message.authorIdentity?.visible, isFalse);
      }
      expect(model.messages.length, 55);
      expect(model.draft, 'Scroll draft');
      port.authorsGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Bridge wire-visible'), findsWidgets);
      expect(model.messages.length, 55);
      expect(model.draft, 'Scroll draft');
      expect(scrollable.position.pixels, closeTo(bottom, 1));
      expect(
        port.observations.length,
        lessThan(15),
        reason: 'Coalescing follows the latest window without an author retry loop.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('ordinary community keeps its existing first-frame author', (
    tester,
  ) async {
    final port = FakeChat()
      ..next = page([1], latest: 1, unread: 0, older: false);
    addTearDown(port.changes.close);
    final model = CommunityChatController(port, 'a' * 32);
    addTearDown(model.dispose);
    await model.refresh();
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      app(
        CommunityChatPanel(
          port: port,
          targetRef: 'a' * 32,
          name: 'Community fixture',
          controller: model,
          onBack: () {},
        ),
      ),
    );
    expect(find.text('Message 1'), findsOneWidget);
    expect(find.textContaining('Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Synthetic 55-row viewport fixture derived from actual person metadata.
/// No avatar keeps geometry stable; the identity hash follows the owner domain.
/// This fixture is not claimed as an exported 55-row Host response.
final class WindowAuthorPort
    implements CommunityChatPort, CommunityAuthorProjectionPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final observations = <List<String>>[];
  Completer<void>? authorsGate;
  void Function(List<String>)? onObserve;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  bool get authorIdentitiesAvailable => true;
  @override
  Stream<void> get authorIdentityChanges => const Stream.empty();
  Map<String, Object?> person(int sequence) {
    final original = Map<String, Object?>.from(
      (wire('chat-current-visible')['messages'] as List).single as Map,
    );
    final version = sha256
        .convert(
          utf8.encode(
            'StarBridge.OfficialFleet.CommunicationAuthor.v1\n${jsonEncode([original['senderCallsign'], null])}',
          ),
        )
        .toString();
    return {
      ...original,
      'sequence': sequence,
      'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
      'text': 'Body $sequence',
      'hasAvatar': false,
      'avatarVersion': null,
      'authorIdentityVersion': version,
    };
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) => readChatAuthors(targetRef, after: after, before: before);
  @override
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) async {
    observations.add(List.of(observeMessageRefs));
    onObserve?.call(observeMessageRefs);
    await authorsGate?.future;
    final sequences = before == 6
        ? List.generate(5, (i) => i + 1)
        : after == 0 && before == 0
        ? List.generate(50, (i) => i + 6)
        : <int>[];
    final source = wire('chat-current-visible');
    return CommunityChatPage.parse({
      ...source,
      'targetRef': targetRef,
      'messages': sequences.map(person).toList(),
      'latestSequence': 55,
      'oldestSequence': sequences.firstOrNull ?? 0,
      'hasOlder': after == 0 && before == 0,
      'unreadCount': 0,
      'authorUpdates': [
        for (final reference in observeMessageRefs)
          {...person(int.parse(reference, radix: 16)), 'recordState': 'found'},
      ],
    }, officialAuthors: true);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => throw StateError('No avatar or attachment');
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => throw StateError('Observation is not a receipt');
}

/// Typed domain controls derived from original person/page metadata. No exported
/// producer response is changed or claimed for these held/mismatched scenarios.
final class RecoveryDomainPort
    implements CommunityChatPort, CommunityAuthorProjectionPort {
  final WindowAuthorPort delegate = WindowAuthorPort();
  bool retired = false;
  int rootReads = 0, marks = 0;
  Completer<CommunityChatPage>? _root;
  StreamController<void> get changes => delegate.changes;
  bool get rootHeld => _root != null && !_root!.isCompleted;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Stream<void> get authorIdentityChanges => const Stream.empty();
  @override
  bool get authorIdentitiesAvailable => true;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) => readChatAuthors(targetRef, after: after, before: before);
  @override
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) async {
    if (retired && after == 0 && before > 0 && before != 6) {
      rootReads++;
      if (rootReads > 1) return rootPage(target: targetRef, missing: true);
      _root = Completer<CommunityChatPage>();
      return _root!.future;
    }
    if (!retired || after == 0) {
      return delegate.readChatAuthors(
        targetRef,
        after: after,
        before: before,
        observeMessageRefs: observeMessageRefs,
      );
    }
    return CommunityChatPage.parse({
      ...wire('chat-hint-true'),
      'targetRef': targetRef,
      'messages': [],
      'oldestSequence': 0,
      'latestSequence': 55,
      'hasOlder': false,
      'unreadCount': 0,
      'authorUpdates': [
        for (final ref in observeMessageRefs)
          {
            'messageRef': ref,
            'senderRef': delegate.person(1)['senderRef'],
            'sequence': int.parse(ref, radix: 16),
            'recordState': 'notRetained',
          },
      ],
    }, officialAuthors: true);
  }

  CommunityChatPage rootPage({
    String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    bool missing = false,
    bool changed = false,
  }) => CommunityChatPage.parse({
    ...wire('chat-current-visible'),
    'targetRef': target,
    'messages': [
      if (!missing)
        for (var sequence = 1; sequence <= 3; sequence++)
          {
            ...delegate.person(sequence),
            'messageRef': (1000 + sequence).toRadixString(16).padLeft(32, '0'),
            if (changed) 'text': 'Changed immutable body $sequence',
          },
    ],
    'oldestSequence': missing ? 0 : 1,
    'latestSequence': 55,
    'hasOlder': false,
    'unreadCount': 0,
    'authorUpdates': [],
  }, officialAuthors: true);
  void releaseRoot(CommunityChatPage value) {
    if (!rootHeld) throw StateError('No actual held root');
    _root!.complete(value);
  }

  void cancelRoot() {
    if (rootHeld) {
      _root!.completeError(StateError('Fixture root cancelled'));
    }
  }

  Future<void> close() async {
    cancelRoot();
    await changes.close();
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => throw StateError('No media in reference controls');
  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) {
    marks++;
    throw StateError('Reference recovery is not a receipt');
  }
}

Future<void> primeRecoveryWindow(
  CommunityChatController model,
  WidgetTester tester,
) async {
  await model.refresh();
  await model.loadOlder();
  expect(model.error, isNull);
  expect(model.messages, hasLength(55));
  model.setReadingContext(visible: true, foreground: true);
  model.observeAuthors(model.messages.take(3));
  for (var index = 0; index < 12 && model.loading; index++) {
    await tester.pump();
  }
  expect(model.loading, isFalse);
  expect(model.error, isNull);
  expect(
    model.messages
        .take(3)
        .every((row) => model.presentAuthor(row).callsign.isNotEmpty),
    isTrue,
  );
}
