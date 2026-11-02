import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_activity.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets(
    'runtime hint heartbeat is silent and existing bounded reconciliation closes the read-wait gap',
    (tester) async {
      final h = RuntimeHintHarness();
      addTearDown(h.close);
      var hints = 0;
      h.activity.configureHintStrategy(h.strategy(1));
      final subscription = h.activity.changes.stream.listen((_) => hints++);
      addTearDown(subscription.cancel);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.waits, hasLength(1));
      expect(
        h.waits.single.payload.keys,
        unorderedEquals([
          'schemaVersion',
          'sourceRef',
          'search',
          'filter',
          'pageNumber',
          'pageSize',
        ]),
      );
      await h.reply(h.waits.last, changed: false);
      await tester.pump();
      expect(hints, 0);
      await tester.pump(const Duration(milliseconds: 150));
      h.now = h.now.add(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 8));
      await h.reply(h.waits.last, changed: false);
      await tester.pump();
      expect(hints, 0);
      await tester.pump(const Duration(milliseconds: 150));
      h.now = h.now.add(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 8));
      await h.reply(h.waits.last, changed: false);
      await tester.pump();
      expect(hints, 1);
      await tester.pump(const Duration(milliseconds: 150));
      await h.reply(h.waits.last, changed: true);
      await tester.pump();
      expect(hints, 2);
      await tester.runAsync(subscription.cancel);
    },
  );
  testWidgets(
    'query replacement cancels the old wait and ignores its late hint',
    (tester) async {
      final h = RuntimeHintHarness();
      addTearDown(h.close);
      var hints = 0;
      h.activity.configureHintStrategy(h.strategy(1));
      final subscription = h.activity.changes.stream.listen((_) => hints++);
      addTearDown(subscription.cancel);
      await tester.pump(const Duration(milliseconds: 1));
      final old = h.waits.single;
      h.activity.configureHintStrategy(h.strategy(2));
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.waits.last.payload['pageNumber'], 2);
      await h.reply(old, changed: true);
      await tester.pump();
      expect(hints, 0);
      await h.reply(h.waits.last, changed: true);
      await tester.pump();
      expect(hints, 1);
      expect(h.cancels, greaterThanOrEqualTo(1));
      await tester.runAsync(subscription.cancel);
    },
  );
  testWidgets(
    'new Ready capability reuses the worker without permanent unsupported construction',
    (tester) async {
      final h = RuntimeHintHarness(capable: false);
      addTearDown(h.close);
      h.activity.configureHintStrategy(h.strategy(1));
      final subscription = h.activity.changes.stream.listen((_) {});
      addTearDown(subscription.cancel);
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.waits, isEmpty);
      h.session.acceptHostCapabilities(['officialFleet.runtimeActivity']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.waits, hasLength(1));
      await tester.runAsync(subscription.cancel);
    },
  );
}

final class RuntimeHintHarness {
  RuntimeHintHarness({bool capable = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(
      capable ? ['officialFleet.runtimeActivity'] : [],
    );
    activity = CommunityActivity(session, now: () => now);
    host = pair.host.incoming.listen((r) {
      if (r.name == 'account.getCurrent') {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              correlationId: r.correlationId,
              sessionGeneration: r.sessionGeneration,
              accountContext: owner,
              status: 'ok',
              payload: const {'schemaVersion': 1, 'state': 'signedIn'},
            ),
          ),
        );
      } else if (r.name == 'officialFleet.waitRuntimeActivity') {
        waits.add(r);
      } else if (r.name == 'bridge.cancel') {
        cancels++;
      }
    });
  }
  static const owner = BridgeAccountContext(
    environment: 'fixture',
    authority: 'scm',
    subject: 'synthetic',
  );
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final CommunityActivity activity;
  late final StreamSubscription<BridgeEnvelope> host;
  final waits = <BridgeEnvelope>[];
  int cancels = 0;
  DateTime now = DateTime.utc(2026);
  CommunityActivityHintStrategy strategy(int page) =>
      CommunityActivityHintStrategy(
        sourceRef: 'officialFleet:7',
        command: 'officialFleet.waitRuntimeActivity',
        capability: 'officialFleet.runtimeActivity',
        payload: {
          'schemaVersion': 2,
          'sourceRef': 'officialFleet:7',
          'search': '',
          'filter': 'all',
          'pageNumber': page,
          'pageSize': 50,
        },
      );
  Future<void> reply(BridgeEnvelope r, {required bool changed}) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          accountContext: owner,
          status: 'ok',
          payload: {
            'schemaVersion': 2,
            'sourceRef': 'officialFleet:7',
            'changed': changed,
          },
        ),
      );
  Future<void> close() async {
    await activity.close();
    await host.cancel();
    await session.close();
    await pair.host.close();
  }
}
