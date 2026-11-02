// After a Host restart the hall's first burst can time out at the back of the
// queue. A read that fails is asked again a few times, so the page does not
// stay on "名称未取到" until someone leaves and comes back.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

class _Port implements MarketplacePort {
  @override
  bool available = true;
  @override
  int generation = 1;
  bool failing = true;
  final reads = <String>[];
  int inFlight = 0, widest = 0;
  Completer<void>? gate;
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) async {
    reads.add(id == 0 ? operation : '$operation:$id:$side');
    inFlight++;
    if (inFlight > widest) widest = inFlight;
    try {
      if (page == 1) await gate?.future;
      if (failing && id != 0) throw const FormatException('Synthetic timeout');
      return MarketRead({
        'rows': id == 0 ? const [] : [{'id': id, 'itemName': '物品 $id', 'unitPrice': 5}],
        'total': 1,
        if (id != 0) 'id': id,
        if (id != 0) 'itemName': '物品 $id',
      }, DateTime(2026, 10, 30));
    } finally {
      inFlight--;
    }
  }

  @override
  Future<MarketRow> preferences([MarketRow? value]) async => {
    'revision': 0,
    'favorites': <int>[7, 8],
    'recentItems': <int>[],
    'recentSearches': <String>[],
  };
  @override
  void dispose() {}
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

Future<MarketplaceController> _start(WidgetTester tester, _Port port) async {
  final controller = MarketplaceController(port);
  unawaited(controller.initialize());
  await _settle(tester);
  return controller;
}

int _watchReads(_Port port) => port.reads.where((r) => r == 'item:7:1').length;

void main() {
  testWidgets('a failed favourite fills in without leaving the page', (
    tester,
  ) async {
    final port = _Port();
    final c = await _start(tester, port);
    expect(c.failures, contains('watch:7'));
    expect(c.watchEntry(7).item, isNull);

    port.failing = false;
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(c.failures, isEmpty);
    expect(c.watchEntry(7).item, isNotNull);
    expect(c.watchEntry(7).lowest, 5);
    c.dispose();
  });

  testWidgets('rereads are bounded when the read keeps failing', (tester) async {
    final port = _Port();
    final c = await _start(tester, port);
    expect(_watchReads(port), 1);
    for (final seconds in const [3, 10, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await _settle(tester);
    }
    expect(_watchReads(port), 4);
    await tester.pump(const Duration(minutes: 10));
    await _settle(tester);
    expect(_watchReads(port), 4);
    expect(c.failures, contains('watch:7'));
    c.dispose();
  });

  testWidgets('a reread goes four at a time, what the Host admits', (
    tester,
  ) async {
    final port = _Port();
    final c = await _start(tester, port);
    port.widest = 0;
    port.gate = Completer<void>();
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(port.inFlight, 4);
    port.gate!.complete();
    port.gate = null;
    await _settle(tester);
    expect(port.widest, 4);
    c.dispose();
  });

  testWidgets('rounds do not overlap', (tester) async {
    final port = _Port();
    final c = await _start(tester, port);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    port.widest = 0;
    final before = _watchReads(port);
    port.gate = Completer<void>();
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester);
    expect(port.inFlight, 4);
    await tester.pump(const Duration(seconds: 60));
    await _settle(tester);
    expect(port.inFlight, 4, reason: 'The next round waits for this one');
    expect(_watchReads(port), before + 1);
    port.gate!.complete();
    port.gate = null;
    await _settle(tester);
    expect(port.widest, 4);
    c.dispose();
  });

  testWidgets('a failed refilter is not read again with its filter', (
    tester,
  ) async {
    final port = _Port();
    final c = await _start(tester, port);
    port.failing = false;
    await c.load('sell', 'offers', id: 9);
    expect(c.blocks['sell'], isNotNull);
    port.failing = true;
    c.refilter(const ['sell'], () {});
    await c.load('sell', 'offers', id: 9, options: const {'q': 'new'});
    expect(c.failures, contains('sell'));
    final before = port.reads.where((r) => r == 'offers:9:1').length;
    for (final seconds in const [3, 10, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await _settle(tester);
    }
    expect(port.reads.where((r) => r == 'offers:9:1').length, before);
    c.dispose();
  });

  testWidgets('a cancelled filter and a failed next page are not reread', (
    tester,
  ) async {
    final port = _Port();
    final c = await _start(tester, port);
    port.failing = false;
    await c.load('sell', 'offers', id: 9);
    port.gate = Completer<void>();
    c.refilter(const ['sell'], () {});
    final cancelled = c.load('sell', 'offers', id: 9, options: const {'q': 'new'});
    c.cancelRefilter('sell');
    port.gate!.complete();
    port.gate = null;
    await cancelled;
    port.failing = true;
    await c.load('sell', 'offers', id: 9, page: 2, append: true);
    expect(c.failures, contains('sell'));
    final before = port.reads.where((r) => r == 'offers:9:1').length;
    for (final seconds in const [3, 10, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await _settle(tester);
    }
    expect(port.reads.where((r) => r == 'offers:9:1').length, before);
    c.dispose();
  });

  testWidgets('a key dropped during a round does not stop the rereads', (
    tester,
  ) async {
    final port = _Port();
    final c = await _start(tester, port);
    port.gate = Completer<void>();
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(port.inFlight, 4);
    // watch-buy:8 waits for the next batch when its next page fails.
    await c.load('watch-buy:8', 'offers', id: 8, side: 0, page: 2, append: true);
    port.gate!.complete();
    port.gate = null;
    await _settle(tester);
    final before = _watchReads(port);
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester);
    expect(_watchReads(port), before + 1, reason: 'The next round still runs');
    c.dispose();
  });

  testWidgets('a new account context drops the pending reread', (tester) async {
    final port = _Port();
    final c = await _start(tester, port);
    final before = _watchReads(port);
    c.contextChanged();
    await _settle(tester);
    expect(_watchReads(port), before + 1, reason: 'The new context reads once');
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(_watchReads(port), before + 1, reason: 'Its clock starts again');
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(_watchReads(port), before + 2);
    c.dispose();
  });

  testWidgets('disposing stops the rereads', (tester) async {
    final port = _Port();
    final c = await _start(tester, port);
    final before = port.reads.length;
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(port.reads.length, before);
  });
}
