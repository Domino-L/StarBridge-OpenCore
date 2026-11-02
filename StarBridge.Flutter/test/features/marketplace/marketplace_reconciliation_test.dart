import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_trade_events_test.dart' show EventPort;

void main() {
  testWidgets(
    '120s remote probe reuses first page and unchanged skips other reads',
    (tester) async {
      final p = EventPort();
      final c = MarketplaceTradesController(p)..setVisible(true);
      addTearDown(c.dispose);
      addTearDown(p.changes.close);
      p.pages[1] = [Map.of(p.row)];
      p.pages[2] = [
        {...p.row, 'transactionNumber': 'T2'},
      ];
      await c.start();
      await c.refresh(more: true);
      await c.open('T1');
      final reads = p.reads;
      await tester.pump(const Duration(seconds: 119));
      expect(p.reads, reads);
      await tester.pump(const Duration(seconds: 1));
      expect(
        p.reads,
        reads + 1,
        reason: 'one remote page, zero further page reads',
      );
      expect(p.detailReads, 1, reason: 'no unchanged detail read');
      expect(p.revisionReads, 1);
      p.pages[1] = [
        {...p.row, 'deliveryStatus': 2},
      ];
      await tester.pump(const Duration(seconds: 120));
      expect(
        p.reads,
        reads + 3,
        reason: 'probe reused, only page two is reread',
      );
      expect(p.detailReads, 2);
      expect(c.rows.first['deliveryStatus'], 2);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  testWidgets(
    'push and reconnect invalidation read immediately; background defers',
    (tester) async {
      final p = EventPort();
      final c = MarketplaceTradesController(p);
      addTearDown(c.dispose);
      addTearDown(p.changes.close);
      await c.start();
      await c.open('T1');
      p.changes.add(
        null,
      ); // Host uses the same invalidation on reconnect/disconnect.
      await tester.pump();
      expect(p.reads, 2);
      expect(p.detailReads, 2);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      p.changes.add(null);
      await tester.pump(const Duration(minutes: 8));
      expect(p.reads, 2);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(p.reads, 3);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
    },
  );

  testWidgets('hidden without actionable trades has no periodic probes', (
    tester,
  ) async {
    final p = EventPort()..row['transactionStatus'] = 3;
    final c = MarketplaceTradesController(p);
    addTearDown(c.dispose);
    addTearDown(p.changes.close);
    await c.start();
    await tester.pump(const Duration(minutes: 8));
    expect(p.reads, 1);
    c.setVisible(true);
    await tester.pump(const Duration(seconds: 120));
    expect(p.reads, 2);
    c.setVisible(false);
    await tester.pump(const Duration(minutes: 8));
    expect(p.reads, 2);
  });

  testWidgets(
    'remote probe denial stops timer and push reads until explicit retry',
    (tester) async {
      for (final code in [
        'marketplace.forbidden',
        'marketplace.sign_in_required',
      ]) {
        final p = EventPort();
        final c = MarketplaceTradesController(p);
        await c.start();
        p.readFailure = code;
        await tester.pump(const Duration(seconds: 120));
        expect(p.reads, 2);
        p.changes.add(null);
        await tester.pump(const Duration(minutes: 8));
        expect(p.reads, 2);
        c.dispose();
        await p.changes.close();
      }
    },
  );
  // CX-T24: the warm-up prefetch starts trades before the hall ever opens; a
  // minimized app must stop the todo-driven check even then.
  testWidgets('started by prefetch, never opened: background stops checks', (
    tester,
  ) async {
    final p = EventPort();
    p.pages[1] = [
      {...p.row, 'deliveryStatus': 1, 'actorRole': 'seller'},
    ];
    final c = MarketplaceTradesController(p);
    addTearDown(c.dispose);
    addTearDown(p.changes.close);
    await c.start();
    await c.refresh();
    expect(c.todo, isNotEmpty, reason: 'a waiting trade drives checks');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reads = p.reads;
    await tester.pump(const Duration(seconds: 250));
    expect(p.reads, reads, reason: 'no background reads');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(p.reads, greaterThan(reads), reason: 'checks again on return');
    // Leave the app backgrounded so the 120 s timer is cancelled.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  });
}
