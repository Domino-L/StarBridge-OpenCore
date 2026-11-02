import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_notices_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

class _Port implements MarketplaceNoticesPort, MarketplaceTradeEvents {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get tradeChanges => changes.stream;
  @override
  bool get noticesSupported => true;
  bool read = false;
  int pages = 0;
  Completer<void>? pending;
  @override
  Future<MarketRow> notices(
    String operation, [
    MarketRow input = const {},
  ]) async {
    if (operation == 'page') {
      pages++;
      await pending?.future;
      return {
        'rows': [
          {'id': 1, 'read': read},
        ],
        'total': 1,
      };
    }
    return {'total': read ? 0 : 1, 'station': read ? 0 : 1};
  }
}

void main() {
  testWidgets(
    'confirmed inbox receipt refreshes an already used marketplace notice list',
    (tester) async {
      final port = _Port();
      final controller = MarketplaceNoticesController(port);
      addTearDown(() async {
        controller.dispose();
        await port.changes.close();
      });
      port.changes.add(null);
      await tester.pump();
      expect(
        port.pages,
        0,
        reason: 'unused pages do not create background REST work',
      );
      await controller.load();
      await controller.loadCounts();
      expect(controller.unreadTotal, 1);
      port.read = true;
      port.changes.add(null);
      await tester.pump();
      expect(port.pages, 2);
      expect(controller.page.rows.single['read'], isTrue);
      expect(controller.unreadTotal, 0);
      controller.reset();
      port.changes.add(null);
      await tester.pump();
      expect(
        port.pages,
        2,
        reason: 'retired account cannot restart used-page refresh',
      );
    },
  );

  testWidgets(
    'receipt change during a page read is reconciled once after completion',
    (tester) async {
      final port = _Port();
      final controller = MarketplaceNoticesController(port);
      addTearDown(() async {
        controller.dispose();
        await port.changes.close();
      });
      port.pending = Completer<void>();
      final read = controller.load();
      port.changes.add(null);
      port.changes.add(null);
      port.read = true;
      port.pending!.complete();
      await read;
      await tester.pump();
      expect(port.pages, 2);
      expect(controller.unreadTotal, 0);
    },
  );
}
