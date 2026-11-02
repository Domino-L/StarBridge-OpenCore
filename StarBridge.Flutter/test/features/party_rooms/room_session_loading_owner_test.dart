import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/room_session_listener.dart';
import 'package:starbridge_flutter/features/party_rooms/bridge_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'bridge_party_rooms_test.dart' show emptyDirectory;

class _Fixture {
  _Fixture({this.holdAccount = false}) {
    scoped(() {
      final pair = InMemoryBridgeConnection.createPair();
      connection = pair.host;
      session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 4,
      )..acceptHostCapabilities(['partyRooms.read']);
      adapter = BridgePartyRoomsAdapter(session);
      module = PartyRoomsModule(adapter);
      subscription = connection.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'account.getCurrent' && !holdAccount) {
          unawaited(reply(request));
        }
      });
    });
    metrics.route('/profile');
  }

  final bool holdAccount;
  int tick = 0;
  final rows = <Map<String, Object>>[];
  late final metrics = LoadingMetrics(nowUs: () => tick++, write: rows.add);
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgePartyRoomsAdapter adapter;
  late final PartyRoomsModule module;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  List<BridgeEnvelope> get directories => requests
      .where((request) => request.name == 'partyRooms.getDirectory')
      .toList();

  T scoped<T>(T Function() work) =>
      runZoned(work, zoneValues: {loadingMetricsZoneKey: metrics});

  Future<void> reply(BridgeEnvelope request, {bool fail = false}) =>
      connection.send(BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: const BridgeAccountContext(
          environment: 'test',
          authority: 'scm-test',
          subject: 'test-subject',
        ),
        status: fail ? 'error' : 'ok',
        error: fail
            ? const BridgeErrorBody(
                code: 'party_rooms.command_unavailable',
                message: 'fixture failure',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? const {'schemaVersion': 1, 'state': 'signedIn'}
            : emptyDirectory,
      ));

  Future<void> mount(WidgetTester tester) => scoped(() => tester.pumpWidget(
        RoomSessionListener(module: module, child: const SizedBox()),
      ));

  void expectRecordedRead(int visit) {
    expect(directories, isNotEmpty, reason: 'Real bridge directory dispatched');
    expect(rows.where((row) => row['kind'] == 'transportStart' &&
        row['operation'] == 'rooms.read'), isNotEmpty,
        reason: 'A missing metrics zone must not fake a passive result');
    expect(metrics.pendingTransportsFor(visit), greaterThan(0));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    module.dispose();
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await connection.close();
    metrics.stop();
  }
}

void main() {
  testWidgets('mounted shell session read does not block unrelated profile', (t) async {
    final f = _Fixture();
    addTearDown(() => f.close(t));
    await f.mount(t);
    await t.pump();
    f.expectRecordedRead(1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    await f.reply(f.directories.single);
    await t.pump();
    expect(f.module.state, RoomReadState.ready);
    expect(f.metrics.pendingTransportsFor(1), 0);
  });

  testWidgets('session eight second renewal stays passive after navigation', (t) async {
    final f = _Fixture();
    addTearDown(() => f.close(t));
    await f.mount(t);
    await t.pump();
    await f.reply(f.directories.single);
    await t.pump();
    f.metrics.route('/settings/privacy');
    await f.scoped(() => t.pump(const Duration(seconds: 8)));
    expect(f.directories, hasLength(2));
    f.expectRecordedRead(2);
    expect(f.metrics.pendingPageReadsFor(2), 0);
    await f.reply(f.directories.last);
    await t.pump();
    expect(f.metrics.pendingTransportsFor(2), 0);
  });

  testWidgets('page enter remains a real page read without a shell session', (t) async {
    final f = _Fixture();
    addTearDown(() => f.close(t));
    f.metrics.route('/rooms');
    f.scoped(f.module.enter);
    await t.pump();
    f.expectRecordedRead(2);
    expect(f.metrics.pendingPageReadsFor(2), greaterThan(0));
    await f.reply(f.directories.single);
    await t.pump();
    expect(f.module.state, RoomReadState.ready);
    expect(f.metrics.pendingPageReadsFor(2), 0);
    f.module.leave();
  });

  testWidgets('explicit manual refresh still blocks on its own bridge read', (t) async {
    final f = _Fixture();
    addTearDown(() => f.close(t));
    final read = f.scoped(() => f.module.refresh(foreground: true));
    await t.pump();
    f.expectRecordedRead(1);
    expect(f.module.manualRefreshing, true);
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    await f.reply(f.directories.single);
    await read;
    expect(f.module.manualRefreshing, false);
    expect(f.metrics.pendingPageReadsFor(1), 0);
  });

  testWidgets('foreground account borrower beside session remains blocking', (t) async {
    final f = _Fixture(holdAccount: true);
    addTearDown(() => f.close(t));
    await f.mount(t);
    await t.pump();
    final read = f.scoped(() => f.metrics.foreground(f.adapter.read));
    await t.pump();
    final accounts = f.requests.where((r) => r.name == 'account.getCurrent');
    expect(accounts, hasLength(1), reason: 'Only in-flight account sharing');
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    await f.reply(accounts.single);
    await t.pump();
    expect(f.directories, hasLength(2));
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    for (final directory in f.directories) {
      await f.reply(directory);
    }
    await t.pump();
    expect((await read).state, RoomReadState.ready);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 0);
  });

  testWidgets('passive directory failure keeps physical error evidence', (t) async {
    final f = _Fixture();
    addTearDown(() => f.close(t));
    await f.mount(t);
    await t.pump();
    f.expectRecordedRead(1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    await f.reply(f.directories.single, fail: true);
    await t.pump();
    expect(f.module.state, RoomReadState.unavailable);
    expect(f.rows.where((row) => row['kind'] == 'transport' &&
        row['operation'] == 'rooms.read' && row['outcome'] == 'error'),
        hasLength(1));
    expect(f.metrics.pendingTransportsFor(1), 0);
  });
}
