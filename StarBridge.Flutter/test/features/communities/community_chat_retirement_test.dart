import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import 'community_author_media_retirement_test.dart'
    show ExpiryAuthorPort, syntheticPixel;
import '../official_fleet/official_fleet_author_wire_test.dart' show wire;

final _start = DateTime.utc(2026, 10, 17, 12);

void main() {
  for (final observation in [2, 3]) {
    testWidgets(
      'avatar-free fence survives expiry and rejects observation $observation',
      (tester) async {
        final pixel = (await tester.runAsync(syntheticPixel))!;
        final port = _RetirementPort(pixel);
        addTearDown(port.delegate.changes.close);
        var elapsed = Duration.zero;
        final model = CommunityChatController(
          port,
          'a' * 32,
          now: () => _start.add(elapsed),
          elapsed: () => elapsed,
        );
        addTearDown(model.dispose);
        await _prime(model, tester); // observedAt=0, validUntil=5.
        final original = model.presentAuthor(model.messages.first);
        final sender = original.senderRef, version = original.avatarVersion!;
        model.seenAuthors.rememberAvatar(sender, version, pixel);
        elapsed = const Duration(seconds: 3);
        await tester.pump(elapsed);
        port.detailAvatarFree = true;
        port.detailObservationSeconds = 3;
        await model.media().load(original);
        expect(model.seenAuthors.avatarOf(sender), isNull);
        expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);

        elapsed = const Duration(seconds: 15);
        await tester.pump(const Duration(seconds: 12));
        expect(model.presentAuthor(model.messages.first).callsign, isEmpty);
        elapsed = const Duration(seconds: 16);
        await tester.pump(const Duration(seconds: 1));
        port.observationSeconds = observation;
        await model.refresh(silent: true, renewal: true);
        model.seenAuthors.confirmAvatar(sender, version, pixel);
        expect(model.presentAuthor(model.messages.first).hasAvatar, isFalse);
        expect(model.seenAuthors.avatarOf(sender), isNull);
        expect(model.authorIsCurrent(model.messages.first), isFalse);
        expect(
          model.presentAuthor(model.messages.first).callsign,
          isNotEmpty,
          reason: 'Avatar-only narrowing does not withdraw the name.',
        );

        port.observationSeconds = 4;
        await model.refresh(silent: true, renewal: true);
        expect(model.presentAuthor(model.messages.first).hasAvatar, isTrue);
        expect(model.authorIsCurrent(model.messages.first), isTrue);
        model.seenAuthors.confirmAvatar(sender, version, pixel);
        expect(model.seenAuthors.avatarOf(sender), orderedEquals(pixel));
        // A successful newer answer must not erase the narrowing watermark.
        port.observationSeconds = observation;
        await model.refresh(silent: true, renewal: true);
        expect(model.presentAuthor(model.messages.first).hasAvatar, isFalse);
        expect(model.messages.first.text, 'Authorized body 1');
        model.setReadingContext(visible: false, foreground: false);
      },
    );
  }

  for (final seconds in [1, 3]) {
    testWidgets('hidden rejects in-flight visible at second $seconds', (
      tester,
    ) async {
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final port = _RetirementPort(pixel);
      addTearDown(port.delegate.changes.close);
      var elapsed = Duration.zero;
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => _start.add(elapsed),
        elapsed: () => elapsed,
      );
      addTearDown(model.dispose);
      await _prime(model, tester);
      final admitted = model.presentAuthor(model.messages.first);
      model.seenAuthors.rememberAvatar(
        admitted.senderRef,
        admitted.avatarVersion!,
        pixel,
      );
      port.observationSeconds = seconds;
      port.pageGate = Completer<void>();
      final pending = model.refresh(silent: true, renewal: true);
      expect(model.loading, isTrue);
      elapsed = const Duration(seconds: 2);
      port.detailHidden = true;
      final detail = await model.media().load(admitted);
      expect(detail.attachment, isNotNull);
      expect(model.presentAuthor(model.messages.first).callsign, isEmpty);
      port.pageGate!.complete();
      expect((await pending)?.renewal, isTrue);
      expect(model.error, isNull);
      expect(
        model.messages.every(
          (row) => model.presentAuthor(row).callsign.isEmpty,
        ),
        isTrue,
        reason: 'A pre-hidden request cannot restore either row, even with a later timestamp.',
      );
      expect(model.seenAuthors.avatarOf(admitted.senderRef), isNull);
      expect(model.authorIsCurrent(admitted), isFalse);

      port.pageGate = null;
      port.observationSeconds = 2;
      await model.refresh(silent: true, renewal: true);
      expect(
        model.presentAuthor(model.messages.first).callsign,
        isEmpty,
        reason:
            'A post-hidden request still needs an observation after hidden.',
      );
      port.observationSeconds = 3;
      await model.refresh(silent: true, renewal: true);
      expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);
      expect(model.presentAuthor(model.messages.first).hasAvatar, isTrue);
      expect(model.messages.first.text, 'Authorized body 1');
      model.setReadingContext(visible: false, foreground: false);
    });
  }

  for (final detailSecond in [0, 1, 3]) {
    testWidgets(
      'avatar-free detail at $detailSecond compares with newer page',
      (tester) async {
        final pixel = (await tester.runAsync(syntheticPixel))!;
        final port = _RetirementPort(pixel);
        addTearDown(port.delegate.changes.close);
        final model = CommunityChatController(
          port,
          'a' * 32,
          now: () => _start,
          elapsed: () => Duration.zero,
        );
        addTearDown(model.dispose);
        await _prime(model, tester);
        final old = model.presentAuthor(model.messages.first);
        model.seenAuthors.rememberAvatar(
          old.senderRef,
          old.avatarVersion!,
          pixel,
        );
        port.delegate.detailGate = Completer<void>();
        port.detailAvatarFree = true;
        port.detailObservationSeconds = detailSecond;
        final pending = model.media().load(old);
        expect(port.delegate.detailReads, 1);
        port.observationSeconds = 1;
        await model.refresh(silent: true);
        final current = model.presentAuthor(model.messages.first);
        expect(
          current.authorIdentity!.observedAt,
          _start.add(const Duration(seconds: 1)),
        );
        expect(model.authorIsCurrent(old), isFalse);
        expect(model.seenAuthors.avatarOf(old.senderRef), orderedEquals(pixel));
        final gate = port.delegate.detailGate!;
        port.delegate.detailGate = null;
        port.detailAvatarFree = false;
        final currentMedia = await model.media().load(current);
        expect(currentMedia.avatar, orderedEquals(pixel));
        expect(model.media().peek(current)?.avatar, orderedEquals(pixel));
        port.detailAvatarFree = true;
        gate.complete();
        final result = await pending;
        expect(result.avatar, isNull);
        expect(result.attachment, isNotNull);
        if (detailSecond >= 1) {
          expect(model.seenAuthors.avatarOf(old.senderRef), isNull);
          expect(model.seenAuthors.avatarWanted(old.senderRef), isNull);
          expect(model.media().peek(current)?.avatar, isNull);
          expect(
            model.messages.every((row) => !model.presentAuthor(row).hasAvatar),
            isTrue,
          );
          if (detailSecond == 3) {
            port.observationSeconds = 2;
            await model.refresh(silent: true);
            expect(
              model.presentAuthor(model.messages.first).hasAvatar,
              isFalse,
            );
            expect(model.seenAuthors.avatarOf(old.senderRef), isNull);
            port.observationSeconds = 4;
            await model.refresh(silent: true);
            expect(model.presentAuthor(model.messages.first).hasAvatar, isTrue);
          }
        } else {
          expect(
            model.seenAuthors.avatarOf(old.senderRef),
            orderedEquals(pixel),
          );
          expect(model.presentAuthor(model.messages.first).hasAvatar, isTrue);
          expect(model.media().peek(current)?.avatar, orderedEquals(pixel));
        }
        expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);
        expect(model.messages.first.text, 'Authorized body 1');
        model.setReadingContext(visible: false, foreground: false);
      },
    );
  }

  for (final answer in ['current', 'observed', 'detail']) {
    testWidgets('hidden $answer withdraws every row and keeps content', (
      tester,
    ) async {
      final pixel = (await tester.runAsync(syntheticPixel))!;
      final port = _RetirementPort(pixel);
      addTearDown(port.delegate.changes.close);
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => _start,
        elapsed: () => Duration.zero,
      );
      addTearDown(model.dispose);
      await _prime(model, tester);
      model.updateDraft('Keep draft');
      const viewport = CommunityChatViewport(
        pixels: 123,
        followLatest: false,
        observedLatest: 2,
        anchorSequence: 1,
        anchorOffset: 3,
      );
      model.rememberViewport(viewport);
      final bodies = model.messages.map((row) => row.text).toList();
      final admitted = model.presentAuthor(model.messages.first);
      model.seenAuthors.rememberAvatar(
        admitted.senderRef,
        admitted.avatarVersion!,
        pixel,
      );
      if (answer == 'detail') {
        port.detailHidden = true;
        final result = await model.media().load(admitted);
        expect(result.avatar, isNull);
        expect(result.attachment, isNotNull);
      } else {
        port.answer = answer == 'current' ? 'currentHidden' : 'hidden';
        await model.refresh(silent: true);
      }
      expect(
        model.messages.every(
          (row) => model.presentAuthor(row).callsign.isEmpty,
        ),
        isTrue,
      );
      expect(
        model.messages.every((row) => !model.presentAuthor(row).hasAvatar),
        isTrue,
      );
      expect(model.seenAuthors.avatarOf(admitted.senderRef), isNull);
      expect(model.messages.take(2).map((row) => row.text), bodies);
      expect(model.messages.first.hasAttachment, isTrue);
      expect(model.draft, 'Keep draft');
      expect(model.viewport, same(viewport));
      expect(tester.takeException(), isNull);
    });
  }

  for (final answer in ['unavailable', 'notRetained', 'missing', 'exception']) {
    testWidgets(
      '$answer does not renew; one-shot timer retires at until plus 10s',
      (tester) async {
        final port = _RetirementPort(Uint8List(0));
        addTearDown(port.delegate.changes.close);
        var elapsed = Duration.zero;
        final model = CommunityChatController(
          port,
          'a' * 32,
          now: () => _start.add(elapsed),
          elapsed: () => elapsed,
        );
        addTearDown(model.dispose);
        await _prime(model, tester);
        model.updateDraft('Keep draft');
        final bodies = model.messages.map((row) => row.text).toList();
        elapsed = const Duration(seconds: 5);
        await tester.pump(elapsed);
        expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);
        port.answer = answer;
        await model.refresh(silent: true);
        elapsed = const Duration(seconds: 12);
        await tester.pump(const Duration(seconds: 7));
        await model.refresh(
          silent: true,
        ); // Later failure cannot extend anything.
        final reads = port.reads;
        elapsed = const Duration(seconds: 14, milliseconds: 999);
        await tester.pump(const Duration(seconds: 2, milliseconds: 999));
        expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);
        var changes = 0;
        model.addListener(() => changes++);
        elapsed = const Duration(seconds: 15);
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          changes,
          greaterThan(0),
          reason: 'Expiry itself requests the redraw.',
        );
        expect(
          model.messages.every(
            (row) => model.presentAuthor(row).callsign.isEmpty,
          ),
          isTrue,
        );
        expect(port.reads, reads, reason: 'Retirement adds no reads.');
        expect(model.messages.map((row) => row.text), bodies);
        expect(model.messages.first.hasAttachment, isTrue);
        expect(model.draft, 'Keep draft');
      },
    );
  }

  testWidgets(
    'rollback and entering/resuming cannot extend the original budget',
    (tester) async {
      final port = _RetirementPort(Uint8List(0));
      addTearDown(port.delegate.changes.close);
      var elapsed = Duration.zero;
      var wall = _start;
      final model = CommunityChatController(
        port,
        'a' * 32,
        now: () => wall,
        elapsed: () => elapsed,
      );
      addTearDown(model.dispose);
      await _prime(model, tester);
      elapsed = const Duration(seconds: 8);
      wall = _start.subtract(const Duration(hours: 1));
      await tester.pump(elapsed);
      port.answer = 'unavailable';
      await model.refresh(
        silent: true,
      ); // Re-arms the existing timer under rollback.
      model.setReadingContext(visible: false, foreground: false);
      elapsed = const Duration(
        seconds: 16,
      ); // Simulate suspension before timers run.
      model.setReadingContext(visible: true, foreground: true);
      expect(
        model.presentAuthor(model.messages.first).callsign,
        isEmpty,
        reason: 'Checked synchronously before the resumed first frame.',
      );
      await model.enter();
      expect(model.presentAuthor(model.messages.first).callsign, isEmpty);
      await tester.pump(const Duration(seconds: 8));
    },
  );

  testWidgets('late avatar completion cannot republish an expired author', (
    tester,
  ) async {
    final pixel = (await tester.runAsync(syntheticPixel))!;
    final port = _RetirementPort(pixel);
    addTearDown(port.delegate.changes.close);
    var elapsed = Duration.zero;
    final model = CommunityChatController(
      port,
      'a' * 32,
      now: () => _start.add(elapsed),
      elapsed: () => elapsed,
    );
    addTearDown(model.dispose);
    await _prime(model, tester);
    port.delegate.detailGate = Completer<void>();
    final admitted = model.presentAuthor(model.messages.first);
    final pending = model.media().load(admitted);
    elapsed = const Duration(seconds: 15);
    await tester.pump(elapsed);
    port.delegate.detailGate!.complete();
    final result = await pending;
    expect(result.avatar, isNull);
    expect(result.attachment, isNotNull);
    expect(model.media().peek(admitted)?.avatar, isNull);
    expect(model.seenAuthors.avatarOf(admitted.senderRef), isNull);
    expect(model.presentAuthor(model.messages.first).callsign, isEmpty);
    expect(model.messages.first.text, isNotEmpty);
  });

  testWidgets('new visible detail without avatar withdraws held portraits', (
    tester,
  ) async {
    final pixel = (await tester.runAsync(syntheticPixel))!;
    final port = _RetirementPort(pixel);
    addTearDown(port.delegate.changes.close);
    final model = CommunityChatController(
      port,
      'a' * 32,
      now: () => _start,
      elapsed: () => Duration.zero,
    );
    addTearDown(model.dispose);
    await _prime(model, tester);
    final admitted = model.presentAuthor(model.messages.first);
    model.seenAuthors.rememberAvatar(
      admitted.senderRef,
      admitted.avatarVersion!,
      pixel,
    );
    port.detailAvatarFree = true;
    final result = await model.media().load(admitted);
    expect(result.avatar, isNull);
    expect(result.attachment, isNotNull);
    expect(model.seenAuthors.avatarOf(admitted.senderRef), isNull);
    expect(model.seenAuthors.avatarWanted(admitted.senderRef), isNull);
    expect(model.presentAuthor(model.messages.first).callsign, isNotEmpty);
    expect(
      model.messages.every((row) => !model.presentAuthor(row).hasAvatar),
      isTrue,
    );
    model.setReadingContext(visible: false, foreground: false);
  });
}

Future<void> _prime(CommunityChatController model, WidgetTester tester) async {
  model.setReadingContext(visible: true, foreground: true);
  await model.refresh();
  model.observeAuthors(model.messages);
  await tester.pump();
  expect(model.messages, hasLength(2));
  expect(
    model.messages.every((row) => model.presentAuthor(row).callsign.isNotEmpty),
    isTrue,
  );
}

final class _RetirementPort
    implements
        CommunityChatPort,
        CommunityAuthorProjectionPort,
        CommunityChatAuthorRenewalPort,
        CommunityChatAuthorDetailPort {
  _RetirementPort(Uint8List pixel) : delegate = ExpiryAuthorPort(pixel);
  final ExpiryAuthorPort delegate;
  String answer = 'visible';
  bool detailHidden = false;
  bool detailAvatarFree = false;
  int observationSeconds = 0, detailObservationSeconds = 0;
  Completer<void>? pageGate;
  int reads = 0;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  bool get authorIdentitiesAvailable => true;
  @override
  bool get chatAuthorRenewalAvailable => true;
  @override
  Future<CommunityChatPage> renewChatAuthors(
    String targetRef, {
    int after = 0,
    List<String> observeMessageRefs = const [],
  }) => readChatAuthors(
    targetRef,
    after: after,
    observeMessageRefs: observeMessageRefs,
  );
  @override
  Stream<void> get invalidations => delegate.invalidations;
  @override
  Stream<void> get authorIdentityChanges => const Stream.empty();
  Map<String, Object?> row(int sequence) => {
    ...delegate.person,
    'identityObservedAtUtc': _start
        .add(Duration(seconds: observationSeconds))
        .toIso8601String(),
    'identityValidUntilUtc': _start
        .add(Duration(seconds: observationSeconds + 5))
        .toIso8601String(),
    'messageRef': sequence.toRadixString(16).padLeft(32, '0'),
    'sequence': sequence,
    'text': 'Authorized body $sequence',
  };
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
    reads++;
    if (answer == 'exception') throw const CommunityFailure('unavailable');
    final records = [row(1), row(2)];
    final page = CommunityChatPage.parse({
      ...wire('chat-current-visible'),
      'targetRef': targetRef,
      'messages': after == 0
          ? records
          : [
              if (answer == 'currentHidden')
                {...row(3), 'authorIdentityState': 'hidden'},
            ],
      'oldestSequence': after == 0
          ? 1
          : answer == 'currentHidden'
          ? 3
          : 0,
      'latestSequence': answer == 'currentHidden' ? 3 : 2,
      'hasOlder': false,
      'authorUpdates': [
        if (answer != 'missing')
          for (final record in records)
            if (observeMessageRefs.contains(record['messageRef']))
              {
                ...record,
                'recordState': answer == 'notRetained'
                    ? 'notRetained'
                    : 'found',
                'authorIdentityState':
                    answer == 'hidden' && record['sequence'] == 1
                    ? 'hidden'
                    : answer == 'unavailable'
                    ? 'unavailable'
                    : 'visible',
              },
      ],
    }, officialAuthors: true);
    await pageGate?.future;
    return page;
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) => delegate.readChatDetail(targetRef, messageRef, offset, version);
  @override
  Future<Map<String, Object?>> readChatAuthorDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
  }) async {
    final result = await delegate.readChatAuthorDetail(
      targetRef,
      messageRef,
      offset,
      version,
      expectedAuthorIdentityVersion: expectedAuthorIdentityVersion,
    );
    return {
      ...result,
      'messageRef': messageRef,
      if (detailHidden)
        'author': {
          'senderRef': delegate.person['senderRef'],
          ...const CommunityAuthorProjection.hidden().personFields,
        },
      if (detailAvatarFree)
        'author': {
          'senderRef': delegate.person['senderRef'],
          ...CommunityAuthorProjection.chat({
            ...delegate.person,
            'identityObservedAtUtc': _start
                .add(Duration(seconds: detailObservationSeconds))
                .toIso8601String(),
            'identityValidUntilUtc': _start
                .add(Duration(seconds: detailObservationSeconds + 5))
                .toIso8601String(),
            'hasAvatar': false,
            'avatarVersion': null,
            'authorIdentityVersion': 'e' * 64,
          }).personFields,
        },
    };
  }

  @override
  Future<CommunityChatReadReceipt> markChatRead(
    String targetRef,
    CommunityChatMessage message,
  ) => throw StateError('Retirement does not submit receipts');
}
