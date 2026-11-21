import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection.dart';

void main() {
  final observed = DateTime.utc(2026, 11, 3, 12);
  final until = observed.add(const Duration(seconds: 5));
  for (final chat in [false, true]) {
    Map<String, Object?> row({int span = 5}) => {
      if (chat)
        'authorIdentityState': 'visible'
      else
        'identityState': 'visible',
      if (chat) 'senderCallsign': 'Fixture' else 'callsign': 'Fixture',
      if (chat)
        'authorIdentityVersion': 'a' * 64
      else
        'identityVersion': 'a' * 64,
      'hasAvatar': false,
      'avatarVersion': null,
      'identityObservedAtUtc': observed.toIso8601String(),
      'identityValidUntilUtc': observed
          .add(Duration(seconds: span))
          .toIso8601String(),
    };
    CommunityAuthorProjection read({int span = 5}) => chat
        ? CommunityAuthorProjection.chat(row(span: span))
        : CommunityAuthorProjection.person(row(span: span));
    for (final milliseconds in [1070, 9000, 10000, 11000]) {
      final delta = Duration(milliseconds: milliseconds);
      test('$chat slow ${milliseconds}ms future tolerance', () {
        expect(
          read().admit(observed.subtract(delta)).visible,
          milliseconds <= 10000,
        );
      });
      test('$chat fast ${milliseconds}ms past deadline grace', () {
        expect(read().admit(until.add(delta)).visible, milliseconds < 10000);
      });
    }
    test('$chat five-second span is valid and six-second span is invalid', () {
      expect(read().admit(observed).visible, isTrue);
      expect(read(span: 6).admit(observed).visible, isFalse);
    });
    test('$chat visible one tick before display deadline', () {
      final deadline = until.add(const Duration(seconds: 10));
      expect(
        read()
            .admit(deadline.subtract(const Duration(microseconds: 1)))
            .visible,
        isTrue,
      );
      expect(read().displayDeadline, deadline);
    });
    test('$chat retired at the exact display deadline', () {
      expect(
        read().admit(until.add(const Duration(seconds: 10))).visible,
        isFalse,
      );
    });
    test('$chat boundaries preserve original proof timestamps', () {
      final proof = read();
      expect(
        proof.admit(until.add(const Duration(seconds: 10))).visible,
        isFalse,
      );
      expect(
        proof
            .admit(until.add(const Duration(seconds: 10, microseconds: 1)))
            .visible,
        isFalse,
      );
      expect(
        proof
            .admit(
              observed.subtract(const Duration(seconds: 10, microseconds: 1)),
            )
            .visible,
        isFalse,
      );
      expect(proof.observedAt, observed);
      expect(proof.validUntil, until);
      // A clock 11s ahead of observation is only 6s past this proof's deadline.
      expect(
        proof.admit(observed.add(const Duration(seconds: 11))).visible,
        isTrue,
      );
    });
  }
}
