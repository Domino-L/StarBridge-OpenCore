import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_chat_preview_authors.dart';
import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_author_projection_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_chat_tile.dart';

final _target = 'a' * 32;
String _ref(int sequence) => sequence.toRadixString(16).padLeft(32, '0');
final _sender = 'd' * 32;

Map<String, Object?> _identity(
  DateTime observed, {
  String name = 'Pilot',
  String state = 'visible',
}) => state == 'visible'
    ? {
        'senderCallsign': name,
        'hasAvatar': false,
        'avatarVersion': null,
        'authorIdentityState': 'visible',
        'authorIdentityVersion': 'b' * 64,
        'identityObservedAtUtc': observed.toUtc().toIso8601String(),
        'identityValidUntilUtc': observed
            .add(const Duration(seconds: 5))
            .toUtc()
            .toIso8601String(),
      }
    : {
        'senderCallsign': '',
        'hasAvatar': false,
        'avatarVersion': null,
        'authorIdentityState': state,
        'authorIdentityVersion': null,
        'identityObservedAtUtc': null,
        'identityValidUntilUtc': null,
      };

Map<String, Object?> _row(int sequence) => {
  'sequence': sequence,
  'messageRef': _ref(sequence),
  'senderRef': _sender,
  'senderCallsign': '',
  'senderGameId': '',
  'senderRoleTitle': '',
  'senderRoleColor': '#9DAAB3',
  'text': 'M$sequence',
  'createdAt': '2026-10-30T00:00:00Z',
  'isSelf': false,
  'hasAvatar': false,
  'hasAttachment': false,
};

CommunityChatPage _page({
  List<Map<String, Object?>> messages = const [],
  List<Map<String, Object?>> updates = const [],
  bool refresh = false,
  String? target,
  int? latest,
}) => CommunityChatPage.parse({
  'schemaVersion': 1,
  'targetRef': target ?? _target,
  'unreadCount': 0,
  'latestSequence': latest ?? (messages.isEmpty ? 1 : messages.last['sequence']),
  'oldestSequence': messages.isEmpty ? 0 : messages.first['sequence'],
  'canSend': true,
  'hasOlder': false,
  'serverTime': '2026-10-30T00:00:00Z',
  'messages': messages,
  'authorUpdates': updates,
  'authorRefreshRequired': refresh,
}, officialAuthors: true);

final class _Port implements OrganizationChatPreviewAuthorPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <(int, List<String>)>[];
  bool available = true;
  Object? failure;
  CommunityChatPage Function((int, List<String>))? answer;
  @override
  bool get previewAuthorsAvailable => available;
  @override
  Stream<void> get previewAuthorChanges => changes.stream;
  final limits = <int>[];
  @override
  Future<CommunityChatPage> renewPreviewAuthors(
    String targetRef, {
    int after = 0,
    int limit = 8,
    List<String> observeMessageRefs = const [],
  }) async {
    final read = (after, observeMessageRefs);
    reads.add(read);
    limits.add(limit);
    if (failure != null) throw failure!;
    return answer!(read);
  }
}

final class _HeldPort implements OrganizationChatPreviewAuthorPort {
  _HeldPort(this.first);
  final Future<CommunityChatPage> first;
  final reads = <int>[];
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  bool get previewAuthorsAvailable => true;
  @override
  Stream<void> get previewAuthorChanges => changes.stream;
  @override
  Future<CommunityChatPage> renewPreviewAuthors(
    String targetRef, {
    int after = 0,
    int limit = 8,
    List<String> observeMessageRefs = const [],
  }) {
    reads.add(after);
    return reads.length == 1 ? first : Future.value(_page());
  }
}

CommunityChatMessage _message(int sequence) =>
    CommunityChatMessage.parse(_row(sequence));

void main() {
  late _Port port;
  late DateTime now;
  late OrganizationChatPreviewAuthors authors;
  var elapsed = Duration.zero;

  // Real async for the reads; the interval is long so only [tick] reads.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    port = _Port();
    now = DateTime.utc(2026, 10, 30, 12);
    elapsed = Duration.zero;
    authors = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(hours: 1),
    )..target = _target;
    port.answer = (read) => read.$2.isEmpty
        ? _page(messages: [
            {..._row(1), ..._identity(now)},
          ])
        : _page(updates: [
            {
              'messageRef': _ref(1),
              'senderRef': _sender,
              'sequence': 1,
              'recordState': 'found',
              ..._identity(now),
            },
          ]);
  });
  tearDown(() async {
    authors.dispose();
    await port.changes.close();
  });

  test('reads nothing until a tile is on screen', () async {
    await settle();
    expect(port.reads, isEmpty);
    expect(authors.present(_message(1)).callsign, '');
  });

  test('a visible tile gets the name; leaving stops reads and drops it', () async {
    authors.setActive(true);
    await settle();
    expect(port.reads.single, (0, const <String>[]));
    expect(authors.present(_message(1)).callsign, 'Pilot');
    authors.setActive(false);
    expect(authors.present(_message(1)).callsign, '');
    await settle();
    expect(port.reads, hasLength(1));
  });

  testWidgets('renewal observes shown messages on the chat cadence', (
    tester,
  ) async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      interval: const Duration(seconds: 3),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await tester.pump();
    expect(port.reads.single, (0, const <String>[]));
    var rebuilds = 0;
    live.addListener(() => rebuilds++);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(port.reads.last.$1, 1);
    expect(port.reads.last.$2, [_ref(1)]);
    expect(rebuilds, 0, reason: 'A renewal changes nothing on screen.');
    live.setActive(false);
    final count = port.reads.length;
    await tester.pump(const Duration(seconds: 9));
    expect(port.reads, hasLength(count));
  });

  test('a proof past its deadline shows no name', () async {
    authors.setActive(true);
    await settle();
    elapsed += const Duration(seconds: 5, milliseconds: 1);
    expect(authors.present(_message(1)).callsign, '');
  });

  test('moving the wall clock alone does not change what shows', () async {
    authors.setActive(true);
    await settle();
    now = now.add(const Duration(seconds: 30));
    expect(authors.present(_message(1)).callsign, 'Pilot');
    elapsed += const Duration(seconds: 5);
    expect(authors.present(_message(1)).callsign, '');
  });

  test('an author who hides is hidden, not named', () async {
    authors.setActive(true);
    await settle();
    port.answer = (_) => _page(updates: [
      {
        'messageRef': _ref(1),
        'senderRef': _sender,
        'sequence': 1,
        'recordState': 'found',
        ..._identity(now, state: 'hidden'),
      },
    ]);
    authors
      ..setActive(false)
      ..setActive(true);
    await settle();
    final shown = authors.present(_message(1));
    expect(shown.callsign, isNot('Pilot'));
  });

  test('an observed message without an update loses its name', () async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      interval: const Duration(milliseconds: 1),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await settle();
    expect(live.present(_message(1)).callsign, 'Pilot');
    port.answer = (_) => _page();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(port.reads.length, greaterThan(1));
    expect(live.present(_message(1)).callsign, '');
    live.setActive(false);
  });

  test('another sender at the same sequence never inherits the name', () async {
    authors.setActive(true);
    await settle();
    final other = CommunityChatMessage.parse({
      ..._row(1),
      'senderRef': 'e' * 32,
    });
    expect(authors.present(other).callsign, '');
  });

  test('a failed read fails closed without throwing', () async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      interval: const Duration(milliseconds: 1),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await settle();
    port.failure = StateError('offline');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(live.present(_message(1)).callsign, '');
    port.failure = null;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(live.present(_message(1)).callsign, 'Pilot');
    live.setActive(false);
  });

  test('losing identity support or a retirement event removes names', () async {
    authors.setActive(true);
    await settle();
    port.changes.add(null);
    expect(authors.present(_message(1)).callsign, '');
    final reads = port.reads.length;
    port.available = false;
    authors
      ..setActive(false)
      ..setActive(true);
    await settle();
    expect(port.reads, hasLength(reads));
  });

  test('a refused read tells the owner so content clears too', () async {
    final lost = <String>[];
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      interval: const Duration(hours: 1),
      onAccessLost: lost.add,
    )..target = _target;
    addTearDown(live.dispose);
    port.failure = const CommunityFailure('unavailable');
    live.setActive(true);
    await settle();
    expect(lost, isEmpty, reason: 'A passing failure only drops names.');
    live.setActive(false);
    port.failure = const CommunityFailure('notAllowed');
    live.setActive(true);
    await settle();
    expect(lost, ['notAllowed']);
    live.setActive(false);
  });

  testWidgets('setting the wall clock back cannot extend a name', (
    tester,
  ) async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(hours: 1),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await tester.pump();
    expect(live.present(_message(1)).callsign, 'Pilot');
    var notified = 0;
    live.addListener(() => notified++);
    now = now.subtract(const Duration(seconds: 3));
    elapsed += const Duration(seconds: 5, milliseconds: 1);
    expect(live.present(_message(1)).callsign, '');
    await tester.pump(const Duration(seconds: 5, milliseconds: 1));
    expect(notified, 1);
    live.setActive(false);
  });

  testWidgets('a renewal after the clock moved back cannot stretch the name', (
    tester,
  ) async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(seconds: 4),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await tester.pump();
    expect(live.present(_message(1)).callsign, 'Pilot');
    var notified = 0;
    live.addListener(() => notified++);
    // Four real seconds on, the clock reads one second: the proof the relay
    // observed at the real time is from the local future and shows no name.
    final real = now.add(const Duration(seconds: 4));
    port.answer = (_) => _page(updates: [
      {
        'messageRef': _ref(1),
        'senderRef': _sender,
        'sequence': 1,
        'recordState': 'found',
        ..._identity(real),
      },
    ]);
    now = now.add(const Duration(seconds: 1));
    elapsed += const Duration(seconds: 4);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(live.present(_message(1)).callsign, '');
    expect(notified, 1, reason: 'The name goes at once, not at a later timer.');
    live.setActive(false);
  });

  testWidgets('a renewed proof brings the name back after one expired', (
    tester,
  ) async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(seconds: 6),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await tester.pump();
    var notified = 0;
    live.addListener(() => notified++);
    now = now.add(const Duration(seconds: 5, milliseconds: 1));
    elapsed += const Duration(seconds: 5, milliseconds: 1);
    await tester.pump(const Duration(seconds: 5, milliseconds: 1));
    expect(live.present(_message(1)).callsign, '');
    expect(notified, 1);
    now = now.add(const Duration(seconds: 1));
    elapsed += const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(live.present(_message(1)).callsign, 'Pilot');
    expect(notified, 2);
    live.setActive(false);
  });

  test('the relay saying nothing means no reads and no names', () async {
    port.available = false;
    authors.setActive(true);
    await settle();
    expect(port.reads, isEmpty);
    expect(authors.present(_message(1)).callsign, '');
    // A verified reopen with the relay's yes starts it.
    port.available = true;
    authors.setActive(true);
    await settle();
    expect(port.reads, hasLength(1));
    expect(authors.present(_message(1)).callsign, 'Pilot');
  });

  test('asks only for the messages on screen', () async {
    authors.shownCount = 2;
    port.answer = (read) => _page(
      messages: read.$2.isEmpty
          ? [
              {..._row(1), ..._identity(now)},
              {..._row(2), ..._identity(now)},
              {..._row(3), ..._identity(now)},
            ]
          : const [],
      updates: [
        for (final ref in read.$2)
          {
            'messageRef': ref,
            'senderRef': _sender,
            'sequence': int.parse(ref, radix: 16),
            'recordState': 'found',
            ..._identity(now),
          },
      ],
    );
    authors.setActive(true);
    await settle();
    expect(port.limits.single, 2);
    expect(authors.present(_message(1)).callsign, '', reason: 'Off screen.');
    expect(authors.present(_message(3)).callsign, 'Pilot');
    authors.shownCount = 1;
    expect(authors.present(_message(2)).callsign, '');
    expect(authors.present(_message(3)).callsign, 'Pilot');
  });

  testWidgets('failures back off and success returns to the cadence', (
    tester,
  ) async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
    )..target = _target;
    addTearDown(live.dispose);
    port.failure = const CommunityFailure('unavailable');
    live.setActive(true);
    await tester.pump();
    expect(port.reads, hasLength(1));
    await tester.pump(const Duration(seconds: 7));
    expect(port.reads, hasLength(1), reason: 'Not again after 4 seconds.');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(port.reads, hasLength(2));
    await tester.pump(const Duration(seconds: 15));
    expect(port.reads, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(port.reads, hasLength(3));
    // Capped at a minute.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
    }
    final count = port.reads.length;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
    }
    // Four minutes at the cap: about four reads, not sixty.
    expect(port.reads.length - count, inInclusiveRange(3, 5));
    port.failure = null;
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    final recovered = port.reads.length;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(port.reads, hasLength(recovered + 1));
    live.setActive(false);
  });

  test('growing while a read is out still fills the new rows', () async {
    final held = Completer<CommunityChatPage>();
    final slow = _HeldPort(held.future);
    final live = OrganizationChatPreviewAuthors(
      slow,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(milliseconds: 1),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await settle();
    live.shownCount = 5;
    held.complete(_page(messages: [{..._row(9), ..._identity(now)}]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(slow.reads[1], 0, reason: 'The next read is the newest window.');
    live.setActive(false);
  });

  test('shrinking and growing back while a read is out still refills', () async {
    final held = Completer<CommunityChatPage>();
    final slow = _HeldPort(held.future);
    final live = OrganizationChatPreviewAuthors(
      slow,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(milliseconds: 1),
    )..target = _target;
    addTearDown(live.dispose);
    live.setActive(true);
    await settle();
    live
      ..shownCount = 2
      ..shownCount = 3;
    held.complete(_page(messages: [{..._row(9), ..._identity(now)}]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(slow.reads[1], 0);
    live.setActive(false);
  });

  test('falling behind a burst goes back to the newest window', () async {
    final live = OrganizationChatPreviewAuthors(
      port,
      now: () => now,
      elapsed: () => elapsed,
      interval: const Duration(milliseconds: 1),
    )..target = _target;
    addTearDown(live.dispose);
    // Latest is 9 on the wire; this page only reached 1.
    port.answer = (_) => _page(
      messages: [
        {..._row(1), ..._identity(now)},
      ],
      latest: 9,
    );
    live.setActive(true);
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(port.reads.every((read) => read.$1 == 0), isTrue);
    live.setActive(false);
  });

  test('another scope is not trusted', () async {
    port.answer = (_) => _page(target: 'c' * 32, messages: [
      {..._row(1), ..._identity(now)},
    ]);
    authors.setActive(true);
    await settle();
    expect(authors.present(_message(1)).callsign, '');
  });

  group('the tile only asks while it is really on screen', () {
    Future<void> pump(
      WidgetTester tester,
      OrganizationCommunication communication, {
      bool onScreen = true,
      bool ticker = true,
    }) async {
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
        home: TickerMode(
          enabled: ticker,
          child: Scaffold(
            body: OfficialFleetChatTile(
              communication: communication,
              unread: 0,
              height: 100,
              onScreen: onScreen,
            ),
          ),
        ),
      ),
      );
      await tester.pump();
    }

    testWidgets('a client nobody is using stops; any input resumes it', (
      tester,
    ) async {
      final communication = OrganizationCommunication(
        (_) => throw UnimplementedError(),
      );
      addTearDown(communication.dispose);
      await pump(tester, communication);
      expect(communication.chatPreviewOnScreen, isTrue);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(communication.chatPreviewOnScreen, isFalse);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(communication.chatPreviewOnScreen, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(communication.chatPreviewOnScreen, isFalse);
    });

    testWidgets('page, ticker and window state each stop it', (tester) async {
      final communication = OrganizationCommunication(
        (_) => throw UnimplementedError(),
      );
      addTearDown(communication.dispose);
      await pump(tester, communication);
      expect(communication.chatPreviewOnScreen, isTrue);
      await pump(tester, communication, onScreen: false);
      expect(communication.chatPreviewOnScreen, isFalse);
      await pump(tester, communication);
      expect(communication.chatPreviewOnScreen, isTrue);
      await pump(tester, communication, ticker: false);
      expect(communication.chatPreviewOnScreen, isFalse);
      await pump(tester, communication);
      expect(communication.chatPreviewOnScreen, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(communication.chatPreviewOnScreen, isFalse, reason: 'Window not in front.');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(communication.chatPreviewOnScreen, isFalse, reason: 'Minimized.');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(communication.chatPreviewOnScreen, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(communication.chatPreviewOnScreen, isFalse);
    });
  });
}
