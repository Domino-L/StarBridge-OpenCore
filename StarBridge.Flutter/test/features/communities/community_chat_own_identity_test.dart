import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_own_avatar.dart';

import '../friends/social_layout_test.dart' show app;
import 'community_chat_controller_test.dart' show page;

/// Two 1x1 PNGs would be enough; the bytes only have to survive the source.
final _png = base64Encode(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

abstract class _Port implements CommunityChatPort, CommunityAuthorProjectionPort {}

final class _OwnPort extends _Fake implements CommunityOwnIdentitySource {
  _OwnPort(this.ownChatName);
  @override
  final String? ownChatName;
  @override
  String? get ownAvatarImageData => 'data:image/png;base64,$_png';
}

class _Fake implements _Port {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CommunityChatMessage _message({required bool self}) =>
    CommunityChatMessage.neutralAuthor(
      page(
        [1],
        latest: 1,
        unread: 0,
        older: false,
        localRequestId: self ? 'b' * 32 : null,
      ).messages.single,
    );

Map<String, Object?> _detailRow(Map<String, Object?> author, Object? avatar) {
  final bytes = utf8.encode(jsonEncode({'avatarImageData': avatar, 'attachment': null}));
  return {
    'schemaVersion': 1,
    'targetRef': 'a' * 32,
    'messageRef': 'b' * 32,
    'offset': 0,
    'version': sha256.convert(bytes).toString(),
    'totalBytes': bytes.length,
    'data': base64Encode(bytes),
    'next': null,
    'authorRefreshRequired': false,
    'author': {'senderRef': 'd' * 32, ...author},
  };
}

void main() {
  final now = DateTime.utc(2026, 10, 31, 12);
  final avatar = 'data:image/png;base64,$_png';
  final version = sha256.convert(utf8.encode(avatar)).toString();
  Map<String, Object?> visibleRow(DateTime observed) => {
    'identityState': 'visible',
    'callsign': 'Nova',
    'identityVersion': 'a' * 64,
    'hasAvatar': true,
    'avatarVersion': version,
    'identityObservedAtUtc': observed.toIso8601String(),
    'identityValidUntilUtc': observed
        .add(const Duration(seconds: 5))
        .toIso8601String(),
  };
  final expected = CommunityAuthorProjection.person(visibleRow(now));
  Future<void> assemble(
    Map<String, Object?> row, {
    required void Function(CommunityAuthorProjection) narrow,
    void Function(String, Object)? confirmed,
    DateTime? at,
    bool current = true,
  }) => assembleCommunityChatDetail(
    _Fake(),
    'a' * 32,
    'b' * 32,
    senderRef: 'd' * 32,
    checkCurrent: () {},
    identity: CommunityChatDetailIdentity(
      expected: expected,
      now: () => at ?? now,
      current: () => current,
      narrow: narrow,
      avatarConfirmed: confirmed,
      read: (_, _, _) async => row,
    ),
  );

  test('a hidden detail answer stays hidden whatever the request expected', () async {
    final seen = <CommunityAuthorState>[];
    await assemble(
      _detailRow({'identityState': 'hidden'}, null),
      narrow: (observed) => seen.add(observed.state),
      current: false,
    );
    expect(seen, contains(CommunityAuthorState.hidden));
  });
  test('an avatar confirmed by its own answer survives a lapsed proof', () async {
    final confirmed = <String>[];
    await assemble(
      _detailRow(visibleRow(now), avatar),
      narrow: (_) {},
      confirmed: (version, _) => confirmed.add(version),
      at: now.add(const Duration(seconds: 30)),
      current: false,
    );
    expect(confirmed, [version]);
  });
  test('a different person never confirms the expected avatar', () async {
    final confirmed = <String>[];
    await assemble(
      _detailRow({...visibleRow(now), 'identityVersion': 'b' * 64}, avatar),
      narrow: (_) {},
      confirmed: (version, _) => confirmed.add(version),
    );
    expect(confirmed, isEmpty);
  });
  test('own avatar bytes need no message version', () {
    final bytes = ownCommunityAvatarBytes(_OwnPort('Domino'));
    expect(bytes, isNotNull);
    expect(sha256.convert(bytes!).bytes, isNotEmpty);
  });
  testWidgets('your own message shows your name with no author proof', (
    tester,
  ) async {
    final port = _OwnPort('Domino');
    addTearDown(port.changes.close);
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 700,
            child: CommunityChatMessageTile(
              port: port,
              targetRef: 'a' * 32,
              message: _message(self: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Domino'), findsOneWidget);
    expect(find.text('我'), findsNothing);
    expect(find.text('Me'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('someone else with no name is a member, never "me"', (tester) async {
    final port = _Fake();
    addTearDown(port.changes.close);
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 700,
            child: CommunityChatMessageTile(
              port: port,
              targetRef: 'a' * 32,
              message: _message(self: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('我'), findsNothing);
    expect(find.text('Me'), findsNothing);
    expect(find.textContaining(RegExp('成员|Member')), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
