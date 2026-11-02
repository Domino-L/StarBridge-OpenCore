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
  setUp(() => seen = CommunityChatSeenAuthors());

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
      [answered({'authorIdentityState': 'unavailable'})],
      [ref],
      const [],
    );
    expect(show(plain).callsign, 'Nova');
    expect(seen.avatarOf(sender), isNotNull);
  });
  test('five minutes after the last confirmation the name goes', () {
    var elapsed = Duration.zero;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed);
    seen.answer([visible(avatar: 'c' * 64)], [ref], const []);
    seen.rememberAvatar(sender, 'c' * 64, Uint8List(1));
    elapsed = CommunityChatSeenAuthors.maximumAge;
    expect(show(plain).callsign, 'Nova');
    expect(seen.sweep(), isFalse);
    elapsed += const Duration(milliseconds: 1);
    final gone = show(plain);
    expect(gone.callsign, isEmpty);
    expect(gone.authorIdentity?.state, CommunityAuthorState.unavailable);
    expect(seen.avatarOf(sender), isNull);
  });
  test('the limit needs no redraw: a sweep withdraws, and asks for one once', () {
    var elapsed = Duration.zero;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed);
    seen.answer([visible()], [ref], const []);
    expect(seen.sweep(), isFalse);
    elapsed = CommunityChatSeenAuthors.maximumAge + const Duration(seconds: 1);
    expect(seen.sweep(), isTrue);
    expect(seen.sweep(), isFalse);
    expect(show(plain).callsign, isEmpty);
    expect(
      CommunityChatSeenAuthors.maximumAge + CommunityChatSeenAuthors.sweepEvery,
      const Duration(minutes: 5),
    );
  });
  test('a hidden answer asks for a redraw too', () {
    seen.answer([visible()], [ref], const []);
    expect(seen.sweep(), isFalse);
    seen.forget(sender);
    expect(seen.sweep(), isTrue);
  });
  test('a new confirmation restarts the five minutes; unavailable does not', () {
    var elapsed = Duration.zero;
    seen = CommunityChatSeenAuthors(elapsed: () => elapsed);
    seen.answer([visible()], [ref], const []);
    elapsed = const Duration(minutes: 4);
    seen.answer([visible()], [ref], const []);
    elapsed = const Duration(minutes: 8, seconds: 50);
    seen.answer(
      [answered({'authorIdentityState': 'unavailable'})],
      [ref],
      const [],
    );
    expect(show(plain).callsign, 'Nova');
    elapsed = const Duration(minutes: 9, seconds: 1);
    expect(show(plain).callsign, isEmpty);
  });
  test('a lapsed proof the read still answered counts as a confirmation', () {
    seen.answer([visible()], [ref], const []);
    final late = show(
      visible(),
      verified: true,
      at: now.add(const Duration(seconds: 30)),
    );
    expect(late.callsign, 'Nova');
    expect(late.authorIdentity?.state, CommunityAuthorState.lastSeen);
    expect(late.authorIdentity?.visible, isFalse, reason: 'No authority.');
    expect(late.hasAvatar, isFalse);
  });
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
      seen.answer([
        answered({'authorIdentityState': state}),
      ], [ref], const []);
      expect(seen.avatarOf(sender), isNull);
      expect(show(plain).callsign, isEmpty);
    });
  }

  test('a late denial for an old window still reaches the same author', () {
    seen.answer([visible()], [ref], const []);
    seen.answer([
      answered({'authorIdentityState': 'hidden'}),
    ], [ref], const []);
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
  });

  test('rows the read was not asked about say nothing', () {
    seen.answer([visible()], [ref], const []);
    seen.answer([CommunityChatMessage.neutralAuthor(plain)], const [], const []);
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
}
