import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_read_scope.dart';

void main() {
  test('automatic callback restores its recorder and preserves another recorder scope', () async {
    final aRows = <Map<String, Object>>[], bRows = <Map<String, Object>>[];
    final a = LoadingMetrics(nowUs: () => 1, write: aRows.add);
    final b = LoadingMetrics(nowUs: () => 1, write: bRows.add);
    a.route('/profile');
    b.route('/hangar');
    final aHeld = Completer<Object?>(), bHeld = Completer<Object?>();
    final callback = runZoned(() => backgroundLoadingCallback(() {
      expect(LoadingMetrics.current, same(a));
      LoadingMetrics.current!.observe('communities.read', aHeld.future, transport: true);
    }), zoneValues: {loadingMetricsZoneKey: a});
    runZoned(() => b.foreground(() {
      b.observe('friends.read', bHeld.future, transport: false);
      callback();
      expect(LoadingMetrics.current, same(b));
      b.observe('friends.read', bHeld.future, transport: false);
    }), zoneValues: {loadingMetricsZoneKey: b});
    expect(a.pendingTransportsFor(1), 1);
    expect(a.pendingPageReadsFor(1), 0);
    expect(b.pendingPageReadsFor(1), 2);
    expect(aRows.singleWhere((r) => r['kind'] == 'transportStart')['activity'], 'background');
    expect(bRows.where((r) => r['kind'] == 'consumerStart').every((r) => r['activity'] == 'foreground'), isTrue);
    aHeld.complete(); bHeld.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('captured automatic callback still permits an explicit foreground borrower', () async {
    final metrics = LoadingMetrics(nowUs: () => 1, write: (_) {});
    metrics.route('/profile');
    final held = Completer<Object?>();
    final callback = runZoned(() => backgroundLoadingCallback(() {
      metrics.foreground(() => metrics.observe('communities.read', held.future, transport: false));
    }), zoneValues: {loadingMetricsZoneKey: metrics});
    callback();
    expect(metrics.pendingPageReadsFor(1), 1);
    held.complete();
    await Future<void>.delayed(Duration.zero);
    expect(metrics.pendingPageReadsFor(1), 0);
  });

  test('disabled recording retains callback identity and stopped recording cannot stop work', () async {
    var calls = 0;
    void plain() { calls++; }
    expect(LoadingMetrics.current, isNull);
    expect(backgroundLoadingCallback(plain), same(plain));
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    final held = Completer<Object?>();
    final callback = runZoned(() => backgroundLoadingCallback(() {
      calls++;
      LoadingMetrics.current?.observe('communities.read', held.future, transport: true);
    }), zoneValues: {loadingMetricsZoneKey: metrics});
    metrics.stop();
    callback();
    expect(calls, 1);
    expect(rows, isEmpty);
    expect(held.isCompleted, isFalse);
    held.complete();
    await Future<void>.delayed(Duration.zero);
  });

  for (final reason in LoadingReadRetirement.values) {
    test('retiring ${reason.name} leaves actual transport and peer pending', () async {
      var time = 0;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add);
      final held = Completer<Object?>();
      metrics.route('/messages');
      metrics.background(() => metrics.observe(
        'directMessages.read', held.future, transport: true,
      ));
      final first = metrics.foreground(() => metrics.observe(
        'directMessages.read', held.future, transport: false,
      ));
      metrics.foreground(() => metrics.observe(
        'directMessages.read', held.future, transport: false,
      ));
      expect(metrics.pendingTransportsFor(1), 1);
      expect(metrics.pendingPageReadsFor(1), 2);
      first(reason);
      first(reason);
      expect(metrics.pendingPageReadsFor(1), 1);
      expect(metrics.pendingTransportsFor(1), 1);
      expect(held.isCompleted, isFalse);
      expect(rows.where((r) => r['kind'] == 'readLeaseRetired'), hasLength(1));
      final retired = rows.singleWhere((r) => r['kind'] == 'readLeaseRetired');
      expect(retired['reason'], reason.name);
      expect(retired['activity'], 'foreground');
      expect(retired.containsKey('outcome'), isFalse);
      expect(rows.where((r) => r['kind'] == 'transport'), isEmpty);
      held.complete();
      await Future<void>.delayed(Duration.zero);
      expect(metrics.pendingPageReadsFor(1), 0);
      expect(metrics.pendingTransportsFor(1), 0);
      expect(rows.where((r) => r['kind'] == 'transport'), hasLength(1));
      expect(rows.where((r) => r['kind'] == 'consumer'), hasLength(2));
      first(reason);
      expect(rows.where((r) => r['kind'] == 'readLeaseRetired'), hasLength(1));
    });
  }

  test('retired consumer still records its real error without error payloads', () async {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    metrics.route('/messages');
    final held = Completer<Object?>();
    final outcome = held.future.then((_) => 'ok', onError: (Object _) => 'error');
    final retire = metrics.observe('directMessages.read', held.future, transport: false);
    retire(LoadingReadRetirement.cancelled);
    held.completeError(StateError('private-sentinel'));
    expect(await outcome, 'error');
    await Future<void>.delayed(Duration.zero);
    expect(rows.singleWhere((r) => r['kind'] == 'consumer')['outcome'], 'error');
    expect(rows.toString(), isNot(contains('private-sentinel')));
    expect(metrics.pendingPageReadsFor(1), 0);
  });

  test('retirement remains attributed to subscription visit after navigation', () async {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    metrics.route('/messages');
    final held = Completer<Object?>();
    final retire = metrics.observe('directMessages.read', held.future, transport: false);
    metrics.route('/profile');
    retire(LoadingReadRetirement.disposed);
    final retired = rows.singleWhere((r) => r['kind'] == 'readLeaseRetired');
    expect(retired['visit'], 1);
    expect(retired['route'], '/messages');
    expect(retired['activity'], 'unclassified');
    expect(metrics.pendingPageReadsFor(1), 0);
    expect(metrics.pendingPageReadsFor(2), 0);
    held.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('passive and routeless requests cannot invent retirement evidence', () async {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    final held = Completer<Object?>();
    final routeless = metrics.observe('directMessages.read', held.future, transport: true);
    metrics.route('/profile');
    final passive = metrics.background(() => metrics.observe(
      'directMessages.read', held.future, transport: true,
    ));
    routeless(LoadingReadRetirement.cancelled);
    passive(LoadingReadRetirement.disposed);
    expect(rows.where((r) => r['kind'] == 'readLeaseRetired'), isEmpty);
    expect(metrics.pendingTransportsFor(1), 1);
    expect(metrics.pendingPageReadsFor(1), 0);
    held.complete();
    await Future<void>.delayed(Duration.zero);
    expect(rows.where((r) => r['kind'] == 'transport'), hasLength(2));
  });

  test('stopped recorder cannot change the business Future or add events', () async {
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => 1, write: rows.add);
    metrics.route('/messages');
    final held = Completer<Object?>();
    final retire = metrics.observe('directMessages.read', held.future, transport: true);
    metrics.stop();
    final count = rows.length;
    retire(LoadingReadRetirement.disposed);
    final afterStop = metrics.observe('directMessages.read', held.future, transport: false);
    afterStop(LoadingReadRetirement.cancelled);
    expect(held.isCompleted, isFalse);
    held.complete('actual-result');
    expect(await held.future, 'actual-result');
    await Future<void>.delayed(Duration.zero);
    expect(rows, hasLength(count));
    expect(metrics.pendingTransportsFor(1), 0);
    expect(metrics.pendingPageReadsFor(1), 0);
  });
}
