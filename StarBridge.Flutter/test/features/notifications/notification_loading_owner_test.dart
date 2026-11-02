import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/social_activity.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import '../../_support/loading_ownership_original/reference_notification_inbox_controller.dart' as original;
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

class _InboxMeter {
  _InboxMeter() {
    session.acceptHostCapabilities(['notificationInbox.read', 'notificationInbox.markRead']);
    host = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') {
        accounts++;
        unawaited(answer(request, const {'schemaVersion': 1, 'state': 'legacySignedIn'}));
      } else if (request.name == 'notificationInbox.read') {
        reads.add(request);
      } else if (request.name == 'notificationInbox.markRead') {
        writes++;
        if (acceptWrite) marked = true;
        unawaited(answer(request, {'schemaVersion': 1, 'confirmed': acceptWrite}));
      }
    });
    controller = scope(() => const bool.fromEnvironment('LOADING_INBOX_ORIGINAL')
      ? original.NotificationInboxController(session)
      : NotificationInboxController(session));
    metrics.route('/profile');
  }
  static const owner = BridgeAccountContext(
    environment: 'fixture', authority: 'starbridge-relay-test', subject: 'fixture',
  );
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
  final rows = <Map<String, Object>>[];
  int time = 0, accounts = 0, writes = 0;
  bool acceptWrite = true, marked = false;
  BridgeAccountContext currentOwner = owner;
  bool _closed = false;
  final reads = <BridgeEnvelope>[];
  late final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add);
  late final StreamSubscription<BridgeEnvelope> host;
  late final dynamic controller;
  T scope<T>(T Function() action) => runZoned(action, zoneValues: {loadingMetricsZoneKey: metrics});
  void start() => scope<void>(() => controller.start());
  Future<bool> manual({bool quiet = false, bool explicit = false}) => scope(() {
    Future<bool> read() => controller.refresh(quiet: quiet) as Future<bool>;
    return explicit ? metrics.foreground(read) : read();
  });
  Future<bool> markRead() => scope(() => metrics.foreground(
    () => controller.markRead(controller.items) as Future<bool>,
  ));
  Future<void> answer(BridgeEnvelope request, Map<String, Object?> payload) => pair.host.send(BridgeEnvelope(
    protocolVersion: 1, messageType: 'response', name: request.name,
    correlationId: request.correlationId, sessionGeneration: request.sessionGeneration,
    accountContext: currentOwner, status: 'ok', payload: payload,
  ));
  Future<void> replyRead(int index) => answer(reads[index], {
    'schemaVersion': 1, 'unreadCount': marked ? 0 : 1,
    'items': [{
      'reference': 'a' * 32, 'category': 'system', 'priority': 'normal',
      'title': 'Fixture', 'body': 'Fixture', 'createdAt': '2026-01-01T00:00:00Z',
      'read': marked, 'isAvailable': true, 'actionTarget': '', 'actionLabel': '',
    }],
  });
  Future<void> changeAccount({int generation = 1}) => pair.host.send(BridgeEnvelope(
    protocolVersion: 1, messageType: 'event', name: 'account.changed',
    sessionGeneration: generation, sequence: 1, payload: const {'schemaVersion': 1},
  ));
  Future<void> failRead(int index, {required bool retryable}) => pair.host.send(BridgeEnvelope(
    protocolVersion: 1, messageType: 'response', name: reads[index].name,
    correlationId: reads[index].correlationId, sessionGeneration: reads[index].sessionGeneration,
    accountContext: currentOwner, status: 'error', payload: const {},
    error: BridgeErrorBody(code: retryable ? 'fixture.read_unavailable' : 'fixture.read_denied', message: 'Fixture', retryable: retryable),
  ));
  Future<void> cancelRead(int index) => pair.host.send(BridgeEnvelope(
    protocolVersion: 1, messageType: 'response', name: reads[index].name,
    correlationId: reads[index].correlationId, sessionGeneration: reads[index].sessionGeneration,
    accountContext: currentOwner, status: 'cancelled', payload: const {},
  ));
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controller.dispose();
    await host.cancel();
    await session.close();
    await pair.host.close();
    metrics.stop();
  }
}

void main() {
  for (final outcome in ['retryable', 'denied', 'invalid', 'cancelled']) {
    testWidgets('$outcome read retains only recoverable same-owner display without granting success', (t) async {
      final f = _InboxMeter();
      addTearDown(f.close);
      f.start();
      await t.pump();
      await f.replyRead(0);
      await t.pump();
      final previous = f.controller.items;
      expect(f.controller.unread.value, 1);
      final refreshing = f.manual();
      await t.pump();
      if (outcome == 'cancelled') {
        await f.cancelRead(1);
      } else if (outcome == 'invalid') {
        await f.answer(f.reads[1], const {'schemaVersion': 1, 'items': 'invalid'});
      } else {
        await f.failRead(1, retryable: outcome == 'retryable');
      }
      await t.pump();
      expect(await refreshing, isFalse);
      expect(f.controller.error, 'read');
      if (outcome == 'retryable' || outcome == 'cancelled') {
        expect(f.controller.items, same(previous));
        expect(f.controller.ready, isTrue);
        expect(f.controller.unread.value, 1);
      } else {
        expect(f.controller.items, isEmpty);
        expect(f.controller.ready, isFalse);
        expect(f.controller.unread.value, 0);
      }
      expect(f.writes, 0);
      await t.runAsync(f.close);
    });
  }

  testWidgets('equivalent decoded account preserves the displayed inbox during fresh read', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    final previous = f.controller.items;
    expect(f.controller.unread.value, 1);
    final refreshing = f.manual();
    await t.pump();
    expect(f.accounts, 2);
    expect(f.reads, hasLength(2));
    expect(f.controller.items, same(previous));
    expect(f.controller.ready, isTrue);
    expect(f.controller.unread.value, 1);
    await f.replyRead(1);
    await t.pump();
    expect(await refreshing, isTrue);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  for (final changed in ['environment', 'authority', 'subject']) {
    testWidgets('changed $changed cannot retain the previous inbox projection', (t) async {
      final f = _InboxMeter();
      addTearDown(f.close);
      f.start();
      await t.pump();
      await f.replyRead(0);
      await t.pump();
      expect(f.controller.unread.value, 1);
      f.currentOwner = BridgeAccountContext(
        environment: changed == 'environment' ? 'other-fixture' : _InboxMeter.owner.environment,
        authority: changed == 'authority' ? 'starbridge-relay-other' : _InboxMeter.owner.authority,
        subject: changed == 'subject' ? 'other-fixture' : _InboxMeter.owner.subject,
      );
      final refreshing = f.manual();
      await t.pump();
      expect(f.reads, hasLength(2));
      expect(f.controller.items, isEmpty);
      expect(f.controller.ready, isFalse);
      expect(f.controller.unread.value, 0);
      await f.replyRead(1);
      await t.pump();
      expect(await refreshing, isTrue);
      expect(f.writes, 0);
      await t.runAsync(f.close);
    });
  }

  testWidgets('new account generation clears even an equivalent owner projection', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    expect(f.controller.unread.value, 1);
    await f.changeAccount(generation: 2);
    await t.pump();
    expect(f.session.activeGeneration, 2);
    expect(f.controller.items, isEmpty);
    expect(f.controller.ready, isFalse);
    expect(f.controller.unread.value, 0);
    await t.runAsync(f.close);
  });

  testWidgets('inbox startup badge read is passive, physically pending, and never marks read', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    expect(f.reads, hasLength(1));
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.controller.busy, isTrue);
    expect(f.writes, 0);
    await f.replyRead(0);
    await t.pump();
    expect(f.controller.unread.value, 1);
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  testWidgets('inbox timer is passive; quiet manual read still waits and rechecks account', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    await t.pump(const Duration(seconds: 60));
    expect(f.reads, hasLength(2));
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    await f.replyRead(1);
    await t.pump();
    final manual = f.manual(quiet: true);
    await t.pump();
    expect(f.reads, hasLength(3));
    expect(f.accounts, 3);
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    final latest = f.rows.lastWhere((r) => r['kind'] == 'transportStart');
    expect(latest['activity'], 'unclassified');
    await f.replyRead(2);
    await t.pump();
    expect(await manual, isTrue);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  testWidgets('inbox social signal classifies callback read independently of publisher zone', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    notifySocialReadChanged(f.session);
    await t.pump();
    expect(f.reads, hasLength(1));
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    await f.replyRead(0);
    await t.pump();
    expect(f.controller.unread.value, 1);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  testWidgets('queued social wake after manual read becomes passive without hiding the manual lease', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    final manual = f.manual(explicit: true);
    await t.pump();
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    notifySocialReadChanged(f.session);
    expect(f.reads, hasLength(1));
    await f.replyRead(0);
    await t.pump();
    expect(await manual, isTrue);
    expect(f.reads, hasLength(2));
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.rows.lastWhere((r) => r['kind'] == 'transportStart')['activity'], 'background');
    await f.replyRead(1);
    await t.pump();
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  testWidgets('account event clears old inbox authority and its automatic reread is passive', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    expect(f.controller.ready, isTrue);
    await f.changeAccount();
    await t.pump();
    expect(f.controller.ready, isFalse);
    expect(f.controller.items, isEmpty);
    expect(f.controller.unread.value, 0);
    expect(f.reads, hasLength(2));
    expect(f.accounts, 2);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    await f.replyRead(1);
    await t.pump();
    expect(f.controller.ready, isTrue);
    expect(f.writes, 0);
    await t.runAsync(f.close);
  });

  testWidgets('confirmed user receipt keeps its authoritative readback foreground', (t) async {
    final f = _InboxMeter();
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    final marked = f.markRead();
    await t.pump();
    expect(f.writes, 1);
    expect(f.reads, hasLength(2));
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    expect(f.rows.lastWhere((r) => r['kind'] == 'transportStart')['activity'], 'foreground');
    expect(f.controller.unread.value, 1);
    await f.replyRead(1);
    await t.pump();
    expect(await marked, isTrue);
    expect(f.controller.unread.value, 0);
    await t.runAsync(f.close);
  });

  testWidgets('failed user receipt never clears unread or manufactures successful readback', (t) async {
    final f = _InboxMeter()..acceptWrite = false;
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    final marked = f.markRead();
    await t.pump();
    expect(await marked, isFalse);
    expect(f.writes, 1);
    expect(f.reads, hasLength(1));
    expect(f.controller.unread.value, 1);
    expect(f.controller.error, 'write');
    await t.runAsync(f.close);
  });

  testWidgets('social wake queued during a failed receipt rereads passively without confirming the receipt', (t) async {
    final f = _InboxMeter()..acceptWrite = false;
    addTearDown(f.close);
    f.start();
    await t.pump();
    await f.replyRead(0);
    await t.pump();
    final marked = f.markRead();
    // The send is already admitted but the fake Host has not replied yet.
    notifySocialReadChanged(f.session);
    await t.pump();
    expect(await marked, isFalse);
    expect(f.writes, 1);
    expect(f.reads, hasLength(2));
    expect(f.controller.unread.value, 1);
    expect(f.controller.error, 'write');
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.rows.lastWhere((r) => r['kind'] == 'transportStart')['activity'], 'background');
    await f.replyRead(1);
    await t.pump();
    expect(f.controller.unread.value, 1);
    expect(f.writes, 1);
    expect(f.metrics.pendingTransportsFor(1), 0);
    await t.runAsync(f.close);
  });
}
