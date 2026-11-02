import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/direct_message_refresh.dart';
import '../_support/loading_ownership_original/reference_direct_message_refresh.dart' as reference;
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_contract.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'message_reception_owner_test.dart' as fixture;

class MeterPort extends fixture.Port {
  MeterPort(super.backend, super.name);
  @override
  Future<List<Conversation>> directory() {
    final future = super.directory();
    LoadingMetrics.current?.observe('directMessages.read', future,
        transport: true);
    return future;
  }
}

class ReceptionMeter {
  ReceptionMeter() {
    backend.pending = held;
    owner = runZoned(() =>
        const bool.fromEnvironment('LOADING_RECEIVER_ORIGINAL')
        ? reference.DirectMessageRefresh(MeterPort(backend, 'root'), account)
        : DirectMessageRefresh(MeterPort(backend, 'root'), account),
        zoneValues: {loadingMetricsZoneKey: metrics});
    a = owner.borrow(MeterPort(backend, 'a')) as DirectMessagesPort;
    b = owner.borrow(MeterPort(backend, 'b')) as DirectMessagesPort;
    metrics.route('/profile');
  }
  final backend = fixture.Backend();
  final held = Completer<List<Conversation>>();
  final account = ValueNotifier(const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.legacySignedIn));
  int time = 0;
  final rows = <Map<String, Object>>[];
  late final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add);
  late final dynamic owner;
  late final DirectMessagesPort a, b;
  bool _closed = false;
  Future<String> read(DirectMessagesPort port) => runZoned(() =>
      metrics.foreground(port.directory).then((_) => 'ok',
        onError: (Object _, StackTrace _) => 'rejected'),
      zoneValues: {loadingMetricsZoneKey: metrics});
  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    owner.dispose();
    if (!held.isCompleted) held.complete([backend.peer]);
    final pending = backend.pending;
    if (pending != null && !pending.isCompleted) pending.complete([backend.peer]);
    await tester.pump();
    await a.close(); await b.close();
    account.dispose();
    await backend.close();
    metrics.stop();
  }
}

void main() {
  testWidgets('foreground-first reception releases a cancelled page while root IO continues', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    // Start before the root's scheduled passive wake: causal order is material.
    final one = f.read(f.a);
    expect(fixture.total(f.backend.directories), 1);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 1);
    f.a.cancel();
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.held.isCompleted, isFalse);
    final two = f.read(f.b);
    expect(f.metrics.pendingPageReadsFor(1), 1);
    expect(fixture.total(f.backend.directories), 1);
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(await one, 'rejected');
    expect(await two, 'ok');
    expect(f.metrics.pendingTransportsFor(1), 0);
    await f.close(t);
  });

  testWidgets('last foreground view closing does not leave a root transport page lease', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    final read = f.read(f.a);
    await f.a.close();
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.rows.where((r) => r['kind'] == 'readLeaseRetired' &&
        r['reason'] == 'disposed'), hasLength(1));
    expect(f.held.isCompleted, isFalse);
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(await read, 'rejected');
    expect(f.metrics.pendingTransportsFor(1), 0);
    await f.close(t);
  });

  testWidgets('passive reception does not hold unrelated page; foreground joins one cycle', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    await t.pump(const Duration(milliseconds: 1));
    expect(fixture.total(f.backend.directories), 1);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    final one = f.read(f.a), two = f.read(f.b);
    expect(f.metrics.pendingPageReadsFor(1), 2);
    expect(fixture.total(f.backend.directories), 1);
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(await one, 'ok'); expect(await two, 'ok');
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(fixture.total(f.backend.directories), 1);
    await f.close(t);
  });

  testWidgets('cancelling one upper view retires only its page lease; physical peer continues', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    await t.pump(const Duration(milliseconds: 1));
    final one = f.read(f.a), two = f.read(f.b);
    expect(f.metrics.pendingPageReadsFor(1), 2);
    f.a.cancel();
    expect(f.metrics.pendingPageReadsFor(1), 1);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.rows.where((row) => row['kind'] == 'readLeaseRetired' &&
        row['reason'] == 'cancelled'), hasLength(1));
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(await one, 'rejected'); expect(await two, 'ok');
    expect(fixture.total(f.backend.directories), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    await f.close(t);
  });

  testWidgets('scope retirement clears page lease without declaring pending physical IO complete', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    await t.pump(const Duration(milliseconds: 1));
    final read = f.read(f.a);
    expect(f.metrics.pendingPageReadsFor(1), 1);
    f.backend.mode++;
    f.backend.changeScope(hard: true);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.rows.where((row) => row['kind'] == 'readLeaseRetired' &&
        row['reason'] == 'invalidated'), hasLength(1));
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(await read, 'rejected');
    expect(f.metrics.pendingTransportsFor(1), 0);
    await f.close(t);
  });

  testWidgets('foreground read during busy background handoff owns only a releasable page lease', (t) async {
    final f = ReceptionMeter();
    addTearDown(() => f.close(t));
    await t.pump(const Duration(milliseconds: 1));
    final next = Completer<List<Conversation>>();
    Future<String>? joined;
    void readFresh() {
      if (joined != null) return;
      // The old cycle publishes unread before its polling callback finishes.
      // Only public owner/view APIs are used, without changing polling state.
      f.backend.pending = next;
      joined = f.read(f.a);
    }
    f.owner.unread.addListener(readFresh);
    f.held.complete([f.backend.peer]);
    await t.pump();
    expect(joined, isNotNull);
    expect(fixture.total(f.backend.directories), 2);
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 1);
    f.a.cancel();
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    next.complete([f.backend.peer]);
    await t.pump();
    expect(await joined!, 'rejected');
    expect(f.metrics.pendingTransportsFor(1), 0);
    f.owner.unread.removeListener(readFresh);
    await f.close(t);
  });
}
