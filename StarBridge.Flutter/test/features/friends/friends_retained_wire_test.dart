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
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

const _path = String.fromEnvironment('STARBRIDGE_FRIENDS_OUTCOMES_WIRE');
const _skip = _path == ''
    ? 'Requires actual Native friends outcome producer'
    : false;
Map<String, Object?> _capture(String outcome) =>
    ((jsonDecode(File(_path).readAsStringSync()) as Map)['captures'] as List)
        .cast<Map>()
        .singleWhere((item) => item['outcome'] == outcome)
        .cast<String, Object?>();

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale Native cached friends remain visible with historical date and read-only notice',
      (tester) async {
        final h = (await tester.runAsync(
          () async => _Harness(_capture('outage')),
        ))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(h.close);
        });
        await tester.runAsync(() async {
          await h.start();
          await h.progress();
        });
        h.friends.select(FriendsSection.incoming);
        await tester.pumpWidget(
          MaterialApp(
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
            home: Scaffold(
              body: FriendsPage(
                createPort: () => throw StateError('borrowed'),
                module: h.friends,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        final text = tester
            .widget<Text>(find.byKey(const Key('friends-cached-display')))
            .data!;
        expect(
          text,
          startsWith(
            AppStrings.resolve(locale)
                .text('friends.cachedAt')
                .split('{time}')
                .first,
          ),
        );
        expect(text, contains('2026'));
        expect(find.byKey(const Key('friends-syncing')), findsOneWidget);
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.partial,
        );
        await tester.runAsync(() async {
          await h.completeRoot();
          await h.loading;
        });
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        expect(find.byKey(const Key('friends-cached-display')), findsOneWidget);
        expect(find.byKey(const Key('friends-sync-failed')), findsOneWidget);
        expect(find.byKey(const Key('friends-syncing')), findsNothing);
        expect(h.friends.incomingAttention.value, 0);
      },
      skip: _path == '',
    );
  }
  for (final boundary in ['account', 'generation', 'disconnect', 'mode']) {
    test('Native friends display withdraws during auth: $boundary', () async {
      final h = _Harness(_capture('outage'));
      addTearDown(h.close);
      await h.start();
      await h.progress();
      h.expectCached();
      if (boundary == 'generation') {
        h.session.advanceGeneration(1);
      } else if (boundary == 'disconnect') {
        await h.session.close();
      } else if (boundary == 'mode') {
        await h.session.runConnectionModeChange(() async {});
      } else {
        await h.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: 0,
            sequence: h.frame('prepared').sequence! + 1,
            payload: const {'schemaVersion': 1},
          ),
        );
      }
      await _drain();
      expect(h.friends.snapshot, isNull);
    }, skip: _skip);
  }
  for (final boundary in ['generation', 'mode', 'account']) {
    test('late cached directory cannot return after $boundary', () async {
      final h = _Harness(_capture('outage'), holdCached: true);
      addTearDown(h.close);
      await h.start();
      await h.progress();
      final cached = await h.cached.future;
      if (boundary == 'generation') {
        h.session.advanceGeneration(1);
      } else if (boundary == 'mode') {
        await h.session.runConnectionModeChange(() async {});
      } else {
        await h.pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: 0,
            sequence: h.frame('prepared').sequence! + 1,
            payload: const {'schemaVersion': 1},
          ),
        );
      }
      await _drain();
      await h.reply(cached, h.frame('cached'));
      await _drain();
      expect(h.friends.snapshot, isNull);
    }, skip: _skip);
  }
  for (final outcome in ['outage', 'success', 'reject']) {
    test('Native friends display follows original auth outcome: $outcome', () async {
      final h = _Harness(_capture(outcome));
      addTearDown(h.close);
      await h.start();
      await h.progress();
      h.expectCached();
      await h.completeRoot();
      if (outcome == 'success') {
        expect(
          h.friends.snapshot,
          isNotNull,
          reason: 'Matching signed-in handoff retains materialized rows',
        );
        final live = await h.live.future;
        expect(h.friends.reading, isTrue);
        expect(h.friends.incomingAttention.value, 0);
        await h.reply(live, h.frame('liveDirectory'));
        await h.loading;
        expect(h.friends.displayOnly, isFalse);
        expect(h.friends.incomingAttention.value, 1);
      } else {
        await h.loading;
        if (outcome == 'outage') {
          h.expectCached(reading: false);
          expect(h.friends.refreshFailed, isTrue);
          h.session.advanceGeneration(1);
          await _drain();
          expect(
            h.friends.snapshot,
            isNull,
            reason: 'Completed outage display cannot survive a new generation',
          );
        } else {
          expect(h.friends.snapshot, isNull);
        }
      }
      // The AccountModule may refresh after the actual account.changed event.
      // Only the original generation is shared; completed roots are not cached.
      expect(
        h.requests.where(
          (r) => r.name == 'account.getCurrent' && r.sessionGeneration == 0,
        ),
        hasLength(1),
        reason: h.trace.join('; '),
      );
      expect(h.requests.where((r) => r.name == 'friends.execute'), isEmpty);
    }, skip: _skip);
  }
  test(
    'outage root can supply a retained selector without progress delivery',
    () async {
      final h = _Harness(_capture('outage'));
      addTearDown(h.close);
      await h.start();
      await h.completeRoot();
      await h.loading;
      h.expectCached(reading: false);
    },
    skip: _skip,
  );
  test(
    'search cancels pending cached display and never adopts late directory',
    () async {
      final h = _Harness(_capture('outage'), holdCached: true);
      addTearDown(h.close);
      await h.start();
      await h.progress();
      final cached = await h.cached.future;
      h.friends.editQuery('Pilot');
      await h.reply(cached, h.frame('cached'));
      await _drain();
      expect(h.friends.snapshot, isNull);
      expect(h.friends.query, 'Pilot');
      expect(h.friends.displayOnly, isFalse);
    },
    skip: _skip,
  );
  for (final field in [
    'conversationKey',
    'chatTargetRef',
    'shared',
    'avatarImageData',
  ]) {
    test('cache rejects unexpected historical $field', () async {
      final h = _Harness(_capture('outage'), holdCached: true);
      addTearDown(h.close);
      await h.start();
      await h.progress();
      final cached = await h.cached.future;
      final body = jsonDecode(jsonEncode(h.frame('cached').payload)) as Map;
      ((body['directory'] as Map)['incoming'] as List).single[field] =
          switch (field) {
            'shared' => {'presence': 'InGame'},
            'avatarImageData' => 'data:image/png;base64,AAAA',
            _ => '1' * 32,
          };
      await h.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: cached.name,
          correlationId: cached.correlationId,
          sessionGeneration: 0,
          status: 'ok',
          payload: body.cast<String, Object?>(),
        ),
      );
      await _drain();
      expect(h.friends.snapshot, isNull);
    }, skip: _skip);
  }
}

Future<void> _drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness {
  _Harness(this.wire, {this.holdCached = false}) {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 0)
      ..acceptHostCapabilities([
        'friends.read',
        'account.restoreDisplay',
        'account.offlineData.read',
      ]);
    account = createAccountModule(BridgeAccountAdapter(session));
    final adapter = BridgeFriendsAdapter(session);
    friends = FriendsModule(adapter);
    cacheSubscription = adapter.cachedDisplays.listen((cache) {
      trace.add(
        'cache=${cache != null},reading=${friends.reading},state=${friends.state},display=${friends.displayOnly}',
      );
    });
    friends.addListener(
      () => trace.add(
        'module reading=${friends.reading},state=${friends.state},display=${friends.displayOnly},snapshot=${friends.snapshot != null},failure=${friends.failure}',
      ),
    );
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (request.name == 'account.getCurrent' && !root.isCompleted) {
        root.complete(request);
      }
      if (request.name == 'friends.read' && !live.isCompleted) {
        live.complete(request);
      }
      if (request.name == 'account.offlineData.read' &&
          request.payload['kind'] == 'friends') {
        if (!cached.isCompleted) cached.complete(request);
        if (!holdCached) await reply(request, frame('cached'));
      }
    });
  }
  final Map<String, Object?> wire;
  final bool holdCached;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final AccountModule account;
  late final FriendsModule friends;
  final requests = <BridgeEnvelope>[];
  final trace = <String>[];
  late final StreamSubscription<FriendsCachedDisplay?> cacheSubscription;
  final root = Completer<BridgeEnvelope>(),
      live = Completer<BridgeEnvelope>(),
      cached = Completer<BridgeEnvelope>();
  late final StreamSubscription<BridgeEnvelope> subscription;
  late Future<void> restoring, loading;
  BridgeEnvelope frame(String key) =>
      BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
  Future<void> start() async {
    restoring = account.initialize();
    loading = friends.enter();
    await root.future;
  }

  Future<void> progress() async {
    final event = frame('prepared');
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: event.name,
        sequence: event.sequence,
        sessionGeneration: 0,
        payload: {
          ...event.payload,
          'rootCorrelationId': (await root.future).correlationId,
        },
      ),
    );
    await _drain();
  }

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
  Future<void> completeRoot() async {
    await reply(await root.future, frame('completed'));
    for (final raw in (wire['events'] as List)) {
      await pair.host.send(
        BridgeEnvelope.fromJson((raw as Map).cast<String, Object?>()),
      );
    }
    await _drain();
  }

  void expectCached({bool reading = true}) {
    expect(
      friends.snapshot?.groups[FriendsSection.incoming]?.single.callsign,
      'Stored Incoming',
      reason: 'Requests: ${requests.map((r) => r.name)}; ${trace.join('; ')}',
    );
    expect(friends.reading, reading);
    expect(friends.displayOnly, isTrue);
    expect(friends.incomingAttention.value, 0);
    final row = friends.snapshot!.groups[FriendsSection.incoming]!.single;
    expect(row.actions, isEmpty);
    expect(row.targetRef, isNull);
    expect(row.chatTargetRef, isNull);
    expect(row.conversationKey, isNull);
    expect(friends.canExecute(row, 'accept'), isFalse);
    expect(
      friends.lastSuccessfulReadUtc,
      DateTime.parse(frame('cached').payload['cachedAtUtc']! as String),
    );
  }

  Future<void> close() async {
    friends.dispose();
    account.dispose();
    await session.close();
    await subscription.cancel();
    await cacheSubscription.cancel();
    await pair.host.close();
    await restoring;
    await loading;
  }
}
