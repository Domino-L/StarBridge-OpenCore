import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/diagnostics/loading_diagnostics.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'deferred fleet phases retain distinct fixed operation labels',
    () async {
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
      metrics.observe(
        'officialFleet.getIdentity',
        Future<void>.value(),
        transport: true,
      );
      metrics.observe(
        'officialFleet.getPublicProfile',
        Future<void>.value(),
        transport: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        rows.map((row) => row['operation']),
        containsAll(['fleet.identity.read', 'fleet.profile.read']),
      );
    },
  );
  test(
    'delayed frame evidence uses the painted visit, not the callback route',
    () {
      var time = 10;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      metrics.route('/hangar');
      time = 20;
      metrics.contentPainted('/hangar', LoadingContentStatus.data, items: 3);
      expect(rows.where((r) => r['kind'] == 'contentRaster'), isEmpty);
      time = 1000;
      metrics.route('/profile');
      metrics.frame(
        buildUs: 30,
        rasterUs: 10,
        totalUs: 50,
        vsyncUs: 5,
        buildStartUs: 15,
        buildFinishUs: 45,
        rasterFinishUs: 55,
      );
      final frame = rows.singleWhere((r) => r['kind'] == 'frame');
      final content = rows.singleWhere((r) => r['kind'] == 'contentRaster');
      expect(frame['route'], '/hangar');
      expect(content['route'], '/hangar');
      expect(content['visit'], 1);
      expect(content['us'], 55);
      expect(content['items'], 3);
      metrics.contentPainted('/hangar', LoadingContentStatus.empty, items: 0);
      expect(rows.where((r) => r['kind'] == 'contentPaint'), hasLength(1));
    },
  );
  test('missing frame evidence never becomes rendered content', () {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/hangar');
    time = 20;
    metrics.contentPainted('/hangar', LoadingContentStatus.data, items: 1);
    metrics.frame(buildUs: 1, rasterUs: 1, totalUs: 2);
    metrics.frame(
      buildUs: 1,
      rasterUs: 1,
      totalUs: 2,
      buildStartUs: 30,
      buildFinishUs: 31,
      rasterFinishUs: 32,
    );
    expect(rows.where((r) => r['kind'] == 'contentRaster'), isEmpty);
  });
  test(
    'request completion retains the foreground visit at subscription',
    () async {
      var time = 10;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      metrics.route('/hangar');
      final done = Completer<Object?>();
      metrics.observe('hangarReader.inventory', done.future, transport: true);
      time = 30;
      metrics.route('/profile');
      done.complete();
      await Future<void>.delayed(Duration.zero);
      final completion = rows.singleWhere((r) => r['kind'] == 'transport');
      expect(completion['route'], '/hangar');
      expect(completion['visit'], 1);
    },
  );
  test('ordinary startup creates no recorder, sink or timer', () {
    LoadingDiagnostics.run(const {}, () {});
    LoadingDiagnostics.stage('connecting');
    expect(LoadingDiagnostics.enabled, isFalse);
    expect(LoadingMetrics.current, isNull);
  });
  test('tour flag without a local trace cannot bind automatic navigation', () {
    var navigations = 0;
    LoadingDiagnostics.run(const {'STARBRIDGE_LOADING_TOUR': 'primary-v1'}, () {
      expect(
        LoadingDiagnostics.bindTour((_) async {
          navigations++;
          throw StateError('must not navigate');
        }),
        isNull,
      );
    });
    expect(navigations, 0);
    expect(LoadingDiagnostics.enabled, isFalse);
  });
  test(
    'account observations contain only fixed facts and preserve readiness',
    () {
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 5, write: rows.add);
      metrics.accountState(
        generation: 2,
        busy: true,
        refreshing: true,
        resolved: true,
        failed: false,
        cached: false,
        scm: true,
        legacy: false,
      );
      expect(rows.single['kind'], 'accountState');
      expect(rows.single['resolved'], isTrue);
      expect(rows.single['busy'], isTrue);
      expect(rows.single['scm'], isTrue);
      expect(rows.where((r) => r['kind'] == 'startup'), isEmpty);
      expect(
        rows.single.values.every(
          (value) => value is num || value is bool || value == 'accountState',
        ),
        isTrue,
      );
    },
  );
  test(
    'only fixed labels enter the trace; private strings and errors are absent',
    () async {
      var time = 0;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      metrics.stage('connecting');
      metrics.stage('private-stage');
      metrics.route('/hangar');
      metrics.route('/hangar?account=private-value');
      final failure = Completer<Object?>();
      metrics.observe('private-secret', failure.future, transport: true);
      time = 125;
      failure.completeError(StateError('private-response-token'));
      await Future<void>.delayed(Duration.zero);
      expect(rows.map((r) => r['kind']), [
        'startup',
        'route',
        'transportStart',
        'transport',
      ]);
      expect(rows.last['operation'], 'other');
      expect(rows.last['durationUs'], 125);
      expect(rows.last['outcome'], 'error');
      expect(rows.toString(), isNot(contains('private')));
    },
  );
  test('bounded recorder stops, including when the output fails', () {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(
      nowUs: () => 0,
      write: rows.add,
      maxEvents: 2,
    );
    for (var i = 0; i < 100; i++) {
      metrics.mark(LoadingMilestone.dartEntry);
    }
    expect(rows, hasLength(2));
    expect(metrics.stopped, isTrue);
    final broken = LoadingMetrics(
      nowUs: () => 0,
      write: (_) => throw StateError('disk'),
    );
    expect(() => broken.mark(LoadingMilestone.dartEntry), returnsNormally);
    expect(broken.stopped, isTrue);
  });
  test(
    'real session records consumers separately from the shared transport',
    () async {
      var time = 0;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final subscription = pair.host.incoming.listen((request) {
        time = 200;
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 1,
              payload: const {'schemaVersion': 1},
              status: 'ok',
            ),
          ),
        );
      });
      await runZoned(() async {
        final first = session.request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
        );
        final second = session.request(
          'account.getCurrent',
          payload: const {'schemaVersion': 1},
          timeout: const Duration(seconds: 60),
        );
        await Future.wait([first, second]);
      }, zoneValues: {loadingMetricsZoneKey: metrics});
      await Future<void>.delayed(Duration.zero);
      expect(rows.where((r) => r['kind'] == 'transport'), hasLength(1));
      expect(rows.where((r) => r['kind'] == 'consumer'), hasLength(2));
      expect(
        rows.where((r) => r['kind'] == 'transport').single['durationUs'],
        200,
      );
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    },
  );
}
