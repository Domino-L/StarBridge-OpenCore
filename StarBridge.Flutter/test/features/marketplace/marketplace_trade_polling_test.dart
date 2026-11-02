import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_trades_test.dart' show TradesPort;

class PollingPort extends TradesPort {
  String? readFailure;
  int revisionReads = 0, detailReads = 0;
  Completer<MarketRow>? revisionGate;
  @override
  Future<MarketRow> trade(String op, [MarketRow input = const {}]) {
    if (op == 'revision') {
      revisionReads++;
      if (revisionGate != null) return revisionGate!.future;
    }
    if (op == 'detail') detailReads++;
    if (op == 'list' && readFailure != null) {
      reads++;
      return Future.error(MarketplaceTradeError(readFailure!));
    }
    return super.trade(op, input);
  }
}

// Pump each tick so the actual async revision request can finish between ticks.
Future<void> ticks(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(seconds: 2));
  }
}

void main() {
  for (final code in [
    'marketplace.forbidden',
    'marketplace.sign_in_required',
  ]) {
    testWidgets(
      'initial $code stops actual timer and explicit retries do not loop',
      (tester) async {
        final p = PollingPort()..readFailure = code;
        final c = MarketplaceTradesController(p);
        try {
          await c.start();
          expect(p.reads, 1);
          await ticks(tester, 45);
          expect(
            p.reads,
            1,
            reason: 'No 30-second requests after an authorization denial',
          );
          expect(p.revisionReads, 0);
          p.revision++;
          await c.checkUpdates();
          expect(
            p.revisionReads,
            0,
            reason: 'A new Host/WebSocket revision cannot bypass the authorization block',
          );
          expect(p.reads, 1);
          await c.start();
          await c.refresh();
          expect(p.reads, 2, reason: 'Only the explicit retry reads once');
          await ticks(tester, 30);
          expect(p.reads, 2);
          p.readFailure = null;
          await c.refresh();
          expect(p.reads, 3);
          expect(c.error, isNull);
          expect(c.errorCode, isNull);
          await c.start();
          await ticks(tester, 59);
          expect(p.reads, 3);
          await ticks(tester, 1);
          expect(
            p.reads,
            4,
            reason: 'One restored timer, not duplicate timers',
          );
          expect(p.writes, 0);
        } finally {
          c.dispose();
        }
      },
    );
  }
  testWidgets(
    'later denial keeps snapshots and does not fetch detail after failed list',
    (tester) async {
      final p = PollingPort();
      final c = MarketplaceTradesController(p);
      addTearDown(c.dispose);
      await c.start();
      await c.open('T1');
      p.readFailure = 'marketplace.forbidden';
      await ticks(tester, 60);
      expect(p.reads, 2);
      expect(p.detailReads, 1);
      expect(c.rows.single['transactionNumber'], 'T1');
      expect(c.detail?['transactionNumber'], 'T1');
      await ticks(tester, 45);
      expect(p.reads, 2);
      expect(p.detailReads, 1);
    },
  );
  testWidgets(
    'in-flight revision cannot revive polling after denial or reset',
    (tester) async {
      final p = PollingPort();
      final c = MarketplaceTradesController(p);
      addTearDown(c.dispose);
      await c.start();
      await ticks(tester, 1);
      p.revisionGate = Completer();
      unawaited(c.checkUpdates());
      await ticks(tester, 1);
      p.readFailure = 'marketplace.forbidden';
      await c.refresh();
      final reads = p.reads;
      p.revisionGate!.complete({'revision': 1});
      await tester.pump();
      await ticks(tester, 30);
      expect(p.reads, reads);
      p.revisionGate = null;
      p.readFailure = null;
      c.reset();
      await c.start();
      expect(p.reads, reads + 1);
      await ticks(tester, 1);
      p.revisionGate = Completer();
      unawaited(c.checkUpdates());
      await ticks(tester, 1);
      c.reset();
      p.revisionGate!.complete({'revision': 2});
      await tester.pump();
      await ticks(tester, 30);
      expect(p.reads, reads + 1);
    },
  );
  testWidgets('old start and disposed callbacks cannot create a new timer', (
    tester,
  ) async {
    final p = PollingPort()..tradeReadGate = Completer();
    final c = MarketplaceTradesController(p);
    final start = c.start();
    c.reset();
    p.tradeReadGate!.complete({
      'rows': [p.row],
      'total': 1,
    });
    await start;
    await ticks(tester, 30);
    expect(p.reads, 1);
    p.tradeReadGate = null;
    await c.start();
    p.revisionGate = Completer();
    unawaited(c.checkUpdates());
    await ticks(tester, 1);
    c.dispose();
    p.revisionGate!.complete({'revision': 99});
    await tester.pump();
    await ticks(tester, 30);
    expect(p.reads, 2);
    expect(p.detailReads, 0);
  });
  testWidgets('successful read recovery preserves uncertain writes', (
    tester,
  ) async {
    final p = PollingPort();
    final c = MarketplaceTradesController(p);
    try {
      await c.start();
      p.writeGate = Completer();
      final write = c.submit('ship', {'transactionNumber': 'T1'});
      p.writeGate!.completeError(TimeoutException('fixture'));
      await write;
      final writeError = c.writeError;
      p.readFailure = 'marketplace.forbidden';
      await c.refresh();
      p.readFailure = null;
      await c.refresh();
      expect(c.errorCode, isNull);
      expect(c.writeUncertain, isTrue);
      expect(c.writeError, writeError);
      await ticks(tester, 30);
      expect(p.writes, 1);
      await c.submit('ship', {'transactionNumber': 'T1'});
      expect(p.writes, 1);
    } finally {
      c.dispose();
    }
  });
  testWidgets('confirmed in-flight write cannot bypass a later read denial', (
    tester,
  ) async {
    final p = PollingPort();
    final c = MarketplaceTradesController(p);
    addTearDown(c.dispose);
    await c.start();
    p.writeGate = Completer();
    final write = c.submit('ship', {'transactionNumber': 'T1'});
    p.readFailure = 'marketplace.forbidden';
    await c.refresh();
    expect(p.reads, 2);
    p.writeGate!.complete({'transactionNumber': 'T1', 'confirmed': true});
    expect(await write, 'T1');
    expect(c.pending, isFalse);
    expect(c.writeUncertain, isFalse);
    expect(c.errorCode, 'marketplace.forbidden');
    await ticks(tester, 30);
    expect(p.reads, 2);
    expect(p.detailReads, 0);
    expect(p.writes, 1);
  });
}
