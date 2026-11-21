import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/catalog_recent_session.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_recent.dart';
import 'package:starbridge_flutter/features/tools/key_bindings_port.dart';
import 'package:starbridge_flutter/features/tools/mission_records_controller.dart';
import 'package:starbridge_flutter/features/tools/mission_records_port.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';
import 'package:starbridge_flutter/features/tools/tools_snapshot_cache.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'catalog_bridge_test.dart' show Mode;
import 'catalog_browse_test.dart' show size, settle, tap, disposePage;
import 'catalog_samples.dart';
import 'mission_records_samples.dart' show record;
import 'terminal_fixtures.dart';

const _keys = KeyBindingsSnapshot(
  state: 'ok',
  channel: 'LIVE',
  maps: [
    KeyBindingMap('player', [
      KeyBindingAction('sample', [
        KeyBindingEntry(
          device: 'keyboardMouse',
          instance: 1,
          input: 'w',
          customized: false,
        ),
      ]),
    ]),
  ],
);

class _KeyPort implements KeyBindingsPort {
  int reads = 0;
  Completer<KeyBindingsSnapshot>? held;
  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) async {
    reads++;
    return await (held?.future ?? Future.value(_keys));
  }

  @override
  Future<void> saveView(KeyBindingsView view) async {}
}

/// Drives work that completes on the widget test clock (the in-memory bridge
/// and its queued history writes) instead of awaiting it from the fake zone.
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
  expect(done, isTrue, reason: 'work driven on the test clock completes');
  if (failure != null) throw failure!;
}

class _HistoryStore extends MemoryCatalogRecentStore {
  final reads = <String>[];
  final writes = <String>[];
  @override
  Future<CatalogRow> read(String owner) {
    reads.add(owner);
    return super.read(owner);
  }

  @override
  Future<void> write(String owner, CatalogRow value) {
    writes.add(owner);
    return super.write(owner, value);
  }
}

/// All account and summary replies stay in memory; no Host or HTTP is opened.
class _AccountHarness {
  _AccountHarness() {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    listener = pair.host.incoming.listen((request) {
      if (request.messageType != 'request') return;
      if (request.name == 'account.getCurrent') {
        accounts.add(request);
        if (!hold) unawaited(reply(request));
      } else if (request.name == 'missionRecords.summary') {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              accountContext: owner,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'groups': [record()],
                'total': 3,
                'importAvailable': false,
              },
            ),
          ),
        );
      }
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> listener;
  final accounts = <BridgeEnvelope>[];
  bool hold = false;
  String subject = 'account-A';
  BridgeAccountContext get owner => BridgeAccountContext(
    environment: 'fixture',
    authority: 'synthetic',
    subject: subject,
  );

  Future<void> reply(BridgeEnvelope request, {bool fail = false}) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: fail ? 'error' : 'ok',
          accountContext: fail ? null : owner,
          payload: const {'schemaVersion': 1},
          error: fail
              ? const BridgeErrorBody(
                  code: 'account.unavailable',
                  message: 'Synthetic failure',
                  retryable: false,
                )
              : null,
        ),
      );

  Future<void> close() async {
    await listener.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  testWidgets(
    'shortcut keys survive the first tools account binding and logout',
    (t) async {
      size(t, 1440);
      final bridge = _AccountHarness(), recent = CatalogRecent(_HistoryStore());
      final scope = CatalogRecentSession(bridge.session, recent);
      final keys = _KeyPort();
      final features = createToolsFeatures(
        recent: recent,
        onShown: () => unawaited(scope.resolve()),
        createKeyBindings: () => keys,
      );
      final tools = features.singleWhere((f) => f.id == 'tools');
      final shortcut = features.singleWhere((f) => f.id == 'keyBindings');
      await t.pumpWidget(
        terminalApp(Builder(builder: shortcut.buildDestination)),
      );
      await settle(t);
      expect(keys.reads, 1);
      expect(bridge.accounts, isEmpty);
      await t.pumpWidget(terminalApp(Builder(builder: tools.buildDestination)));
      await settle(t);
      final cache = t.widget<ToolsPage>(find.byType(ToolsPage)).cache!;
      final readAt = cache.keysReadAt;
      expect(cache.keys, same(_keys));
      expect(readAt, isNotNull);
      expect(recent.scopeRevision, 0);
      expect(
        find.descendant(
          of: find.byKey(const Key('tool-key-bindings')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      cache.accept('missions.detail', {}, missionSample, false);
      cache.accept('blueprints.page', {}, {
        'total': 1,
        'rows': [blueprintSample],
      }, false);
      // The in-memory bridge answers account.getCurrent on the test clock:
      // pump until the view (which resolves the account first) completes.
      var viewed = false;
      unawaited(
        recent
            .view(CatalogKind.missions, missionSample)
            .then((_) => recent.idle)
            .whenComplete(() => viewed = true),
      );
      for (var i = 0; i < 40 && !viewed; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(viewed, isTrue);
      bridge.session.advanceGeneration(2);
      expect(cache.missionRows, isEmpty);
      expect(cache.blueprintTotal, isNull);
      expect(recent.entries, isEmpty);
      expect(cache.keys, same(_keys));
      expect(cache.keysReadAt, readAt);
      await disposePage(t);
      tools.onDispose?.call();
      scope.dispose();
      await t.runAsync(bridge.close);
    },
  );

  for (final kind in CatalogKind.values) {
    for (final fail in [false, true]) {
      testWidgets('${kind.name} loads while account is held; failure=$fail', (
        t,
      ) async {
        size(t, 1440);
        final bridge = _AccountHarness()..hold = true;
        final store = _HistoryStore();
        // Observe this instance's reads and writes, including a held detail view.
        final history = CatalogRecent(store);
        final scope = CatalogRecentSession(bridge.session, history);
        final port = SampleCatalogPort();
        final features = createToolsFeatures(
          recent: history,
          onShown: () => unawaited(scope.resolve()),
          createCatalog: () => port,
        );
        final page = features.singleWhere((f) => f.id == kind.name);
        await t.pumpWidget(
          terminalApp(Builder(builder: page.buildDestination)),
        );
        await settle(t);
        final id = kind == CatalogKind.missions ? missionGuid : 73;
        expect(find.byKey(Key('catalog-row-$id')), findsOneWidget);
        expect(
          port.calls.map((r) => r.operation),
          contains('${kind.name}.page'),
        );
        expect(bridge.accounts, hasLength(1));
        expect(store.reads, isEmpty);
        await tap(t, Key('catalog-row-$id'));
        expect(history.entries, isEmpty);
        expect(store.writes, isEmpty);
        await _drive(t, bridge.reply(bridge.accounts.single, fail: fail));
        await settle(t);
        await _drive(t, history.idle);
        expect(history.entries, fail ? isEmpty : hasLength(1));
        expect(store.writes, fail ? isEmpty : hasLength(1));
        expect(find.byKey(const Key('catalog-error')), findsNothing);
        // A first owner binding must not retire the already loaded catalogue.
        await tap(t, const Key('catalog-refresh'));
        expect(find.byKey(Key('catalog-row-$id')), findsOneWidget);
        await disposePage(t);
        features.singleWhere((f) => f.id == 'tools').onDispose?.call();
        scope.dispose();
        await t.runAsync(bridge.close);
      });
    }
  }

  testWidgets('compact mission row retains its system with type and faction', (
    t,
  ) async {
    size(t, 320);
    final features = createToolsFeatures(
      createCatalog: () => SampleCatalogPort(),
    );
    final page = features.singleWhere((f) => f.id == 'missions');
    await t.pumpWidget(terminalApp(Builder(builder: page.buildDestination)));
    await settle(t);
    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-row-$missionGuid')),
        matching: find.text('运输 · 示意阵营 · Stanton'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await disposePage(t);
    features.singleWhere((f) => f.id == 'tools').onDispose?.call();
  });

  test(
    'key reads in flight survive account retirement, but not cache disposal',
    () async {
      final source = _KeyPort()..held = Completer<KeyBindingsSnapshot>();
      final cache = ToolsSnapshotCache();
      final port = ObservedKeyBindingsPort(source, cache);
      final pending = port.read('LIVE', 'en');
      cache.retire();
      source.held!.complete(_keys);
      await pending;
      expect(cache.keys, same(_keys));
      final firstReadAt = cache.keysReadAt;
      cache.retire();
      expect(cache.keysReadAt, firstReadAt);
      source.held = Completer<KeyBindingsSnapshot>();
      final disposedRead = port.read('LIVE', 'en');
      cache.dispose();
      source.held!.complete(
        const KeyBindingsSnapshot(state: 'missing', channel: 'LIVE'),
      );
      await disposedRead;
      expect(cache.keys, same(_keys));
    },
  );

  test(
    'a view waiting for preparation cannot cross an A-B-A owner change',
    () async {
      final recent = CatalogRecent(_HistoryStore());
      await recent.switchOwner('account-A');
      final held = Completer<void>();
      recent.prepare = () => held.future;
      final view = recent.view(CatalogKind.missions, missionSample);
      await recent.switchOwner('account-B');
      await recent.switchOwner('account-A');
      held.complete();
      await view;
      expect(recent.entries, isEmpty);
      recent.dispose();
    },
  );

  test(
    'a pending first-owner view cannot enter a later session generation',
    () async {
      final bridge = _AccountHarness()..hold = true;
      final store = _HistoryStore();
      final history = CatalogRecent(store);
      final scope = CatalogRecentSession(bridge.session, history);
      final view = history.view(CatalogKind.missions, missionSample);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.accounts.single.sessionGeneration, 1);
      bridge.session.advanceGeneration(2);
      final resolved = scope.resolve();
      await Future<void>.delayed(Duration.zero);
      final current = bridge.accounts.singleWhere(
        (r) => r.sessionGeneration == 2,
      );
      await bridge.reply(current);
      await resolved;
      await view;
      expect(history.entries, isEmpty);
      expect(store.writes, isEmpty);
      scope.dispose();
      await bridge.close();
    },
  );

  test('account changes clear mission summaries and recent entries', () async {
    final bridge = _AccountHarness(), store = _HistoryStore();
    final recent = CatalogRecent(store);
    final scope = CatalogRecentSession(bridge.session, recent);
    final mode = Mode();
    bridge.session.acceptHostCapabilities(['missionRecords.read']);
    final port = BridgeMissionRecordsPort(bridge.session, mode);
    final records = MissionRecordsController(port);
    await scope.resolve();
    await records.load();
    await recent.view(CatalogKind.missions, missionSample);
    await recent.idle;
    expect(records.groups.single.count, 3);
    expect(recent.entries, hasLength(1));
    bridge.hold = true;
    bridge.subject = 'account-B';
    bridge.session.advanceGeneration(2);
    expect(records.groups, isEmpty);
    expect(recent.entries, isEmpty);
    expect(recent.lastImportAt, isNull);
    // Release the new account lookup so the controller has no pending work.
    await Future<void>.delayed(Duration.zero);
    for (final request in bridge.accounts.where(
      (r) => r.sessionGeneration == 2,
    )) {
      await bridge.reply(request);
    }
    await Future<void>.delayed(Duration.zero);
    records.dispose();
    port.dispose();
    mode.dispose();
    scope.dispose();
    await bridge.close();
  });
}
