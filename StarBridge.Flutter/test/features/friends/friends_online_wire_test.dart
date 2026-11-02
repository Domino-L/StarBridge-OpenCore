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
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

const _path = String.fromEnvironment('STARBRIDGE_FRIENDS_ONLINE_WIRE');
const _skip = _path == ''
    ? 'Requires actual Native signed-in cache progress wire'
    : false;

void main() {
  test(
    'generic display progress cannot replace account restoration observation',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen(requests.add);
      try {
        expect(
          () => session.beginRequest(
            'account.getCurrent',
            payload: const {'schemaVersion': 1},
            displayProgress: BridgeDisplayProgress(
              'account.getCurrentDisplay',
              (_) {},
            ),
          ),
          throwsArgumentError,
        );
        expect(requests, isEmpty);
      } finally {
        await session.close();
        await subscription.cancel();
        await pair.host.close();
      }
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final outcome in ['success', 'transient']) {
      testWidgets(
        '$locale signed-in cached page remains visible through $outcome',
        (tester) async {
          final h = (await tester.runAsync(() async => _Online(outcome)))!;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(h.close);
          });
          await tester.runAsync(h.start);
          await tester.runAsync(_drain);
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
          expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
          expect(
            find.byKey(const Key('friends-cached-display')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('friends-syncing')), findsOneWidget);
          expect(
            tester
                .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
                .status,
            LoadingContentStatus.partial,
          );
          await tester.runAsync(h.complete);
          await tester.runAsync(() => h.loading);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
          expect(
            find.byKey(const Key('friends-cached-display')),
            outcome == 'success' ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(const Key('friends-sync-failed')),
            outcome == 'transient' ? findsOneWidget : findsNothing,
          );
        },
        skip: _path == '',
      );
    }
  }
  test('reentrant mode pause retires the exact resource read even before beginRequest returns', () async {
    final connection = _Immediate(_capture('success'));
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: connection.frame('root').sessionGeneration,
    )..acceptHostCapabilities(['friends.read', 'friends.readDisplay']);
    final module = FriendsModule(BridgeFriendsAdapter(session));
    Future<void>? changing;
    module.addListener(() {
      if (module.displayOnly) {
        changing ??= session.runConnectionModeChange(() async {});
      }
    });
    final loading = module.enter();
    try {
      await loading.timeout(const Duration(milliseconds: 250));
      await changing;
      final original = connection.requests.singleWhere(
        (r) => r.name == 'friends.read',
      );
      expect(
        connection.requests
            .where((r) => r.name == 'bridge.cancel')
            .single
            .payload['targetCorrelationId'],
        original.correlationId,
      );
      expect(module.snapshot, isNull);
    } finally {
      module.dispose();
      await session.close();
      await loading;
    }
  }, skip: _skip);
  test('completed transient display withdraws on mode change without restore capability', () async {
    final h = _Online('transient', restoring: false);
    addTearDown(h.close);
    await h.start();
    await _drain();
    await h.complete();
    await h.loading;
    expect(h.module.snapshot, isNotNull);
    await h.session.runConnectionModeChange(() async {});
    await _drain();
    expect(h.module.snapshot, isNull);
  }, skip: _skip);
  test('wrong correlation, generation, event and authority metadata cannot supply a display', () async {
    final h = _Online('success', automaticProgress: false);
    addTearDown(h.close);
    await h.start();
    await h.sendProgress(correlationId: 'foreign-read');
    await h.sendProgress(generation: h.session.activeGeneration + 1);
    await h.sendProgress(eventName: 'foreign.display');
    await h.sendProgress(accountContext: h.frame('root').accountContext);
    await _drain();
    expect(h.module.snapshot, isNull);
    expect(h.module.reading, isTrue);
    await h.sendProgress();
    await _drain();
    expect(h.module.rows.single.callsign, 'Stored Incoming');
    await h.complete();
    await h.loading;
  }, skip: _skip);
  for (final bad in ['schema', 'time', 'action', 'sharing', 'extra']) {
    test(
      'malformed $bad cached progress cannot fail the original fresh directory',
      () async {
        final h = _Online('success', automaticProgress: false);
        addTearDown(h.close);
        await h.start();
        final body = (jsonDecode(
          jsonEncode(h.frame('prepared').payload),
        ) as Map).cast<String, Object?>();
        if (bad == 'schema') {
          body['schemaVersion'] = '1';
        } else if (bad == 'time') {
          body['cachedAtUtc'] = '2026-01-01T00:00:00';
        } else if (bad == 'extra') {
          body['privileged'] = true;
        } else {
          final row =
              ((body['directory'] as Map)['incoming'] as List).single as Map;
          if (bad == 'action') {
            row['targetRef'] = '1' * 32;
            row['actions'] = ['reject'];
          } else {
            row['shared'] = {'presence': 'InGame'};
          }
        }
        await h.sendProgress(payload: body);
        await _drain();
        expect(h.module.snapshot, isNull);
        expect(h.module.reading, isTrue);
        await h.complete();
        await h.loading;
        expect(h.module.rows.single.callsign, 'Updated Incoming');
      },
      skip: _skip,
    );
  }
  test('timed-out read keeps dated readonly display but ignores late terminal data', () async {
    final h = _Online(
      'success',
      restoring: false,
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(h.close);
    await h.start();
    await _drain();
    expect(h.module.rows.single.callsign, 'Stored Incoming');
    await h.loading;
    expect(h.module.refreshFailed, isTrue);
    await h.complete();
    expect(h.module.rows.single.callsign, 'Stored Incoming');
  }, skip: _skip);
  for (final outcome in ['success', 'transient', 'forbidden', 'cancel']) {
    test(
      'actual Native signed-in cache is visible before original $outcome directory completes',
      () async {
        final h = _Online(outcome);
        addTearDown(h.close);
        await h.start();
        await _drain();
        expect(h.module.rows.single.callsign, 'Stored Incoming');
        expect(h.module.reading, isTrue);
        expect(h.module.displayOnly, isTrue);
        expect(h.module.incomingAttention.value, 0);
        expect(h.module.canExecute(h.module.rows.single, 'reject'), isFalse);
        final at = DateTime.parse(
          h.frame('prepared').payload['cachedAtUtc']! as String,
        );
        expect(h.module.lastSuccessfulReadUtc, at);
        expect(
          h.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(1),
        );
        await h.complete();
        await h.loading;
        if (outcome == 'success') {
          expect(h.module.rows.single.callsign, 'Updated Incoming');
          expect(h.module.displayOnly, isFalse);
          expect(h.module.canExecute(h.module.rows.single, 'reject'), isTrue);
          await h.sendProgress();
          await _drain();
          expect(
            h.module.rows.single.callsign,
            'Updated Incoming',
            reason:
                'Late progress cannot revive old data after terminal response',
          );
        } else if (outcome == 'transient') {
          expect(h.module.rows.single.callsign, 'Stored Incoming');
          expect(h.module.refreshFailed, isTrue);
          expect(h.module.lastSuccessfulReadUtc, at);
        } else {
          expect(h.module.snapshot, isNull);
          expect(h.module.incomingAttention.value, 0);
        }
      },
      skip: _skip,
    );
  }
  for (final boundary in [
    'generation',
    'mode',
    'account',
    'search',
    'disconnect',
  ]) {
    test(
      'signed-in cached progress withdraws and cannot arrive late after $boundary',
      () async {
        final h = _Online('success');
        addTearDown(h.close);
        await h.start();
        await _drain();
        expect(h.module.snapshot, isNotNull);
        h.retired = true;
        if (boundary == 'generation') {
          h.session.advanceGeneration(h.session.activeGeneration + 1);
        } else if (boundary == 'mode') {
          await h.session.runConnectionModeChange(() async {});
        } else if (boundary == 'account') {
          await h.pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'bootstrap.invalidated',
              sessionGeneration: h.session.activeGeneration,
              sequence: ++h.sequence,
              payload: const {'schemaVersion': 1},
            ),
          );
        } else if (boundary == 'search') {
          h.module.editQuery('Pilot');
        } else {
          await h.session.close();
        }
        await _drain();
        expect(h.module.snapshot, isNull);
        if (boundary != 'disconnect') {
          await h.sendProgress();
          await _drain();
          expect(h.module.snapshot, isNull);
        }
      },
      skip: _skip,
    );
  }
  test('older Host receives the original payload and completes fresh without cached progress', () async {
    final h = _Online('success', enabled: false);
    addTearDown(h.close);
    await h.start();
    await _drain();
    expect(
      (await h.read.future).payload.containsKey('cachedDisplayProgress'),
      isFalse,
    );
    expect(h.module.snapshot, isNull);
    await h.complete();
    await h.loading;
    expect(h.module.rows.single.callsign, 'Updated Incoming');
  }, skip: _skip);
}

Future<void> _drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map _capture(String outcome) =>
    ((jsonDecode(File(_path).readAsStringSync()) as Map)['captures'] as List)
        .cast<Map>()
        .singleWhere((row) => row['outcome'] == outcome);

final class _Online {
  _Online(
    String outcome, {
    bool enabled = true,
    bool automaticProgress = true,
    bool restoring = true,
    Duration? timeout,
  }) {
    wire = _capture(outcome);
    sequence = frame('prepared').sequence! - 1;
    session =
        BridgeClientSession(
          connection: pair.client,
          sessionGeneration: frame('root').sessionGeneration,
          requestTimeout: timeout ?? const Duration(seconds: 15),
        )..acceptHostCapabilities([
          'friends.read',
          'friends.commands',
          if (restoring) ...[
            'account.restoreDisplay',
            'account.offlineData.read',
          ],
          if (enabled) 'friends.readDisplay',
        ]);
    module = FriendsModule(BridgeFriendsAdapter(session));
    module.select(FriendsSection.incoming);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (retired) return;
      if (request.name == 'account.getCurrent') {
        await reply(request, frame('root'));
      } else if (request.name == 'friends.read') {
        if (!read.isCompleted) read.complete(request);
        if (automaticProgress &&
            request.payload['cachedDisplayProgress'] == true) {
          await sendProgress();
        }
      }
    });
  }
  late final Map wire;
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final FriendsModule module;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final read = Completer<BridgeEnvelope>();
  late Future<void> loading;
  late int sequence;
  bool retired = false;
  BridgeEnvelope frame(String key) =>
      BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
  Future<void> start() async {
    loading = module.enter();
    await read.future;
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
          error: source.error,
          accountContext: source.accountContext,
        ),
      );
  Future<void> sendProgress({
    String? correlationId,
    int? generation,
    String? eventName,
    Map<String, Object?>? payload,
    BridgeAccountContext? accountContext,
  }) async {
    final source = frame('prepared');
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: eventName ?? source.name,
        sessionGeneration: generation ?? source.sessionGeneration,
        sequence: ++sequence,
        accountContext: accountContext,
        payload: {
          ...?payload,
          if (payload == null) ...source.payload,
          'requestCorrelationId':
              correlationId ?? (await read.future).correlationId,
        },
      ),
    );
  }

  Future<void> complete() async {
    await reply(await read.future, frame('completed'));
    await _drain();
  }

  Future<void> close() async {
    module.dispose();
    await session.close();
    await subscription.cancel();
    await pair.host.close();
    await loading;
  }
}

final class _Immediate implements BridgeConnection {
  _Immediate(this.wire);
  final Map wire;
  final incomingController = StreamController<BridgeEnvelope>.broadcast(
    sync: true,
  );
  final requests = <BridgeEnvelope>[];
  BridgeEnvelope frame(String key) =>
      BridgeEnvelope.fromJson((wire[key] as Map).cast<String, Object?>());
  @override
  Stream<BridgeEnvelope> get incoming => incomingController.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    requests.add(request);
    if (request.name == 'account.getCurrent') {
      final root = frame('root');
      incomingController.add(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: root.status,
          payload: root.payload,
          accountContext: root.accountContext,
        ),
      );
    } else if (request.name == 'friends.read') {
      final progress = frame('prepared');
      incomingController.add(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: progress.name,
          sessionGeneration: request.sessionGeneration,
          sequence: progress.sequence,
          payload: {
            ...progress.payload,
            'requestCorrelationId': request.correlationId,
          },
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    unawaited(incomingController.close());
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
