import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_avatar_cache.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_shared_preset_card.dart';

import '../friends/social_layout_test.dart' show app;
import '../official_fleet/official_fleet_author_wire_test.dart'
    show AuthorWireHost, wire;

void main() {
  testWidgets(
    'a new verified window cannot inherit the same-version pending avatar',
    (tester) async {
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final port = ChangingAvatarPort(pixel, pixel);
      addTearDown(port.changes.close);
      final avatars = CommunityAvatarCache();
      addTearDown(avatars.dispose);
      var unrelatedReads = 0;
      final unrelatedRead = avatars.get('unrelated', 'stable', () async {
        unrelatedReads++;
        return Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2]);
      });
      final unrelated = await unrelatedRead;
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => DateTime.utc(2026, 10, 17, 12),
      );
      addTearDown(model.dispose);
      model.setReadingContext(visible: true, foreground: true);
      await model.refresh();
      model.observeAuthors(model.messages);
      await tester.pump();
      final admitted = model.presentAuthor(model.messages.single);
      expect(admitted.hasAvatar, isTrue);
      final cache = model.media(avatars: avatars);
      final oldRead = cache.load(admitted, avatarOnly: true);
      expect(port.detailReads, 1);
      model.retireAuthors();
      expect(model.presentAuthor(model.messages.single).hasAvatar, isFalse);
      model.observeAuthors(model.messages);
      await tester.pump();
      final fresh = model.presentAuthor(model.messages.single);
      expect(fresh.hasAvatar, isTrue);
      expect(
        fresh.avatarVersion,
        admitted.avatarVersion,
        reason: 'The original UTC/hash is unchanged; a verified new window is not the old pending request.',
      );
      final freshRead = cache.load(fresh, avatarOnly: true);
      expect(
        port.detailReads,
        2,
        reason: 'The previous in-flight avatar must not be reused across publication windows.',
      );
      port.gates[0].complete();
      expect((await oldRead).avatar, isNull);
      expect(cache.peek(admitted)?.avatar, isNull);
      port.gates[1].complete();
      expect((await freshRead).avatar, orderedEquals(pixel));
      final retainedUnrelated = avatars.get('unrelated', 'stable', () async {
        unrelatedReads++;
        return null;
      });
      expect(retainedUnrelated, same(unrelatedRead));
      expect(await retainedUnrelated, same(unrelated));
      expect(
        unrelatedReads,
        1,
        reason: 'Retire the exact person/version; never clear the borrowed workspace cache.',
      );
      expect(port.detailReads, 2);
      expect(tester.takeException(), isNull);
      model.setReadingContext(visible: false, foreground: false);
    },
  );
  testWidgets(
    'a current changed avatar recovers after the older combined read finishes',
    (tester) async {
      final oldPixel = (await tester.runAsync(syntheticPixel))!;
      final newPixel = (await tester.runAsync(
        () => syntheticPixel(color: 0xffac6824),
      ))!;
      final oldImage = (await tester.runAsync(
        () => decodeCommunityImage(oldPixel, 96),
      ))!;
      final newImage = (await tester.runAsync(
        () => decodeCommunityImage(newPixel, 96),
      ))!;
      addTearDown(oldImage.dispose);
      addTearDown(newImage.dispose);
      final avatars = CommunityAvatarCache();
      avatars.images.dispose();
      avatars.images = CommunityImageDecodeCache(
        decoder: (bytes, _) async =>
            base64Encode(bytes) == base64Encode(newPixel)
            ? newImage.clone()
            : oldImage.clone(),
      );
      addTearDown(avatars.dispose);
      final port = ChangingAvatarPort(oldPixel, newPixel);
      addTearDown(port.changes.close);
      final cache = CommunityChatMediaCache(
        port,
        'a' * 32,
        avatars: avatars,
        now: () => DateTime.utc(2026, 10, 17, 12),
        authorIsCurrent: (message) =>
            message.authorIdentity
                ?.admit(DateTime.utc(2026, 10, 17, 12))
                .visible ==
            true,
      );
      addTearDown(cache.dispose);
      final original = CommunityChatMessage.parse(
        authorPerson(oldPixel),
        officialAuthors: true,
      );
      final replacement = CommunityChatMessage.parse(
        authorPerson(newPixel),
        officialAuthors: true,
      );
      Widget tile(CommunityChatMessage message) => app(
        Center(
          child: SizedBox(
            width: 700,
            child: CommunityChatMessageTile(
              port: port,
              targetRef: 'a' * 32,
              message: message,
              mediaCache: cache,
              authorIsCurrent: (candidate) =>
                  candidate.authorIdentity
                      ?.admit(DateTime.utc(2026, 10, 17, 12))
                      .visible ==
                  true,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(tile(original));
      expect(port.detailReads, 1);
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      await tester.pumpWidget(tile(replacement));
      expect(find.byType(RawImage), findsNothing);
      port.gates[0].complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
      expect(
        port.detailReads,
        2,
        reason: 'Finish the same content, then acquire only the latest still-admitted person once.',
      );
      expect(
        find.byType(RawImage),
        findsNothing,
        reason: 'The prior avatar cannot fill the replacement person.',
      );
      port.gates[1].complete();
      await tester.pumpAndSettle();
      final shown = tester.widget<RawImage>(find.byType(RawImage)).image!;
      final actual = (await tester.runAsync(() => shown.toByteData()))!;
      final expected = (await tester.runAsync(() => newImage.toByteData()))!;
      expect(
        actual.buffer.asUint8List(),
        orderedEquals(expected.buffer.asUint8List()),
      );
      expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
      expect(find.text('Authorized expiry body'), findsOneWidget);
      expect(port.detailReads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('retiring a person keeps the in-flight authorized attachment', (
    tester,
  ) async {
    final pixel = (await tester.runAsync(syntheticPixel))!;
    final port = ExpiryAuthorPort(pixel)..detailGate = Completer<void>();
    addTearDown(port.changes.close);
    final cache = CommunityChatMediaCache(
      port,
      'a' * 32,
      now: () => DateTime.utc(2026, 10, 17, 12),
      authorIsCurrent: (message) =>
          message.authorIdentity
              ?.admit(DateTime.utc(2026, 10, 17, 12))
              .visible ==
          true,
    );
    addTearDown(cache.dispose);
    final original = CommunityChatMessage.parse(
      port.person,
      officialAuthors: true,
    );
    Widget tile(CommunityChatMessage message) => app(
      Center(
        child: SizedBox(
          width: 700,
          child: CommunityChatMessageTile(
            port: port,
            targetRef: 'a' * 32,
            message: message,
            mediaCache: cache,
            authorIsCurrent: (candidate) =>
                candidate.authorIdentity
                    ?.admit(DateTime.utc(2026, 10, 17, 12))
                    .visible ==
                true,
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(tile(original));
    expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
    expect(port.detailReads, 1);
    await tester.pumpWidget(tile(CommunityChatMessage.neutralAuthor(original)));
    expect(find.textContaining('Bridge wire-visible'), findsNothing);
    expect(find.text('Authorized expiry body'), findsOneWidget);
    port.detailGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.byType(OverlaySharedPresetCard),
      findsOneWidget,
      reason: 'Only the person was retired; the original content read is still authorized.',
    );
    expect(
      find.byType(RawImage),
      findsNothing,
      reason: 'The old combined response must not restore its retired avatar.',
    );
    expect(
      port.detailReads,
      1,
      reason: 'The same in-flight content is consumed without another detail request.',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'the original identity deadline retires the proof while its worker hangs, keeping the seen name',
    (tester) async {
      var now = DateTime.utc(2026, 10, 17, 12);
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final image = (await tester.runAsync(
        () => decodeCommunityImage(pixel, 96),
      ))!;
      addTearDown(image.dispose);
      final avatars = CommunityAvatarCache(now: () => now);
      avatars.images.dispose();
      avatars.images = CommunityImageDecodeCache(
        decoder: (_, _) async => image.clone(),
      );
      addTearDown(avatars.dispose);
      final port = ExpiryAuthorPort(pixel);
      addTearDown(port.changes.close);
      final model = CommunityChatController(port, 'a' * 32, now: () => now);
      addTearDown(model.dispose);
      await model.refresh();
      model.updateDraft('Keep expiry draft');
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        app(
          CommunityChatPanel(
            port: port,
            targetRef: 'a' * 32,
            name: 'Expiry window',
            avatars: avatars,
            controller: model,
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
      port.pageGate = Completer<void>();
      final held = model.refresh(silent: true);
      expect(model.loading, isTrue);
      final requestsBeforeDeadline = port.authorReads;
      final detailsBeforeDeadline = port.detailReads;
      now = DateTime.utc(2026, 10, 17, 12, 0, 5);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      // User decision 2026-10-30: a hanging read holds the seen name and avatar
      // until it ends; the received proof itself has still retired.
      expect(
        find.textContaining('Bridge wire-visible'),
        findsOneWidget,
      );
      expect(find.byType(RawImage), findsOneWidget);
      {
        final heldName = model.presentAuthor(model.messages.single);
        expect(heldName.authorIdentity!.state, CommunityAuthorState.lastSeen);
        expect(model.authorIsCurrent(heldName), isFalse);
      }
      expect(find.text('Authorized expiry body'), findsOneWidget);
      expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
      expect(model.draft, 'Keep expiry draft');
      expect(
        port.authorReads,
        requestsBeforeDeadline,
        reason:
            'Deadline retirement redraws only; it is not another IO worker.',
      );
      expect(
        port.detailReads,
        detailsBeforeDeadline,
        reason: 'Retiring the author must not reread an already authorized attachment.',
      );
      port.pageGate!.complete();
      await held;
      await tester.pumpAndSettle();
      // The read answered visible with a proof already lapsed: it confirms the
      // seen name (user 2026-10-31) but is still no current author.
      expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
      expect(
        model.authorIsCurrent(model.presentAuthor(model.messages.single)),
        isFalse,
      );
      expect(find.text('Authorized expiry body'), findsOneWidget);
      expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
      expect(model.draft, 'Keep expiry draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'typed official chat detail withdraws its author across actual chunks but retains the attachment',
    (tester) async {
      // Controlled future cap x source-open1; explicit consumer-domain page
      // addresses/person metadata align independent actual producer scenarios.
      // The six responses below are original payloads, never reconstructed JSON.
      final chunkNames = [
        'attachment-first',
        'attachment-neutral-2',
        'attachment-neutral-1',
        'attachment-neutral-2',
        'attachment-neutral-3',
        'attachment-neutral-4',
      ];
      final chunks = chunkNames.map(wire).toList();
      final first = chunks.first;
      final author = first['author'] as Map;
      expect(author['identityState'], 'visible');
      expect((chunks[1]['author'] as Map)['identityState'], 'unavailable');
      final neutralBytes = BytesBuilder(copy: false);
      for (final name in [
        'attachment-neutral-1',
        'attachment-neutral-2',
        'attachment-neutral-3',
        'attachment-neutral-4',
      ]) {
        neutralBytes.add(base64Decode(wire(name)['data'] as String));
      }
      final expectedBytes = neutralBytes.takeBytes();
      expect(expectedBytes.length, 589985);
      expect(
        sha256.convert(expectedBytes).toString(),
        wire('attachment-neutral-1')['version'],
      );
      final expectedBody = jsonDecode(utf8.decode(expectedBytes)) as Map;
      expect(expectedBody['avatarImageData'], isNull);
      final expectedAttachment = expectedBody['attachment'] as Map;
      var detailIndex = 0;
      final host = AuthorWireHost(
        authorCapability: true,
        chatPage: (request) => _attachmentChatDomainPage(request.payload),
        chatDetailPage: (_) {
          // An unexpected extra request still gets real original bytes and then
          // fails the exact bounded request assertions; it never hangs on a stub.
          final index = detailIndex++;
          return chunks[index < chunks.length ? index : chunks.length - 1];
        },
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityChatController? cleanupModel;
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
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        final context = await host.adapter.open();
        expect(context.targetRef, first['targetRef']);
        final model = CommunityChatController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        model.setReadingContext(visible: true, foreground: true);
        await model.refresh();
        model.updateDraft('Keep typed attachment draft');
        // Controlled measured-window admission through the original read owner;
        // this is not a physical viewport/device-acceptance claim.
        model.observeAuthors(model.messages);
        await tester.idle();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final admitted = model.presentAuthor(model.messages.single);
        expect(admitted.messageRef, first['messageRef']);
        expect(admitted.senderRef, author['senderRef']);
        expect(admitted.authorIdentity!.version, author['identityVersion']);
        expect(
          admitted.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          admitted.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(admitted.hasAttachment, isTrue);
        expect(model.authorIsCurrent(admitted), isTrue);
        final cache = model.media();
        host.holdNextChatDetail();
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 700,
                child: AnimatedBuilder(
                  animation: model,
                  builder: (_, _) => CommunityChatMessageTile(
                    port: host.adapter,
                    targetRef: context.targetRef,
                    message: model.presentAuthor(model.messages.single),
                    mediaCache: cache,
                    authorIsCurrent: model.authorIsCurrent,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.idle();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.text('authorized body'), findsOneWidget);
        expect(host.chatDetailReadHeld, isTrue);
        final initial = host.requests
            .where((request) => request.payload['action'] == 'chatDetail')
            .single
            .payload;
        expect(initial['targetRef'], first['targetRef']);
        expect(initial['messageRef'], first['messageRef']);
        expect(initial['offset'], 0);
        expect(initial['version'], isNull);
        // The first semantic assertion occurs before any detail response is
        // released, so timeout/legacy-header incompatibility cannot masquerade as
        // evidence that this actual media/cache/Tile request negotiated identities.
        expect(initial['authorIdentitySchemaVersion'], 1);
        expect(
          initial['expectedAuthorIdentityVersion'],
          author['identityVersion'],
        );
        host.releaseChatDetail();
        for (var attempt = 0; attempt < 12; attempt++) {
          await tester.idle();
          await tester.pump();
          if (find.byType(OverlaySharedPresetCard).evaluate().isNotEmpty) break;
        }
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final card = tester.widget<OverlaySharedPresetCard>(
          find.byType(OverlaySharedPresetCard),
        );
        expect(card.name, expectedAttachment['title']);
        final state =
            tester.state(find.byType(CommunityChatMessageTile)) as dynamic;
        expect(
          state.detail.attachment['overlayPresetPackage'],
          expectedAttachment['overlayPresetPackage'],
        );
        expect(state.avatar, isNull);
        expect(find.byType(RawImage), findsNothing);
        // Unavailable is not hidden: the seen name stays, with no authority.
        expect(
          model.presentAuthor(model.messages.single).authorIdentity?.state,
          CommunityAuthorState.lastSeen,
        );
        expect(find.text('authorized body'), findsOneWidget);
        expect(model.messages, hasLength(1));
        expect(model.draft, 'Keep typed attachment draft');
        expect(model.error, isNull);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'chatDetail')
            .toList();
        expect(reads, hasLength(6));
        expect(detailIndex, 6);
        expect(reads.map((request) => request.payload['offset']), [
          0,
          196608,
          0,
          196608,
          393216,
          589824,
        ]);
        expect(reads.map((request) => request.payload['version']), [
          null,
          first['version'],
          null,
          chunks[2]['version'],
          chunks[2]['version'],
          chunks[2]['version'],
        ]);
        for (final read in reads) {
          expect(read.payload['targetRef'], first['targetRef']);
          expect(read.payload['messageRef'], first['messageRef']);
          expect(read.payload['authorIdentitySchemaVersion'], 1);
          expect(
            read.payload['expectedAuthorIdentityVersion'],
            author['identityVersion'],
          );
        }
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
    'only losing the author capability mid-chunks preserves authorized chat content and the attachment',
    (tester) async {
      // The producer exported one visible first chunk and all four neutral
      // chunks. Restore only its original complete PNG URI into the unchanged
      // neutral body: the resulting full bytes must equal the original visible
      // content hash and its exported first chunk. Later visible chunks below
      // are explicit consumer-domain segmentation, not additional producer wire.
      final first = wire('attachment-first');
      final author = first['author'] as Map;
      expect(author['identityState'], 'visible');
      final bodyBytes = BytesBuilder(copy: false);
      for (var index = 1; index <= 4; index++) {
        bodyBytes.add(
          base64Decode(wire('attachment-neutral-$index')['data'] as String),
        );
      }
      final neutralText = utf8.decode(bodyBytes.takeBytes());
      final firstText = utf8.decode(base64Decode(first['data'] as String));
      final encodedAvatar = RegExp(r'^\{"avatarImageData":("[^"]+"),')
          .firstMatch(firstText)!
          .group(1)!;
      final visibleBytes = Uint8List.fromList(
        utf8.encode(
          neutralText.replaceFirst(
            '{"avatarImageData":null,',
            '{"avatarImageData":$encodedAvatar,',
          ),
        ),
      );
      expect(visibleBytes.length, first['totalBytes']);
      expect(visibleBytes.length, 593877);
      expect(sha256.convert(visibleBytes).toString(), first['version']);
      expect(base64Encode(visibleBytes.sublist(0, 192 * 1024)), first['data']);
      final visibleBody = jsonDecode(utf8.decode(visibleBytes)) as Map;
      final avatarUri = visibleBody['avatarImageData'] as String;
      expect(
        sha256.convert(utf8.encode(avatarUri)).toString(),
        author['avatarVersion'],
      );
      final pixel = base64Decode(avatarUri.split(',').last);
      final image = (await tester.runAsync(
        () => decodeCommunityImage(pixel, 96),
      ))!;
      addTearDown(image.dispose);
      expect(image.width, 48);
      expect(image.height, 48);
      final attachment = visibleBody['attachment'] as Map;
      final chunks = <Map<String, Object?>>[];
      for (var offset = 0; offset < visibleBytes.length; offset += 192 * 1024) {
        final end = (offset + 192 * 1024).clamp(0, visibleBytes.length);
        chunks.add({
          ...first,
          'offset': offset,
          'next': end < visibleBytes.length ? end : null,
          'data': base64Encode(visibleBytes.sublist(offset, end)),
        });
      }
      expect(chunks, hasLength(4));
      expect(
        chunks.every(
          (chunk) => (chunk['author'] as Map)['identityState'] == 'visible',
        ),
        isTrue,
      );
      var detailIndex = 0;
      late final AuthorWireHost host;
      host = AuthorWireHost(
        authorCapability: true,
        chatPage: (request) => _attachmentChatDomainPage(request.payload),
        chatDetailPage: (_) {
          final index = detailIndex++;
          // Arm the existing gate after the actual first response. The next
          // real request must be held at offset196608, before cap retirement.
          if (index == 0) host.holdNextChatDetail();
          return chunks[index < chunks.length ? index : chunks.length - 1];
        },
      );
      addTearDown(host.close);
      addTearDown(host.adapter.close);
      CommunityChatController? cleanupModel;
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
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        final context = await host.adapter.open();
        final generation = host.session.activeGeneration;
        final model = CommunityChatController(
          host.adapter,
          context.targetRef,
          now: () => DateTime.utc(2026, 10, 17, 12, 0, 1),
        );
        cleanupModel = model;
        model.setReadingContext(visible: true, foreground: true);
        await model.refresh();
        model.updateDraft('Keep cap-only attachment draft');
        model.observeAuthors(model.messages);
        await tester.idle();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        final admitted = model.presentAuthor(model.messages.single);
        expect(admitted.messageRef, first['messageRef']);
        expect(admitted.senderRef, author['senderRef']);
        expect(admitted.authorIdentity!.version, author['identityVersion']);
        expect(
          admitted.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          admitted.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(model.authorIsCurrent(admitted), isTrue);
        final cache = model.media();
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 700,
                child: AnimatedBuilder(
                  animation: model,
                  builder: (_, _) => CommunityChatMessageTile(
                    port: host.adapter,
                    targetRef: context.targetRef,
                    message: model.presentAuthor(model.messages.single),
                    mediaCache: cache,
                    authorIsCurrent: model.authorIsCurrent,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.idle();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.text('authorized body'), findsOneWidget);
        expect(host.chatDetailReadHeld, isTrue);
        expect(
          detailIndex,
          1,
          reason:
              'The original first chunk has been delivered, the next has not.',
        );
        final inFlight = host.requests
            .where((request) => request.payload['action'] == 'chatDetail')
            .toList();
        expect(inFlight, hasLength(2));
        expect(inFlight.map((request) => request.payload['offset']), [
          0,
          196608,
        ]);
        expect(inFlight[1].payload['version'], first['version']);
        for (final request in inFlight) {
          expect(request.payload['authorIdentitySchemaVersion'], 1);
          expect(
            request.payload['expectedAuthorIdentityVersion'],
            author['identityVersion'],
          );
        }
        final state =
            tester.state(find.byType(CommunityChatMessageTile)) as dynamic;
        expect(state.loading, isTrue);
        expect(find.byType(OverlaySharedPresetCard), findsNothing);
        final readsBefore = host.requests
            .where((request) => request.payload['action'] == 'chat')
            .length;
        final opensBefore = host.requests
            .where((request) => request.payload['action'] == 'open')
            .length;
        host.session.acceptHostCapabilities(['officialFleet.communication']);
        await tester.idle();
        expect(
          host.session.hostCapabilities,
          contains('officialFleet.communication'),
        );
        expect(
          host.session.hostCapabilities,
          isNot(contains('officialFleet.communication.authorIdentities')),
        );
        expect(
          (host.adapter as CommunityAuthorProjectionPort)
              .authorIdentitiesAvailable,
          isFalse,
        );
        expect(host.adapter.chatAvailable, isTrue);
        expect(host.adapter.chatSendAvailable, isTrue);
        expect(host.session.activeGeneration, generation);
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(state.avatar, isNull);
        expect(model.authorIsCurrent(admitted), isFalse);
        expect(model.presentAuthor(model.messages.single).callsign, isEmpty);
        expect(host.chatDetailReadHeld, isTrue);
        expect(detailIndex, 1);
        expect(find.text('authorized body'), findsOneWidget);
        expect(model.draft, 'Keep cap-only attachment draft');
        expect(model.error, isNull);
        expect(
          host.requests
              .where((request) => request.payload['action'] == 'chat')
              .length,
          readsBefore,
        );
        host.releaseChatDetail();
        for (var attempt = 0; attempt < 12; attempt++) {
          await tester.idle();
          await tester.pump();
          if (find.byType(OverlaySharedPresetCard).evaluate().isNotEmpty) break;
        }
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final card = tester.widget<OverlaySharedPresetCard>(
          find.byType(OverlaySharedPresetCard),
        );
        expect(card.name, attachment['title']);
        expect(
          state.detail.attachment['overlayPresetPackage'],
          attachment['overlayPresetPackage'],
        );
        expect(state.loading, isFalse);
        expect(state.failed, isFalse);
        expect(state.avatar, isNull);
        expect(find.byType(RawImage), findsNothing);
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        final retained = cache.peek(admitted)!;
        expect(retained.avatar, isNull);
        expect(retained.authorCurrent!(), isFalse);
        expect(
          retained.attachment!['overlayPresetPackage'],
          attachment['overlayPresetPackage'],
        );
        expect(find.text('authorized body'), findsOneWidget);
        expect(model.messages, hasLength(1));
        expect(model.draft, 'Keep cap-only attachment draft');
        expect(model.error, isNull);
        final reads = host.requests
            .where((request) => request.payload['action'] == 'chatDetail')
            .toList();
        expect(reads, hasLength(4));
        expect(detailIndex, 4);
        expect(reads.map((request) => request.payload['offset']), [
          0,
          196608,
          393216,
          589824,
        ]);
        expect(reads.map((request) => request.payload['version']), [
          null,
          first['version'],
          first['version'],
          first['version'],
        ]);
        for (var index = 0; index < reads.length; index++) {
          final request = reads[index].payload;
          expect(request['targetRef'], context.targetRef);
          expect(request['messageRef'], first['messageRef']);
          expect(request['sourceRef'], 'officialFleet:7');
          expect(reads[index].sessionGeneration, generation);
          expect(
            request['authorIdentitySchemaVersion'],
            index < 2 ? 1 : isNull,
          );
          expect(
            request['expectedAuthorIdentityVersion'],
            index < 2 ? author['identityVersion'] : isNull,
          );
        }
        expect(
          host.requests
              .where((request) => request.payload['action'] == 'chat')
              .length,
          readsBefore,
        );
        expect(
          host.requests
              .where((request) => request.payload['action'] == 'open')
              .length,
          opensBefore,
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
        expect(host.session.activeGeneration, generation);
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'expired official chat identity never becomes current after clock rollback without a new read',
    (tester) async {
      // Existing synthetic-domain pixel/content/attachment fixture, with unchanged
      // actual-producer author00->05. This does not claim a new producer response.
      var now = DateTime.utc(2026, 10, 17, 12);
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final image = (await tester.runAsync(
        () => decodeCommunityImage(pixel, 96),
      ))!;
      addTearDown(image.dispose);
      final avatars = CommunityAvatarCache(now: () => now);
      avatars.images.dispose();
      avatars.images = CommunityImageDecodeCache(
        decoder: (_, _) async => image.clone(),
      );
      addTearDown(avatars.dispose);
      final port = ExpiryAuthorPort(pixel);
      addTearDown(port.changes.close);
      final model = CommunityChatController(port, 'a' * 32, now: () => now);
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);
      Future<void>? held;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        model.setReadingContext(visible: false, foreground: false);
        model.dispose();
        final gate = port.pageGate;
        if (gate != null && !gate.isCompleted) gate.complete();
        final pending = held;
        if (pending != null) await pending;
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        model.setReadingContext(visible: true, foreground: true);
        await model.refresh();
        model.observeAuthors(model.messages);
        await tester.idle();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        model.updateDraft('Keep rollback draft');
        final admitted = model.presentAuthor(model.messages.single);
        expect(
          admitted.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          admitted.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(model.authorIsCurrent(admitted), isTrue);
        final cache = model.media(avatars: avatars);
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 700,
                child: AnimatedBuilder(
                  animation: Listenable.merge([model, repaint]),
                  builder: (_, _) => CommunityChatMessageTile(
                    port: port,
                    targetRef: 'a' * 32,
                    message: model.presentAuthor(model.messages.single),
                    mediaCache: cache,
                    authorIsCurrent: model.authorIsCurrent,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final shown = tester.widget<RawImage>(find.byType(RawImage)).image!;
        final actual = (await tester.runAsync(() => shown.toByteData()))!;
        final expected = (await tester.runAsync(() => image.toByteData()))!;
        expect(
          actual.buffer.asUint8List(),
          orderedEquals(expected.buffer.asUint8List()),
        );
        port.pageGate = Completer<void>();
        held = model.refresh(silent: true);
        expect(model.loading, isTrue);
        final pagesBeforeDeadline = port.authorReads,
            detailsBeforeDeadline = port.detailReads;
        now = DateTime.utc(2026, 10, 17, 12, 0, 5);
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        // User decision 2026-10-30: the seen name stays until a read ends.
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(model.draft, 'Keep rollback draft');
        expect(port.authorReads, pagesBeforeDeadline);
        expect(port.detailReads, detailsBeforeDeadline);
        now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        // Fixture-only pure repaint; no refresh, new observation or product API.
        repaint.value++;
        await tester.pump();
        {
          final heldName = model.presentAuthor(model.messages.single);
          expect(heldName.authorIdentity!.state, CommunityAuthorState.lastSeen);
          expect(model.authorIsCurrent(heldName), isFalse);
        }
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'A retired proof stays retired when the clock rolls back; only the seen name shows.',
        );
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(model.draft, 'Keep rollback draft');
        expect(port.authorReads, pagesBeforeDeadline);
        expect(port.detailReads, detailsBeforeDeadline);
        expect(
          model.loading,
          isTrue,
          reason: 'The old worker response has not been released.',
        );
        // Nobody reading in front: no former name, not even the seen one.
        model.setReadingContext(visible: true, foreground: false);
        repaint.value++;
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'chat deadline retirement preserves the other independently valid peer and current content cache',
    (tester) async {
      // Explicit typed-domain peer03->08; the first received proof remains00->05.
      // This is a bounded presentation test, not an additional producer scenario.
      var now = DateTime.utc(2026, 10, 17, 12, 0, 4);
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final image = (await tester.runAsync(
        () => decodeCommunityImage(pixel, 96),
      ))!;
      addTearDown(image.dispose);
      final avatars = CommunityAvatarCache(now: () => now);
      avatars.images.dispose();
      avatars.images = CommunityImageDecodeCache(
        decoder: (_, _) async => image.clone(),
      );
      addTearDown(avatars.dispose);
      final port = PeerExpiryAuthorPort(pixel);
      addTearDown(port.changes.close);
      final model = CommunityChatController(port, 'a' * 32, now: () => now);
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        model.setReadingContext(visible: false, foreground: false);
        model.dispose();
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        model.setReadingContext(visible: true, foreground: true);
        await model.refresh();
        model.observeAuthors(model.messages);
        await tester.idle();
        expect(model.messages, hasLength(2));
        expect(model.error, isNull);
        model.updateDraft('Keep independent peers');
        final admitted = model.presentAuthor(model.messages.first);
        final peer = model.presentAuthor(model.messages.last);
        expect(
          admitted.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          admitted.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(
          peer.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12, 0, 3),
        );
        expect(
          peer.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 8),
        );
        final cache = model.media(avatars: avatars);
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 700,
                child: AnimatedBuilder(
                  animation: Listenable.merge([model, repaint]),
                  builder: (_, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final message in model.messages)
                        CommunityChatMessageTile(
                          key: ValueKey(message.messageRef),
                          port: port,
                          targetRef: 'a' * 32,
                          message: model.presentAuthor(message),
                          mediaCache: cache,
                          authorIsCurrent: model.authorIsCurrent,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.textContaining('Bridge independent-peer'), findsOneWidget);
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final firstTile = find.byWidgetPredicate(
          (widget) =>
              widget is CommunityChatMessageTile &&
              widget.message.messageRef == admitted.messageRef,
        );
        final state = tester.state(firstTile) as dynamic;
        expect(state.avatar, orderedEquals(pixel));
        final before = cache.peek(admitted)!;
        expect(before.avatar, orderedEquals(pixel));
        expect(before.attachment, isNotNull);
        final attachment = before.attachment, preview = before.preview;
        final shown = tester.widget<RawImage>(find.byType(RawImage)).image!;
        final actual = (await tester.runAsync(() => shown.toByteData()))!;
        final expected = (await tester.runAsync(() => image.toByteData()))!;
        expect(
          actual.buffer.asUint8List(),
          orderedEquals(expected.buffer.asUint8List()),
        );
        final pages = port.authorReads, details = port.detailReads;
        now = DateTime.utc(2026, 10, 17, 12, 0, 5);
        await tester.pump(const Duration(seconds: 1));
        // User decision 2026-10-30: the seen name stays until a read ends; the
        // proof, its avatar and the peer's own proof still retire separately.
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(
          model.presentAuthor(model.messages.first).authorIdentity!.state,
          CommunityAuthorState.lastSeen,
        );
        expect(find.textContaining('Bridge independent-peer'), findsOneWidget);
        expect(
          model.presentAuthor(model.messages.last).authorIdentity!.state,
          CommunityAuthorState.visible,
        );
        expect(find.byType(RawImage), findsNothing);
        expect(state.avatar, isNull);
        expect(state.detail.attachment, same(attachment));
        expect(state.preview, same(preview));
        final retained = cache.peek(admitted)!;
        expect(retained.avatar, isNull);
        expect(retained.authorCurrent!(), isFalse);
        expect(retained.attachment, same(attachment));
        expect(retained.preview, same(preview));
        expect(port.authorReads, pages);
        expect(port.detailReads, details);
        now = DateTime.utc(2026, 10, 17, 12, 0, 8);
        await tester.pump(const Duration(seconds: 3));
        expect(find.textContaining('Bridge independent-peer'), findsOneWidget);
        expect(
          model.presentAuthor(model.messages.last).authorIdentity!.state,
          CommunityAuthorState.lastSeen,
        );
        now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        repaint.value++;
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.textContaining('Bridge independent-peer'), findsOneWidget);
        for (final message in model.messages) {
          expect(model.authorIsCurrent(model.presentAuthor(message)), isFalse);
        }
        expect(state.avatar, isNull);
        expect(cache.peek(admitted)!.avatar, isNull);
        expect(cache.peek(admitted)!.attachment, same(attachment));
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(find.text('Authorized peer body'), findsOneWidget);
        expect(model.draft, 'Keep independent peers');
        expect(port.authorReads, pages);
        expect(port.detailReads, details);
        // Nobody reading in front: no former name, not even the seen one.
        model.setReadingContext(visible: true, foreground: false);
        repaint.value++;
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(find.textContaining('Bridge independent-peer'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
  testWidgets(
    'an old held chat proof cannot make its retired owner current after clock rollback',
    (tester) async {
      // Existing synthetic-domain pixel/content/attachment fixture, with unchanged
      // actual-producer author00->05. This does not claim a new producer response.
      var now = DateTime.utc(2026, 10, 17, 12);
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final image = (await tester.runAsync(
        () => decodeCommunityImage(pixel, 96),
      ))!;
      addTearDown(image.dispose);
      final avatars = CommunityAvatarCache(now: () => now);
      avatars.images.dispose();
      avatars.images = CommunityImageDecodeCache(
        decoder: (_, _) async => image.clone(),
      );
      addTearDown(avatars.dispose);
      final port = ExpiryAuthorPort(pixel);
      addTearDown(port.changes.close);
      final model = CommunityChatController(port, 'a' * 32, now: () => now);
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);
      Future<void>? held;
      var retiredFixture = false;
      Future<void> retireWidgetFixture() async {
        if (retiredFixture) return;
        retiredFixture = true;
        await tester.pumpWidget(const SizedBox());
        model.setReadingContext(visible: false, foreground: false);
        model.dispose();
        final gate = port.pageGate;
        if (gate != null && !gate.isCompleted) gate.complete();
        final pending = held;
        if (pending != null) await pending;
        await tester.idle();
      }

      addTearDown(retireWidgetFixture);
      try {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        model.setReadingContext(visible: true, foreground: true);
        await model.refresh();
        model.observeAuthors(model.messages);
        await tester.idle();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        model.updateDraft('Keep rollback draft');
        final admitted = model.presentAuthor(model.messages.single);
        expect(
          admitted.authorIdentity!.observedAt,
          DateTime.utc(2026, 10, 17, 12),
        );
        expect(
          admitted.authorIdentity!.validUntil,
          DateTime.utc(2026, 10, 17, 12, 0, 5),
        );
        expect(model.authorIsCurrent(admitted), isTrue);
        final cache = model.media(avatars: avatars);
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 700,
                child: AnimatedBuilder(
                  animation: Listenable.merge([model, repaint]),
                  builder: (_, _) => CommunityChatMessageTile(
                    port: port,
                    targetRef: 'a' * 32,
                    message: model.presentAuthor(model.messages.single),
                    mediaCache: cache,
                    authorIsCurrent: model.authorIsCurrent,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final shown = tester.widget<RawImage>(find.byType(RawImage)).image!;
        final actual = (await tester.runAsync(() => shown.toByteData()))!;
        final expected = (await tester.runAsync(() => image.toByteData()))!;
        expect(
          actual.buffer.asUint8List(),
          orderedEquals(expected.buffer.asUint8List()),
        );
        port.pageGate = Completer<void>();
        held = model.refresh(silent: true);
        expect(model.loading, isTrue);
        final pagesBeforeDeadline = port.authorReads,
            detailsBeforeDeadline = port.detailReads;
        now = DateTime.utc(2026, 10, 17, 12, 0, 5);
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        // User decision 2026-10-30: the seen name stays until a read ends.
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(model.draft, 'Keep rollback draft');
        expect(port.authorReads, pagesBeforeDeadline);
        expect(port.detailReads, detailsBeforeDeadline);
        now = DateTime.utc(2026, 10, 17, 12, 0, 4);
        // Fixture-only pure repaint; no refresh, new observation or product API.
        repaint.value++;
        await tester.pump();
        {
          final heldName = model.presentAuthor(model.messages.single);
          expect(heldName.authorIdentity!.state, CommunityAuthorState.lastSeen);
          expect(model.authorIsCurrent(heldName), isFalse);
        }
        expect(
          find.textContaining('Bridge wire-visible'),
          findsOneWidget,
          reason: 'A retired proof stays retired when the clock rolls back; only the seen name shows.',
        );
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(model.draft, 'Keep rollback draft');
        expect(port.authorReads, pagesBeforeDeadline);
        expect(port.detailReads, detailsBeforeDeadline);
        expect(
          model.loading,
          isTrue,
          reason: 'The old worker response has not been released.',
        );
        port.pageGate!.complete();
        await held;
        held = null;
        await tester.pump();
        expect(model.loading, isFalse);
        expect(model.error, isNull);
        // Its lapsed proof confirms the seen name, and no more than that.
        expect(find.textContaining('Bridge wire-visible'), findsOneWidget);
        expect(
          model.authorIsCurrent(model.presentAuthor(model.messages.single)),
          isFalse,
        );
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(OverlaySharedPresetCard), findsOneWidget);
        final state =
            tester.state(find.byType(CommunityChatMessageTile)) as dynamic;
        expect(state.avatar, isNull);
        expect(state.detail.attachment, isNotNull);
        expect(cache.peek(admitted)!.avatar, isNull);
        expect(cache.peek(admitted)!.attachment, same(state.detail.attachment));
        expect(find.text('Authorized expiry body'), findsOneWidget);
        expect(model.draft, 'Keep rollback draft');
        expect(port.authorReads, pagesBeforeDeadline);
        expect(port.detailReads, detailsBeforeDeadline);
        // Nobody reading in front: no former name, not even the seen one.
        model.setReadingContext(visible: true, foreground: false);
        repaint.value++;
        await tester.pump();
        expect(find.textContaining('Bridge wire-visible'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await retireWidgetFixture();
      }
    },
  );
}

/// All pixels are generated in this test. Person metadata retains the original
/// actual-producer UTC deadline; content/attachment are explicitly synthetic.
Future<Uint8List> syntheticPixel({int color = 0xff2468ac}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(color), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

final class ExpiryAuthorPort
    implements
        CommunityChatPort,
        CommunityAuthorProjectionPort,
        CommunityChatAuthorDetailPort {
  ExpiryAuthorPort(this.pixel);
  final Uint8List pixel;
  final changes = StreamController<void>.broadcast(sync: true);
  Completer<void>? pageGate, detailGate;
  int authorReads = 0, detailReads = 0;
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
  Map<String, Object?> get person => authorPerson(pixel);
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
    authorReads++;
    await pageGate?.future;
    return CommunityChatPage.parse({
      ...wire('chat-current-visible'),
      'targetRef': targetRef,
      'messages': [if (after == 0 && before == 0) person],
      'oldestSequence': after == 0 && before == 0 ? 1 : 0,
      'authorUpdates': [
        for (final ref in observeMessageRefs)
          if (ref == person['messageRef']) {...person, 'recordState': 'found'},
      ],
    }, officialAuthors: true);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    detailReads++;
    await detailGate?.future;
    final bytes = utf8.encode(
      jsonEncode({
        'avatarImageData': 'data:image/png;base64,${base64Encode(pixel)}',
        'attachment': {
          'kind': 'overlay_preset',
          'title': 'Authorized attachment',
          'summary': '',
          'overlayPresetPackage': jsonEncode({
            'version': 1,
            'name': 'Synthetic',
            'settings': '{}',
            'layout': '{}',
          }),
        },
      }),
    );
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes),
    };
  }

  Map<String, Object?> detailPerson(String? expected) => person;
  @override
  Future<Map<String, Object?>> readChatAuthorDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
  }) async {
    // Explicit typed synthetic-domain provider. Original gates/body remain the
    // actual race owner; none of these maps substitutes for producer wire tests.
    final row = await readChatDetail(targetRef, messageRef, offset, version);
    final source = detailPerson(expectedAuthorIdentityVersion);
    final proof = CommunityAuthorProjection.chat(source);
    final admitted = proof.version == expectedAuthorIdentityVersion
        ? proof
        : const CommunityAuthorProjection.unavailable();
    return {
      ...row,
      'authorRefreshRequired': !admitted.visible,
      'author': {'senderRef': source['senderRef'], ...admitted.personFields},
    };
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => throw StateError('Observation is not a receipt');
}

/// Synthetic person variants recompute both exact content hashes; the actual
/// producer name/UTC remain unchanged. This is a controlled consumer race.
Map<String, Object?> authorPerson(Uint8List pixel) {
  final original = Map<String, Object?>.from(
    (wire('chat-current-visible')['messages'] as List).single as Map,
  );
  final avatar = sha256
      .convert(utf8.encode('data:image/png;base64,${base64Encode(pixel)}'))
      .toString();
  return {
    ...original,
    'text': 'Authorized expiry body',
    'hasAttachment': true,
    'avatarVersion': avatar,
    'authorIdentityVersion': sha256
        .convert(
          utf8.encode(
            'StarBridge.OfficialFleet.CommunicationAuthor.v1\n${jsonEncode([original['senderCallsign'], avatar])}',
          ),
        )
        .toString(),
  };
}

final class ChangingAvatarPort extends ExpiryAuthorPort {
  ChangingAvatarPort(super.pixel, this.nextPixel);
  final Uint8List nextPixel;
  final gates = [Completer<void>(), Completer<void>()];
  @override
  Map<String, Object?> detailPerson(String? expected) {
    final next = authorPerson(nextPixel);
    return next['authorIdentityVersion'] == expected
        ? next
        : super.detailPerson(expected);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    final index = detailReads++;
    if (index >= gates.length) throw StateError('Unbounded avatar reread');
    await gates[index].future;
    final bytes = utf8.encode(
      jsonEncode({
        'avatarImageData':
            'data:image/png;base64,${base64Encode(index == 0 ? pixel : nextPixel)}',
        'attachment': {
          'kind': 'overlay_preset',
          'title': 'Authorized attachment',
          'summary': '',
          'overlayPresetPackage': jsonEncode({
            'version': 1,
            'name': 'Synthetic',
            'settings': '{}',
            'layout': '{}',
          }),
        },
      }),
    );
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes),
    };
  }
}

/// Explicit consumer-domain page alignment only. Metadata, name/hash and UTC
/// come from original attachment-first; neutral chunks remain actual bytes.
Map<String, Object?> _attachmentChatDomainPage(Map<String, Object?> request) {
  final page = wire('chat-current-visible'), detail = wire('attachment-first');
  final original = (page['messages'] as List).single as Map;
  final person = detail['author'] as Map;
  final message = <String, Object?>{
    ...Map<String, Object?>.from(original),
    'messageRef': detail['messageRef'],
    'senderRef': person['senderRef'],
    'senderCallsign': person['callsign'],
    'senderGameId': person['gameId'],
    'senderRoleTitle': person['roleTitle'],
    'senderRoleColor': person['roleColor'],
    'hasAvatar': person['hasAvatar'],
    'avatarVersion': person['avatarVersion'],
    'authorIdentityState': person['identityState'],
    'authorIdentityVersion': person['identityVersion'],
    'identityObservedAtUtc': person['identityObservedAtUtc'],
    'identityValidUntilUtc': person['identityValidUntilUtc'],
    'hasAttachment': true,
  };
  final incremental = (request['after'] as int? ?? 0) > 0;
  final observed = request['observeMessageRefs'] as List? ?? [];
  return {
    ...page,
    'targetRef': detail['targetRef'],
    'messages': [if (!incremental) message],
    'oldestSequence': incremental ? 0 : 1,
    'authorUpdates': [
      if (observed.contains(message['messageRef']))
        {...message, 'recordState': 'found'},
    ],
  };
}

final class PeerExpiryAuthorPort extends ExpiryAuthorPort {
  PeerExpiryAuthorPort(super.pixel);
  Map<String, Object?> get peer {
    final name = 'Bridge independent-peer';
    return {
      ...person,
      'sequence': 2,
      'messageRef': 'e' * 32,
      'senderRef': 'd' * 32,
      'senderCallsign': name,
      'text': 'Authorized peer body',
      'hasAvatar': false,
      'avatarVersion': null,
      'hasAttachment': false,
      'authorIdentityVersion': sha256
          .convert(
            utf8.encode(
              'StarBridge.OfficialFleet.CommunicationAuthor.v1\n${jsonEncode([name, null])}',
            ),
          )
          .toString(),
      'identityObservedAtUtc': '2026-10-17T12:00:03Z',
      'identityValidUntilUtc': '2026-10-17T12:00:08Z',
    };
  }

  @override
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  }) async {
    authorReads++;
    await pageGate?.future;
    final records = [person, peer];
    return CommunityChatPage.parse({
      ...wire('chat-current-visible'),
      'targetRef': targetRef,
      'latestSequence': 2,
      'unreadCount': 2,
      'messages': [if (after == 0 && before == 0) ...records],
      'oldestSequence': after == 0 && before == 0 ? 1 : 0,
      'authorUpdates': [
        for (final record in records)
          if (observeMessageRefs.contains(record['messageRef']))
            {...record, 'recordState': 'found'},
      ],
    }, officialAuthors: true);
  }
}
