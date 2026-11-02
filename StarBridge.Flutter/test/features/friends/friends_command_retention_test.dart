import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'friends_test.dart' show PendingPort;
import '../direct_messages/direct_message_live_delivery_test.dart'
    show IncomingPort;

const _wirePath = String.fromEnvironment('STARBRIDGE_FRIEND_COMMAND_WIRE');
const _skipWire = _wirePath == ''
    ? 'Requires actual Native friend command wire'
    : false;
const _noWrite = [
  'busy',
  'rateLimited',
  'cooldown',
  'tooManyPending',
  'rejected',
];

FriendsReadResult _ready({String? query}) => FriendsReadResult(
  FriendsReadState.ready,
  snapshot: FriendsSnapshot(
    groups: query == null
        ? {
            FriendsSection.incoming: [_row()],
          }
        : {},
    results: query == null ? [] : [_row(search: true)],
    query: query,
  ),
);
FriendRow _row({bool search = false}) => FriendRow(
  'Loaded Pilot',
  '',
  search ? 'none' : 'incoming',
  DateTime.utc(2026),
  targetRef: '1' * 32,
  chatTargetRef: '2' * 32,
  conversationKey: '3' * 32,
  actions: search ? ['send'] : ['reject'],
  shared: {'presence': 'InGame'},
);

void main() {
  for (final error in _noWrite) {
    test(
      'definite no-write $error preserves readonly rows, time and viewport until explicit refresh',
      () async {
        var now = DateTime.utc(2026, 10, 17, 1);
        final port = _Commands();
        final module = FriendsModule(port, now: () => now);
        addTearDown(module.dispose);
        final read = module.enter();
        port.requests.single.complete(_ready());
        await read;
        module.select(FriendsSection.incoming);
        final view = module.viewEpoch;
        module.rememberScroll(173, expectedEpoch: view);
        final at = module.lastSuccessfulReadUtc;
        final old = module.rows.single;
        final action = module.execute(old, 'reject');
        now = now.add(const Duration(minutes: 1));
        expect(module.rows.single, same(old));
        port.reply.complete(FriendCommandResult('rejected', error: error));
        await action;
        expect(module.rows.single.callsign, 'Loaded Pilot');
        expect(module.section, FriendsSection.incoming);
        expect(module.scrollOffset, 173);
        expect(module.viewEpoch, view);
        expect(module.lastSuccessfulReadUtc, at);
        expect(module.refreshFailed, isTrue);
        expect(module.feedback, error);
        expect(module.feedbackSuccess, isFalse);
        final row = module.rows.single;
        expect(row.targetRef, isNull);
        expect(row.chatTargetRef, isNull);
        expect(row.conversationKey, isNull);
        expect(row.actions, isEmpty);
        expect(row.shared, isEmpty);
        expect(module.canExecute(old, 'reject'), isFalse);
        await module.execute(old, 'reject');
        await module.execute(row, 'reject');
        expect(port.writes, 1);
        expect(port.requests, hasLength(1));
        final retry = module.refresh();
        expect(module.rows.single.callsign, 'Loaded Pilot');
        port.requests.last.complete(_ready());
        await retry;
        expect(module.refreshFailed, isFalse);
        expect(module.canExecute(module.rows.single, 'reject'), isTrue);
        expect(module.lastSuccessfulReadUtc, now);
      },
    );
  }
  test('a rejected search retains input, selection, scroll and an independent chat draft', () async {
    final port = _Commands();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final chatPort = IncomingPort();
    final chat = module.chat(() => chatPort);
    await chat.openFriend(chatPort.peer);
    chat.editDraft('Unsent personal draft');
    final selected = chat.selected;
    module.select(FriendsSection.outgoing);
    module.editQuery('Pilot');
    final read = module.refresh();
    port.requests.single.complete(_ready(query: 'Pilot'));
    await read;
    final view = module.viewEpoch;
    module.rememberScroll(81, expectedEpoch: view);
    final action = module.execute(module.rows.single, 'send');
    port.reply.complete(
      const FriendCommandResult('rejected', error: 'cooldown'),
    );
    await action;
    expect(module.query, 'Pilot');
    expect(module.snapshot?.query, 'Pilot');
    expect(module.section, FriendsSection.outgoing);
    expect(module.scrollOffset, 81);
    expect(module.viewEpoch, view);
    expect(module.rows.single.callsign, 'Loaded Pilot');
    expect(chat.draft, 'Unsent personal draft');
    expect(chat.selected, same(selected));
  });
  for (final (status, error) in [
    ('unknown', 'rateLimited'),
    ('unknown', 'outcomeUnknown'),
    ('rejected', 'forbidden'),
    ('rejected', 'identityUnavailable'),
    ('rejected', 'targetChanged'),
    ('rejected', 'refreshRequired'),
    ('rejected', 'unrecognized'),
    ('accepted', null),
  ]) {
    test(
      '$status/$error never preserves command authority or attention',
      () async {
        final port = _Commands();
        final module = FriendsModule(port);
        addTearDown(module.dispose);
        final read = module.enter();
        port.requests.single.complete(_ready());
        await read;
        module.select(FriendsSection.incoming);
        expect(module.incomingAttention.value, 1);
        final row = module.rows.single;
        final action = module.execute(row, 'reject');
        port.reply.complete(FriendCommandResult(status, error: error));
        await action;
        expect(module.snapshot, isNull);
        expect(module.lastSuccessfulReadUtc, isNull);
        expect(module.incomingAttention.value, 0);
        expect(module.canExecute(row, 'reject'), isFalse);
        await module.execute(row, 'reject');
        expect(port.writes, 1);
      },
    );
  }
  test('account invalidation rejects a late definite rejection', () async {
    final port = _Commands();
    final module = FriendsModule(port);
    addTearDown(module.dispose);
    final read = module.enter();
    port.requests.single.complete(_ready());
    await read;
    module.select(FriendsSection.incoming);
    final action = module.execute(module.rows.single, 'reject');
    port.events.add(null);
    port.requests.last.complete(
      const FriendsReadResult(FriendsReadState.signedOut),
    );
    port.reply.complete(
      const FriendCommandResult('rejected', error: 'rateLimited'),
    );
    await action;
    await Future<void>.delayed(Duration.zero);
    expect(module.snapshot, isNull);
    expect(module.state, FriendsReadState.signedOut);
    expect(module.feedback, isNull);
  });
  for (final changed in [false, true]) {
    test(
      'confirmed directory freshness respects concurrent content invalidation: $changed',
      () async {
        var now = DateTime.utc(2026, 10, 17, 1);
        final port = _Commands();
        final module = FriendsModule(port, now: () => now);
        addTearDown(module.dispose);
        final read = module.enter();
        port.requests.single.complete(_ready());
        await read;
        module.select(FriendsSection.incoming);
        final action = module.execute(module.rows.single, 'reject');
        now = now.add(const Duration(seconds: 1));
        if (changed) {
          port.activity.add(null);
        }
        port.reply.complete(
          FriendCommandResult(
            'accepted',
            directory: FriendsSnapshot(groups: {}, results: []),
          ),
        );
        await action;
        expect(module.lastSuccessfulReadUtc, now);
        final entering = module.enter();
        expect(port.requests, hasLength(changed ? 2 : 1));
        if (changed) {
          port.requests.last.complete(_ready());
        }
        await entering;
      },
    );
  }
  for (final outcome in ['rejected', 'accepted', 'unknown']) {
    test(
      'actual Native $outcome command drives retained presentation without replay',
      () async {
        final h = _Native(outcome);
        addTearDown(h.close);
        await h.module.enter();
        h.module.select(FriendsSection.incoming);
        final at = h.module.lastSuccessfulReadUtc;
        final row = h.module.rows.single;
        final action = h.module.execute(row, 'reject');
        await h.command.future;
        await h.finish();
        await action;
        expect(h.writes, 1);
        if (outcome == 'rejected') {
          expect(h.module.rows.single.callsign, 'Stored Incoming');
          expect(h.module.lastSuccessfulReadUtc, at);
          expect(h.module.refreshFailed, isTrue);
          expect(h.module.canExecute(row, 'reject'), isFalse);
          expect(h.reads, 1);
          await h.module.refresh();
          expect(h.module.canExecute(h.module.rows.single, 'reject'), isTrue);
          expect(h.module.rows.single.targetRef, isNot(row.targetRef));
        } else if (outcome == 'accepted') {
          expect(h.module.rows, isEmpty);
          expect(h.module.lastSuccessfulReadUtc, isNotNull);
          await h.module.enter();
          expect(h.reads, 1);
        } else {
          expect(h.module.snapshot, isNull);
          expect(h.module.incomingAttention.value, 0);
        }
        expect(h.writes, 1);
      },
      skip: _skipWire,
    );
  }
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale actual rejected command keeps visible content with dated feedback and no repeat action',
      (tester) async {
        final h = (await tester.runAsync(() async => _Native('rejected')))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(h.close);
        });
        await tester.runAsync(h.module.enter);
        h.module.select(FriendsSection.incoming);
        await tester.pumpWidget(
          _app(
            FriendsPage(
              createPort: () => throw StateError('borrowed'),
              module: h.module,
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        final row = h.module.rows.single;
        await tester.tap(
          find.byKey(ValueKey('friend-reject-${row.targetRef}')),
        );
        for (var i = 0; i < 20 && !h.command.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
        }
        expect(
          h.command.isCompleted,
          isTrue,
          reason:
              'The real async transport must reach the command before replying',
        );
        await tester.runAsync(h.finish);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        expect(
          find.text(AppStrings.resolve(locale).text('friends.rateLimited')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('friends-sync-failed')), findsOneWidget);
        expect(find.byKey(const Key('friends-cached-display')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('friends-sync-failed')))
              .data,
          contains('2026'),
        );
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.partial,
        );
        expect(h.module.canExecute(row, 'reject'), isFalse);
        expect(h.writes, 1);
        await tester.tap(find.byKey(const Key('friends-refresh')));
        for (var i = 0; i < 20 && h.module.reading; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        expect(find.byKey(const Key('friends-sync-failed')), findsNothing);
        expect(h.module.canExecute(h.module.rows.single, 'reject'), isTrue);
        expect(h.writes, 1);
      },
      skip: _wirePath == '',
    );
  }
}

class _Commands extends PendingPort
    implements FriendsCommandPort, FriendsActivityPort {
  final reply = Completer<FriendCommandResult>();
  int writes = 0;
  final activity = StreamController<void>.broadcast(sync: true);
  @override
  bool get commandsAvailable => true;
  @override
  Stream<void> get changes => activity.stream;
  @override
  Future<FriendCommandResult> execute(String action, String target) {
    writes++;
    return reply.future;
  }

  @override
  Future<void> close() async {
    await activity.close();
    await super.close();
  }
}

final class _Native {
  _Native(String outcome) {
    wire =
        ((jsonDecode(File(_wirePath).readAsStringSync()) as Map)['captures']
                as List)
            .cast<Map>()
            .singleWhere((item) => item['outcome'] == outcome);
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: frame('root').sessionGeneration,
    )..acceptHostCapabilities(['friends.read', 'friends.commands']);
    module = FriendsModule(BridgeFriendsAdapter(session));
    subscription = pair.host.incoming.listen((request) async {
      if (request.name == 'account.getCurrent') {
        await reply(request, frame('root'));
      } else if (request.name == 'friends.read') {
        reads++;
        await reply(request, frame(reads == 1 ? 'directory' : 'refreshed'));
      } else if (request.name == 'friends.execute') {
        writes++;
        expectSync(request.payload, frame('request').payload);
        if (!command.isCompleted) {
          command.complete(request);
        }
      }
    });
  }
  late final Map wire;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final FriendsModule module;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final command = Completer<BridgeEnvelope>();
  int reads = 0, writes = 0;
  BridgeEnvelope frame(String key) =>
      BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
  Future<void> reply(BridgeEnvelope request, BridgeEnvelope source) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: source.status,
          payload: source.payload,
          accountContext: source.accountContext,
        ),
      );
  Future<void> finish() async {
    await reply(await command.future, frame('command'));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close() async {
    module.dispose();
    await session.close();
    await subscription.cancel();
    await pair.host.close();
  }
}

Widget _app(Widget child, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: child),
);
