import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/hangar_loading_metrics.dart';
import 'package:starbridge_flutter/features/hangar/hangar_read_diagnostics.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'bridge_local_hangar_test.dart' show LocalConnection;

void main() {
  for (final origin in HangarReadOrigin.values) {
    test('real local inventory identifies ${origin.name} bind and projection', () async {
      final connection = LocalConnection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
      final port = BridgeLocalHangar(session, readOrigin: origin);
      await runZoned(
        () => port.read(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      // Observation completion does not extend the business Future's lifetime.
      await Future<void>.delayed(Duration.zero);
      expect(port.readScope?.generation, 7);
      expect(connection.requests.map((r) => r.name), [
        'account.getCurrent',
        'hangarReader.inventory',
        'hangarReader.inventory',
      ]);
      final phases = events
          .where((e) => e['kind'] == 'consumer')
          .map((e) => e['operation']);
      expect(
        phases,
        containsAll([
          'hangar.${origin.name}.bind',
          'hangar.${origin.name}.inventory',
          'hangar.${origin.name}.inventoryProjection',
        ]),
      );
    });
  }

  test(
    'legacy fallback keeps its original requests and separate phases',
    () async {
      final connection = LocalConnection()
        ..legacy = true
        ..emptyRevision = 0;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      );
      addTearDown(session.close);
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
      await runZoned(
        () => BridgeLocalHangar(
          session,
          readOrigin: HangarReadOrigin.profile,
        ).read(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.requests.map((r) => r.name), [
        'account.getCurrent',
        'hangarReader.inventory',
        'personalProfile.getSelf',
      ]);
      expect(
        events.where((e) => e['kind'] == 'consumer').map((e) => e['operation']),
        containsAll([
          'hangar.profile.legacyRead',
          'hangar.profile.legacyProjection',
        ]),
      );
    },
  );

  for (final stopped in [false, true]) {
    test('no active recorder preserves the original Future ($stopped)', () {
      final metrics = LoadingMetrics(
        nowUs: () => 10,
        write: (_) => fail('must not record'),
      );
      metrics.stop();
      final original = Future.value(7);
      var calls = 0;
      final result = runZoned(
        () => observeHangarRead(
          HangarReadOrigin.feature,
          HangarReadStage.bind,
          () {
            calls++;
            return original;
          },
        ),
        zoneValues: stopped ? {loadingMetricsZoneKey: metrics} : {},
      );
      expect(identical(result, original), isTrue);
      expect(calls, 1);
    });
  }

  test(
    'phase clock includes synchronous work and retains its starting visit',
    () async {
      var now = 10;
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => now, write: events.add);
      metrics.route('/hangar');
      final result = await runZoned(
        () => observeHangarRead(
          HangarReadOrigin.feature,
          HangarReadStage.inventoryProjection,
          () {
            now = 30;
            metrics.route('/profile');
            return Future.value(7);
          },
        ),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await Future<void>.delayed(Duration.zero);
      expect(result, 7);
      final event = events.singleWhere((e) => e['kind'] == 'consumer');
      expect(event['durationUs'], 20);
      expect(event['route'], '/hangar');
      expect(event['visit'], 1);
      expect(event['outcome'], 'ok');
    },
  );

  for (final synchronous in [true, false]) {
    test('phase observation preserves error identity ($synchronous)', () async {
      final failure = StateError('private-account-token-path');
      final events = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: events.add);
      await runZoned(() async {
        if (synchronous) {
          expect(
            () => observeHangarRead<int>(
              HangarReadOrigin.profile,
              HangarReadStage.bind,
              () => throw failure,
            ),
            throwsA(same(failure)),
          );
        } else {
          await expectLater(
            observeHangarRead<int>(
              HangarReadOrigin.profile,
              HangarReadStage.bind,
              () async => throw failure,
            ),
            throwsA(same(failure)),
          );
        }
      }, zoneValues: {loadingMetricsZoneKey: metrics});
      await Future<void>.delayed(Duration.zero);
      expect(
        events.singleWhere((e) => e['kind'] == 'consumer')['outcome'],
        'error',
      );
      expect(events.toString(), isNot(contains('private-account-token-path')));
    });
  }

  test('failed diagnostic output cannot replace the business result', () async {
    final metrics = LoadingMetrics(
      nowUs: () => 10,
      write: (_) => throw StateError('sink failed'),
    );
    final result = await runZoned(
      () => observeHangarRead(
        HangarReadOrigin.menuProfile,
        HangarReadStage.inventory,
        () async => 7,
      ),
      zoneValues: {loadingMetricsZoneKey: metrics},
    );
    expect(result, 7);
    expect(metrics.stopped, isTrue);
  });
}
