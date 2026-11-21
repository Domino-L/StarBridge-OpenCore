import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_seen_authors.dart';

import 'community_chat_controller_test.dart' show page;

void main() {
  final now = DateTime.utc(2026, 10, 30, 12);
  final messages = page([1, 2], latest: 2, unread: 0, older: false).messages;
  final plain = messages.first;
  final ref = plain.messageRef, sender = plain.senderRef;

  CommunityChatMessage answered(Map<String, Object?> row) =>
      CommunityChatMessage.withAuthor(
        plain,
        CommunityAuthorProjection.chat(row),
      );
  CommunityChatMessage visible({String? avatar}) => answered({
    'authorIdentityState': 'visible',
    'senderCallsign': 'Nova',
    'authorIdentityVersion': 'a' * 64,
    'hasAvatar': avatar != null,
    'avatarVersion': avatar,
    'identityObservedAtUtc': now.toIso8601String(),
    'identityValidUntilUtc': now
        .add(const Duration(seconds: 5))
        .toIso8601String(),
  });

  late CommunityChatSeenAuthors seen;
  CommunityChatMessage show(
    CommunityChatMessage message, {
    bool verified = false,
    bool allowed = true,
    DateTime? at,
  }) => seen.present(
    message,
    verified: verified,
    allowed: allowed,
    now: at ?? now,
  );
  setUp(() => seen = CommunityChatSeenAuthors(now: () => now));

  test('someone never seen stays neutral until a read answers', () {
    final shown = show(plain);
    expect(shown.authorIdentity?.state, CommunityAuthorState.unavailable);
    expect(shown.callsign, isEmpty);
  });

  test('a seen name shows while the next read is on its way', () {
    seen.answer([visible()], [ref], const []);
    final waiting = show(plain);
    expect(waiting.authorIdentity?.state, CommunityAuthorState.lastSeen);
    expect(waiting.callsign, 'Nova');
    expect(waiting.authorIdentity?.visible, isFalse, reason: 'No authority.');
  });

  test('drawing a valid proof never writes a name back', () {
    seen.answer([visible()], [ref], const []);
    seen.clear();
    expect(show(visible(), verified: true).callsign, 'Nova');
    expect(show(plain).callsign, isEmpty, reason: 'Withdrawn stays withdrawn.');
  });

  test('a proof running out keeps the seen name, not neutral', () {
    seen.answer([visible()], [ref], const []);
    final retired = CommunityChatMessage.neutralAuthor(plain);
    expect(show(retired, verified: true).callsign, 'Nova');
    final later = now.add(const Duration(seconds: 6));
    expect(show(visible(), verified: true, at: later).callsign, 'Nova');
  });

  test('a read answering unavailable keeps name and avatar', () {
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    seen.rememberAvatar(sender, 'c' * 64, Uint8List(1));
    seen.answer(
      [
        answered({'authorIdentityState': 'unavailable'}),
      ],
      [ref],
      const [],
    );
    expect(show(plain).callsign, 'Nova');
    expect(seen.avatarOf(sender), isNotNull);
  });
  test('unavailable retires exactly at validUntil plus ten seconds', () {
    var elapsed = Duration.zero;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed, now: () => now);
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    seen.rememberAvatar(sender, 'c' * 64, Uint8List(1));
    seen.answer(
      [
        answered({'authorIdentityState': 'unavailable'}),
      ],
      [ref],
      const [],
    );
    elapsed = const Duration(seconds: 5);
    expect(show(plain).callsign, 'Nova');
    expect(seen.sweep(), isFalse);
    elapsed = const Duration(seconds: 14, milliseconds: 999);
    expect(show(plain).callsign, 'Nova');
    elapsed = const Duration(seconds: 15);
    final gone = show(plain);
    expect(gone.callsign, isEmpty);
    expect(gone.authorIdentity?.state, CommunityAuthorState.unavailable);
    expect(seen.avatarOf(sender), isNull);
  });
  test(
    'the limit needs no redraw: a sweep withdraws, and asks for one once',
    () {
      var elapsed = Duration.zero;
      seen = CommunityChatSeenAuthors(elapsed: () => elapsed, now: () => now);
      seen.answer([visible()], [ref], const []);
      expect(seen.sweep(), isFalse);
      expect(seen.nextRetirement, const Duration(seconds: 15));
      elapsed = const Duration(seconds: 15);
      expect(seen.sweep(), isTrue);
      expect(seen.sweep(), isFalse);
      expect(show(plain).callsign, isEmpty);
      expect(seen.nextRetirement, isNull);
    },
  );
  test('a hidden answer asks for a redraw too', () {
    seen.answer([visible()], [ref], const []);
    expect(seen.sweep(), isFalse);
    seen.forget(sender);
    expect(seen.sweep(), isTrue);
  });
  test('the same proof and later unavailable never restart the deadline', () {
    var elapsed = Duration.zero;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed, now: () => now);
    seen.answer([visible()], [ref], const []);
    elapsed = const Duration(seconds: 8);
    seen.answer([visible()], [ref], const []);
    elapsed = const Duration(seconds: 12);
    seen.answer(
      [
        answered({'authorIdentityState': 'unavailable'}),
      ],
      [ref],
      const [],
    );
    expect(show(plain).callsign, 'Nova');
    expect(seen.nextRetirement, const Duration(seconds: 3));
    elapsed = const Duration(seconds: 15);
    expect(show(plain).callsign, isEmpty);
    seen.answer([visible()], [ref], const []);
    expect(
      show(plain).callsign,
      isEmpty,
      reason: 'Retired proof cannot revive.',
    );
  });
  test(
    'a lapsed proof cannot leave a former name beyond its hard deadline',
    () {
      seen.answer([visible()], [ref], const []);
      final late = show(
        visible(),
        verified: true,
        at: now.add(const Duration(seconds: 30)),
      );
      expect(late.callsign, isEmpty);
      expect(late.authorIdentity?.state, CommunityAuthorState.unavailable);
      expect(late.authorIdentity?.visible, isFalse, reason: 'No authority.');
      expect(late.hasAvatar, isFalse);
    },
  );
  test('a wall-clock rollback cannot prolong name or admit a late avatar', () {
    var elapsed = Duration.zero, wall = now;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed, now: () => wall);
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    elapsed = const Duration(seconds: 14);
    wall = now.subtract(const Duration(hours: 1));
    expect(show(plain, at: wall).callsign, 'Nova');
    expect(
      seen.avatarWanted(sender),
      isNull,
      reason: 'No avatar read in grace.',
    );
    elapsed = const Duration(seconds: 15);
    seen.confirmAvatar(sender, 'c' * 64, Uint8List(1));
    expect(seen.avatarOf(sender), isNull);
    expect(show(visible(), verified: true, at: wall).callsign, isEmpty);
  });
  test(
    'a newer valid observation replaces the budget without changing body',
    () {
      var elapsed = Duration.zero;
      seen = CommunityChatSeenAuthors(elapsed: () => elapsed, now: () => now);
      seen.answer([visible()], [ref], const []);
      elapsed = const Duration(seconds: 4);
      final updated = answered({
        ...visible().authorIdentity!.chatFields,
        'identityObservedAtUtc': now.add(elapsed).toIso8601String(),
        'identityValidUntilUtc': now
            .add(const Duration(seconds: 9))
            .toIso8601String(),
      });
      seen.answer([updated], [ref], const []);
      elapsed = const Duration(seconds: 15);
      expect(show(plain).callsign, 'Nova');
      elapsed = const Duration(seconds: 19);
      final retired = show(plain);
      expect(retired.callsign, isEmpty);
      expect(retired.text, plain.text);
      expect(retired.hasAttachment, plain.hasAttachment);
      expect(retired.messageRef, plain.messageRef);
    },
  );
  test('only a matching avatar is confirmed', () {
    var changes = 0;
    seen.addListener(() => changes++);
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    seen.confirmAvatar(sender, 'd' * 64, Uint8List(1));
    expect(seen.avatarOf(sender), isNull);
    expect(changes, 0);
    seen.confirmAvatar(sender, 'c' * 64, Uint8List(1));
    expect(seen.avatarOf(sender), isNotNull);
    expect(changes, 1);
    expect(seen.avatarWanted(sender), isNull);
  });
  for (final state in ['hidden']) {
    test('a read answering $state forgets name and avatar on arrival', () {
      seen.answer([visible(avatar: 'b' * 64)], [ref], const []);
      seen.rememberAvatar(sender, 'b' * 64, Uint8List(1));
      seen.answer(
        [
          answered({'authorIdentityState': state}),
        ],
        [ref],
        const [],
      );
      expect(seen.avatarOf(sender), isNull);
      expect(show(plain).callsign, isEmpty);
    });
  }

  test('a late denial for an old window still reaches the same author', () {
    seen.answer([visible()], [ref], const []);
    seen.answer(
      [
        answered({'authorIdentityState': 'hidden'}),
      ],
      [ref],
      const [],
    );
    // Another message by the same person, which no read has answered yet.
    final other = CommunityChatMessage.neutralAuthor(plain);
    expect(show(other).callsign, isEmpty);
  });

  test('a denial for a message pushed out of the history still counts', () {
    seen.answer([visible()], [ref], const []);
    final update = page([1], latest: 1, unread: 0, older: false);
    final denied = CommunityChatAuthorUpdate.parse({
      'messageRef': ref,
      'senderRef': sender,
      'sequence': plain.sequence,
      'recordState': 'found',
      'authorIdentityState': 'hidden',
    });
    expect(update.messages, isNotEmpty);
    seen.answer(const [], [ref], [denied]);
    expect(show(plain).callsign, isEmpty);
  });

  test('a detail read answering no forgets through forget', () {
    seen.answer([visible()], [ref], const []);
    seen.forget(sender);
    expect(show(plain).callsign, isEmpty);
    seen.answer([visible()], [ref], const []);
    expect(
      show(visible(), verified: true).callsign,
      isEmpty,
      reason: 'The same delayed proof cannot undo hidden.',
    );
  });

  test('rows the read was not asked about say nothing', () {
    seen.answer([visible()], [ref], const []);
    seen.answer(
      [CommunityChatMessage.neutralAuthor(plain)],
      const [],
      const [],
    );
    expect(show(plain).callsign, 'Nova');
  });

  test('confirmed without an avatar drops the old avatar', () {
    seen.answer([visible(avatar: 'b' * 64)], [ref], const []);
    seen.rememberAvatar(sender, 'b' * 64, Uint8List(1));
    seen.answer([visible()], [ref], const []);
    expect(seen.avatarOf(sender), isNull);
  });

  test('a changed avatar is not drawn as the new one', () {
    seen.answer([visible(avatar: 'b' * 64)], [ref], const []);
    seen.rememberAvatar(sender, 'b' * 64, Uint8List(1));
    expect(seen.avatarOf(sender, version: 'b' * 64), isNotNull);
    expect(seen.avatarOf(sender, version: 'c' * 64), isNull);
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    expect(seen.avatarOf(sender), isNull);
  });

  test('nobody reading in front shows no former name', () {
    seen.answer([visible()], [ref], const []);
    final shown = show(plain, allowed: false);
    expect(shown.authorIdentity?.state, CommunityAuthorState.unavailable);
    expect(shown.callsign, isEmpty);
    expect(show(plain).callsign, 'Nova', reason: 'Back in front, it returns.');
  });

  test('an avatar is only kept for someone seen by name', () {
    seen.rememberAvatar(sender, 'b' * 64, Uint8List(1));
    expect(seen.avatarOf(sender), isNull);
  });

  for (final hidden in [false, true]) {
    test(
      '${hidden ? 'hidden' : 'avatar-only'} fence survives newer answers',
      () {
        var elapsed = Duration.zero;
        seen = CommunityChatSeenAuthors(
          elapsed: () => elapsed,
          now: () => now.add(elapsed),
        );
        CommunityChatMessage proof(int second, {bool avatar = true}) =>
            answered({
              ...visible(avatar: avatar ? 'b' * 64 : null)
                  .authorIdentity!
                  .chatFields,
              'identityObservedAtUtc': now
                  .add(Duration(seconds: second))
                  .toIso8601String(),
              'identityValidUntilUtc': now
                  .add(Duration(seconds: second + 5))
                  .toIso8601String(),
            });
        seen.answer([proof(0)], [ref], const []);
        elapsed = const Duration(seconds: 3);
        if (hidden) {
          seen.hide(sender);
        } else {
          seen.withdrawAvatar(sender, observedAt: now.add(elapsed));
          // Repeated older narrowing cannot lower the watermark.
          seen.withdrawAvatar(
            sender,
            observedAt: now.add(const Duration(seconds: 2)),
          );
        }
        elapsed = const Duration(seconds: 15);
        seen.sweep();
        elapsed = const Duration(seconds: 16);
        for (final second in [2, 3]) {
          expect(
            seen.allowsProof(sender, proof(second).authorIdentity!),
            isFalse,
          );
          expect(
            seen.allowsProof(
              sender,
              proof(second, avatar: false).authorIdentity!,
            ),
            !hidden,
            reason: 'Only hidden also fences the name.',
          );
        }
        seen.answer([proof(4)], [ref], const []);
        expect(seen.allowsProof(sender, proof(4).authorIdentity!), isTrue);
        for (final second in [2, 3]) {
          expect(
            seen.allowsProof(sender, proof(second).authorIdentity!),
            isFalse,
          );
        }
        seen.clear(); // Account/organization/generation reset remains authoritative.
        expect(seen.allowsProof(sender, proof(2).authorIdentity!), isTrue);
      },
    );

    test('${hidden ? 'hidden' : 'avatar-only'} fences remain bounded', () {
      final proof = visible(avatar: 'b' * 64).authorIdentity!;
      for (var index = 0; index <= 500; index++) {
        final author = index.toRadixString(16).padLeft(32, '0');
        if (hidden) {
          seen.hide(author);
        } else {
          seen.withdrawAvatar(author, observedAt: now);
          seen.forget(author);
        }
      }
      expect(seen.allowsProof('0' * 32, proof), isTrue);
      expect(seen.allowsProof('1'.padLeft(32, '0'), proof), isFalse);
      expect(
        seen.allowsProof(500.toRadixString(16).padLeft(32, '0'), proof),
        isFalse,
      );
    });
  }
}
