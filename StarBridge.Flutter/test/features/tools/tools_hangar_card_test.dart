import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'catalog_browse_test.dart' show size, disposePage;
import 'terminal_fixtures.dart';

class _Port extends TerminalHangarPort {
  int reads = 0;
  Completer<ExecHangarSnapshot>? pending;
  ExecHangarSnapshot? value;
  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) {
    reads++;
    return pending?.future ?? Future.value(value ?? snapshot);
  }
}

Future<void> _pump(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drive(WidgetTester t, Future<void> work) async {
  var done = false;
  Object? failure;
  unawaited(
    work
        .then(
          (_) {},
          onError: (Object e) {
            failure = e;
          },
        )
        .whenComplete(() => done = true),
  );
  for (var i = 0; i < 80 && !done; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue, reason: 'in-memory bridge work completes by pumping');
  if (failure != null) throw failure!;
}

ExecHangarSnapshot _timeline(DateTime now) => ExecHangarSnapshot(
  revision: 1,
  reminders: const ExecHangarReminders(),
  now: now,
  reliable: true,
  refreshFailed: false,
  deliveryState: 'idle',
  phases: [
    for (var i = 0; i < 6; i++)
      ExecHangarPhase(
        now.add(Duration(seconds: i * 3)),
        now.add(Duration(seconds: (i + 1) * 3)),
        i.isEven,
        i.isEven ? 3 : 0,
        i.isEven ? 1 : 4,
      ),
  ],
  windows: [
    for (var i = 0; i < 3; i++)
      ExecHangarWindow(
        now.add(Duration(seconds: i * 6)),
        now.add(Duration(seconds: i * 6 + 3)),
      ),
  ],
);

Map<String, Object?> _wire(ExecHangarSnapshot snapshot) => {
  'schemaVersion': 1,
  'revision': snapshot.revision,
  'reminders': snapshot.reminders.wire,
  'now': snapshot.now.toIso8601String(),
  'reliable': true,
  'refreshFailed': false,
  'deliveryState': 'idle',
  'config': {
    'version': 'fixture',
    'lastModified': 'fixture',
    'sourceUrl': 'https://example.invalid/calibration',
    'fetchedAt': snapshot.now.toIso8601String(),
  },
  'phases': [
    for (final phase in snapshot.phases)
      {
        'start': phase.start.toIso8601String(),
        'end': phase.end.toIso8601String(),
        'open': phase.open,
        'greenLights': phase.green,
        'redLights': phase.red,
      },
  ],
  'windows': [
    for (final window in snapshot.windows)
      {
        'open': window.open.toIso8601String(),
        'close': window.close.toIso8601String(),
      },
  ],
};

ExecHangarSnapshot _window(DateTime now, {bool reliable = true}) =>
    ExecHangarSnapshot(
      revision: 1,
      reminders: const ExecHangarReminders(),
      now: now,
      reliable: reliable,
      refreshFailed: false,
      deliveryState: 'ready',
      phases: [
        ExecHangarPhase(now, now.add(const Duration(seconds: 3)), true, 3, 1),
      ],
      windows: [ExecHangarWindow(now, now.add(const Duration(seconds: 3)))],
    );

void main() {
  testWidgets('identical replies keep later boundaries and consume each once', (
    t,
  ) async {
    size(t, 1440);
    var elapsed = Duration.zero;
    final now = DateTime.utc(2026, 11, 10);
    final port = _Port()..value = _timeline(now);
    final cache = CachedExecHangar(port, elapsed: () => elapsed);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    expect(port.reads, 1);
    for (final seconds in [3, 6, 9]) {
      elapsed = Duration(seconds: seconds);
      // Return a distinct object with the same snapshot contents and time.
      port.value = _timeline(now);
      await t.pump(const Duration(seconds: 1));
      await _pump(t);
      expect(port.reads, 1 + seconds ~/ 3);
      expect(cache.age, elapsed);
      expect(find.text('00:00:03'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(
        port.reads,
        1 + seconds ~/ 3,
        reason: 'no duplicate at this boundary',
      );
    }
    await disposePage(t);
  });

  testWidgets('failed boundary read still schedules the next known window', (
    t,
  ) async {
    size(t, 1440);
    var elapsed = Duration.zero;
    final port = _Port()..value = _timeline(DateTime.utc(2026, 11, 10));
    final cache = CachedExecHangar(port, elapsed: () => elapsed);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    port.pending = Completer<ExecHangarSnapshot>();
    elapsed = const Duration(seconds: 3);
    await t.pump(const Duration(seconds: 1));
    expect(port.reads, 2);
    port.pending!.completeError(StateError('synthetic boundary failure'));
    await _pump(t);
    expect(find.text('暂无数据'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(port.reads, 2);
    port.pending = null;
    elapsed = const Duration(seconds: 6);
    await t.pump(const Duration(seconds: 1));
    await _pump(t);
    expect(port.reads, 3);
    expect(find.text('开启中'), findsOneWidget);
    expect(find.text('暂无数据'), findsNothing);
    await disposePage(t);
  });

  testWidgets('covered route catches up once on return across a boundary', (
    t,
  ) async {
    size(t, 1440);
    var elapsed = Duration.zero;
    final port = _Port()..value = _timeline(DateTime.utc(2026, 11, 10));
    final cache = CachedExecHangar(port, elapsed: () => elapsed);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    final navigator = Navigator.of(t.element(find.byType(ToolsPage)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('cover'))),
      ),
    );
    await _pump(t);
    elapsed = const Duration(seconds: 4);
    await t.pump(const Duration(seconds: 4));
    expect(port.reads, 1, reason: 'covered tools route must not read');
    navigator.pop();
    await _pump(t);
    await t.pump(const Duration(seconds: 1));
    await _pump(t);
    expect(port.reads, 2);
    expect(find.text('00:00:02'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(port.reads, 2);
    elapsed = const Duration(seconds: 6);
    await t.pump(const Duration(seconds: 1));
    await _pump(t);
    expect(port.reads, 3);
    expect(find.text('开启中'), findsOneWidget);
    await disposePage(t);
  });

  for (final fail in [false, true]) {
    testWidgets('replacement cache ignores late A result: failure=$fail', (
      t,
    ) async {
      size(t, 1440);
      final a = _Port()..pending = Completer<ExecHangarSnapshot>();
      final b = _Port()..pending = Completer<ExecHangarSnapshot>();
      final cacheA = CachedExecHangar(a, elapsed: () => Duration.zero);
      final cacheB = CachedExecHangar(b, elapsed: () => Duration.zero);
      final selected = ValueNotifier(cacheA);
      await t.pumpWidget(
        terminalApp(
          ValueListenableBuilder<CachedExecHangar>(
            valueListenable: selected,
            builder: (_, cache, _) => ToolsPage(hangar: cache),
          ),
        ),
      );
      await _pump(t);
      expect(a.reads, 1);
      selected.value = cacheB;
      await _pump(t);
      expect(b.reads, 1);
      expect(find.text('正在获取行政机库状态…'), findsOneWidget);
      if (fail) {
        a.pending!.completeError(StateError('synthetic retired cache failure'));
      } else {
        a.pending!.complete(_window(DateTime.utc(2026, 11, 10)));
      }
      await _pump(t);
      await t.pump(const Duration(seconds: 5));
      expect(
        find.text('正在获取行政机库状态…'),
        findsOneWidget,
        reason: 'retired A must not clear the loading state of B',
      );
      expect(find.text('00:00:03'), findsNothing);
      expect(find.text('暂无数据'), findsNothing);
      b.pending!.complete(b.snapshot);
      await _pump(t);
      expect(find.text('00:10:00'), findsOneWidget);
      expect(find.text('00:00:03'), findsNothing);
      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('正在获取行政机库状态…'), findsNothing);
      expect([a.reads, b.reads], [1, 1]);
      expect(t.takeException(), isNull);
      await disposePage(t);
      selected.dispose();
    });
  }

  testWidgets('account generation change rejects an in-flight hangar result', (
    t,
  ) async {
    size(t, 1440);
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['execHangar.read']);
    final requests = <BridgeEnvelope>[];
    final listener = pair.host.incoming.listen((request) {
      if (request.messageType == 'request') requests.add(request);
    });
    final cache = CachedExecHangar(
      BridgeExecHangar(session),
      elapsed: () => Duration.zero,
    );
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    expect(requests, hasLength(1));
    session.advanceGeneration(2);
    session.acceptHostCapabilities(['execHangar.read']);
    await _pump(t);
    expect(cache.snapshot, isNull);
    expect(find.text('暂无数据'), findsOneWidget);
    await t.tap(find.byKey(const Key('tools-hangar-retry')));
    await _pump(t);
    expect(requests, hasLength(2));
    Future<void> reply(BridgeEnvelope request, ExecHangarSnapshot value) =>
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: _wire(value),
          ),
        );
    await _drive(t, reply(requests.first, _window(DateTime.utc(2026, 11, 10))));
    await _pump(t);
    expect(
      cache.snapshot,
      isNull,
      reason: 'account A result cannot enter account B',
    );
    expect(find.text('正在获取行政机库状态…'), findsOneWidget);
    expect(find.text('开启中'), findsNothing);
    final current = TerminalHangarPort().snapshot;
    await _drive(t, reply(requests.last, current));
    await _pump(t);
    expect(cache.snapshot?.now, current.now);
    expect(find.text('00:10:00'), findsOneWidget);
    expect(find.text('暂无数据'), findsNothing);
    expect(t.takeException(), isNull);
    await disposePage(t);
    // Closing the in-memory pair is real stream work, not test-clock work.
    await t.runAsync(() async {
      await listener.cancel();
      await session.close();
      await pair.host.close();
    });
  });

  testWidgets('known lamp phases tick locally until the open window closes', (
    t,
  ) async {
    size(t, 1440);
    var elapsed = Duration.zero;
    final now = DateTime.utc(2026, 11, 10);
    final port = _Port()
      ..value = ExecHangarSnapshot(
        revision: 1,
        reminders: const ExecHangarReminders(),
        now: now,
        reliable: true,
        refreshFailed: false,
        deliveryState: 'ready',
        phases: [
          ExecHangarPhase(now, now.add(const Duration(seconds: 3)), true, 3, 1),
          ExecHangarPhase(
            now.add(const Duration(seconds: 3)),
            now.add(const Duration(seconds: 10)),
            true,
            2,
            2,
          ),
        ],
        windows: [ExecHangarWindow(now, now.add(const Duration(seconds: 10)))],
      );
    final cache = CachedExecHangar(port, elapsed: () => elapsed);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    elapsed = const Duration(seconds: 4);
    await t.pump(const Duration(seconds: 1));
    expect(port.reads, 1);
    expect(find.text('00:00:06'), findsOneWidget);
    elapsed = const Duration(seconds: 11);
    await t.pump(const Duration(seconds: 1));
    await _pump(t);
    expect(port.reads, 2);
    await disposePage(t);
  });
  testWidgets('tools creates the shared hangar before any hangar page visit', (
    t,
  ) async {
    size(t, 1440);
    final port = _Port()..pending = Completer<ExecHangarSnapshot>();
    final features = createToolsFeatures(createPort: () => port);
    final tools = features.singleWhere((f) => f.id == 'tools');
    await t.pumpWidget(terminalApp(Builder(builder: tools.buildDestination)));
    await t.pump();
    expect(port.reads, 1);
    expect(find.text('正在获取行政机库状态…'), findsOneWidget);
    final cache = t.widget<ToolsPage>(find.byType(ToolsPage)).hangar;
    expect(cache, isNotNull);
    port.pending!.complete(port.snapshot);
    await _pump(t);
    expect(find.text('开启中'), findsOneWidget);
    expect(find.textContaining(RegExp(r'00:(09|10):')), findsOneWidget);
    await disposePage(t);
    tools.onDispose?.call();
  });

  testWidgets('failed initial read shows no data and retry recovers once', (
    t,
  ) async {
    size(t, 1440);
    final port = _Port()..pending = Completer<ExecHangarSnapshot>();
    final cache = CachedExecHangar(port, elapsed: () => Duration.zero);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    // App strings load asynchronously; the card starts its read on the next
    // frame. Fail the read only once the card is listening to it.
    await t.pump();
    expect(port.reads, 1);
    expect(find.text('正在获取行政机库状态…'), findsOneWidget);
    port.pending!.completeError(StateError('synthetic failure'));
    await _pump(t);
    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.text('正在获取行政机库状态…'), findsNothing);
    await t.pump(const Duration(seconds: 10));
    expect(port.reads, 1);
    port.pending = null;
    await t.tap(find.byKey(const Key('tools-hangar-retry')));
    await _pump(t);
    expect(port.reads, 2);
    expect(find.text('开启中'), findsOneWidget);
    expect(find.text('暂无数据'), findsNothing);
    await disposePage(t);
  });

  for (final narrow in [false, true]) {
    testWidgets(
      'retry inside the tile retries without opening the hangar: narrow=$narrow',
      (t) async {
        // The narrow case is 320 px at twice the text size: loading, no data
        // and the retry button must all fit the tile.
        size(t, narrow ? 320 : 1440);
        final opened = <String>[];
        final port = _Port()..pending = Completer<ExecHangarSnapshot>();
        final cache = CachedExecHangar(port, elapsed: () => Duration.zero);
        await t.pumpWidget(
          terminalApp(
            Actions(
              actions: {
                OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                  onInvoke: (intent) {
                    opened.add(intent.route);
                    return null;
                  },
                ),
              },
              child: ToolsPage(hangar: cache),
            ),
            scale: narrow ? 2 : 1,
          ),
        );
        await t.pump();
        expect(find.text('正在获取行政机库状态…'), findsOneWidget);
        expect(t.takeException(), isNull);
        port.pending!.completeError(StateError('synthetic failure'));
        await _pump(t);
        expect(find.text('暂无数据'), findsOneWidget);
        expect(t.takeException(), isNull);
        port.pending = null;
        await t.tap(find.byKey(const Key('tools-hangar-retry')));
        await _pump(t);
        expect(port.reads, 2);
        expect(opened, isEmpty);
        expect(find.text('开启中'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('tool-exec-hangar')));
        await _pump(t);
        expect(opened, ['/tools/exec-hangar']);
        await disposePage(t);
      },
    );
  }

  testWidgets('returning from hangar uses its fresh shared snapshot', (
    t,
  ) async {
    size(t, 1440);
    final port = _Port();
    final features = createToolsFeatures(createPort: () => port);
    final hangar = features.singleWhere((f) => f.id == 'execHangar');
    final tools = features.singleWhere((f) => f.id == 'tools');
    await t.pumpWidget(terminalApp(Builder(builder: hangar.buildDestination)));
    await _pump(t);
    expect(port.reads, 1);
    await t.pumpWidget(terminalApp(Builder(builder: tools.buildDestination)));
    await _pump(t);
    expect(port.reads, 1);
    expect(find.text('开启中'), findsOneWidget);
    await disposePage(t);
    tools.onDispose?.call();
  });

  testWidgets(
    'crossing a window adds one read even if the reply repeats old data',
    (t) async {
      size(t, 1440);
      var elapsed = Duration.zero;
      final port = _Port()..value = _window(DateTime.utc(2026, 11, 10));
      final cache = CachedExecHangar(port, elapsed: () => elapsed);
      await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
      await _pump(t);
      expect(port.reads, 1);
      elapsed = const Duration(seconds: 4);
      port.pending = Completer<ExecHangarSnapshot>();
      await t.pump(const Duration(seconds: 1));
      expect(port.reads, 2);
      await t.pump(const Duration(seconds: 5));
      expect(port.reads, 2);
      port.pending!.complete(port.value!);
      await _pump(t);
      elapsed = const Duration(seconds: 20);
      await t.pump(const Duration(seconds: 20));
      expect(port.reads, 2);
      await disposePage(t);
    },
  );

  testWidgets(
    'stale cache is read on entry while an in-flight read is shared',
    (t) async {
      size(t, 1440);
      var elapsed = Duration.zero;
      final port = _Port();
      final cache = CachedExecHangar(port, elapsed: () => elapsed);
      unawaited(cache.read());
      await _pump(t);
      elapsed = const Duration(minutes: 2);
      port.pending = Completer<ExecHangarSnapshot>();
      unawaited(cache.read());
      await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
      await _pump(t);
      expect(port.reads, 2);
      expect(find.text('正在获取行政机库状态…'), findsOneWidget);
      port.pending!.complete(port.snapshot);
      await _pump(t);
      expect(port.reads, 2);
      expect(find.text('开启中'), findsOneWidget);
      await disposePage(t);
    },
  );

  testWidgets('unreliable snapshot has an explicit retry state', (t) async {
    size(t, 1440);
    final port = _Port()
      ..value = _window(DateTime.utc(2026, 11, 10), reliable: false);
    final cache = CachedExecHangar(port, elapsed: () => Duration.zero);
    await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
    await _pump(t);
    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.byKey(const Key('tools-hangar-retry')), findsOneWidget);
    port.value = null;
    await t.tap(find.byKey(const Key('tools-hangar-retry')));
    await _pump(t);
    expect(port.reads, 2);
    expect(find.text('开启中'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets(
    'disposing the tools page stops boundary reads and ignores a late reply',
    (t) async {
      size(t, 1440);
      var elapsed = Duration.zero;
      final port = _Port()..value = _window(DateTime.utc(2026, 11, 10));
      final cache = CachedExecHangar(port, elapsed: () => elapsed);
      await t.pumpWidget(terminalApp(ToolsPage(hangar: cache)));
      await _pump(t);
      expect(port.reads, 1);
      port.pending = Completer<ExecHangarSnapshot>();
      elapsed = const Duration(seconds: 4);
      await t.pump(const Duration(seconds: 1));
      expect(port.reads, 2);
      await disposePage(t);
      port.pending!.complete(port.snapshot);
      elapsed = const Duration(hours: 1);
      await t.pump(const Duration(hours: 1));
      expect(port.reads, 2);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'hangar page polls from the last read when the server time repeats',
    (t) async {
      size(t, 1440);
      var elapsed = Duration.zero;
      final port = _Port();
      final cache = CachedExecHangar(port, elapsed: () => elapsed);
      await t.runAsync(cache.read);
      // Over a minute later the shared snapshot is stale; the next reply is a
      // new object with the same server time, so its age keeps counting.
      elapsed = const Duration(seconds: 70);
      await t.pumpWidget(terminalApp(ExecHangarPage(port: cache)));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final afterOpen = port.reads;
      expect(
        afterOpen,
        2,
        reason:
            'warm-up read plus exactly one read on open for the stale cache',
      );
      expect(
        cache.age.inSeconds,
        greaterThanOrEqualTo(70),
        reason: 'countdown is not rewound',
      );
      // A few seconds of page ticks must not poll again before the cadence.
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(
        port.reads,
        afterOpen,
        reason: 'no per-second polling after a repeated snapshot',
      );
      expect(t.takeException(), isNull);
      await disposePage(t);
    },
  );
}
