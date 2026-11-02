// 0.7.2 G5/G6/G7 data layer (UI waits for the approved preview).
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_records_controller.dart';

class _Port implements MarketplaceRecordsPort {
  final calls = <(String, MarketRow)>[];
  final blocked = <String>{'r1', 'r2'};
  bool failReports = false;
  @override
  bool get recordsSupported => true;
  @override
  Future<MarketRow> records(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add((operation, input));
    switch (operation) {
      case 'reviews':
        final page = input['page'] as int;
        return {
          'rows': [
            {'id': page * 10 + 1, 'reviewer': 'A*****y', 'rating': 5},
          ],
          'total': 2,
        };
      case 'reports':
        if (failReports) {
          throw const MarketplaceTradeError('marketplace.reauthorize_required');
        }
        return {'rows': <MarketRow>[], 'total': 0};
      case 'blocklist':
        return {
          'rows': [
            for (final ref in blocked) {'ref': ref, 'name': 'D*****8'},
          ],
          'total': blocked.length,
        };
      case 'unblock':
        blocked.remove(input['ref']);
        return {'ref': input['ref'], 'confirmed': true};
    }
    throw StateError(operation);
  }
}

void main() {
  test(
    'pages append; unblock is sent once and the list is read again',
    () async {
      final port = _Port();
      final c = MarketplaceRecordsController(port);
      addTearDown(c.dispose);

      await c.load('reviews');
      expect(c.reviews.rows, hasLength(1));
      expect(c.reviews.more, isTrue);
      await c.load('reviews', more: true);
      expect(c.reviews.rows.map((r) => r['id']), [11, 21]);
      expect(c.reviews.more, isFalse);
      await c.load('reviews', more: true);
      expect(
        port.calls.where((x) => x.$1 == 'reviews'),
        hasLength(2),
        reason: 'no read past the end',
      );

      await c.load('blocklist');
      expect(c.blocklist.total, 2);
      expect(await c.unblock('r1'), isTrue);
      expect(port.calls.where((x) => x.$1 == 'unblock'), hasLength(1));
      expect(c.blocklist.rows.map((r) => r['ref']), [
        'r2',
      ], reason: 'read again after unblock');

      port.failReports = true;
      await c.load('reports');
      expect(c.reports.failed, isTrue);
      expect(c.reports.error, 'marketplace.reauthorize_required');

      c.reset();
      expect(c.blocklist.rows, isEmpty);
      expect(c.reviews.total, 0);
    },
  );
}
