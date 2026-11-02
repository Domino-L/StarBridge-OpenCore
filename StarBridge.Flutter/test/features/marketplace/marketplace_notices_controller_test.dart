// 0.7.2 G8 data layer (colors and the notification-center wiring wait for the
// approved notify-badge preview).
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_notices_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

class _Port implements MarketplaceNoticesPort {
  final calls = <(String, MarketRow)>[];
  var unread = 3;
  @override
  bool get noticesSupported => true;
  @override
  Future<MarketRow> notices(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add((operation, input));
    switch (operation) {
      case 'unread':
        return {'total': unread, 'station': unread - 1, 'chatFallback': 1};
      case 'page':
        return {
          'rows': [
            {'id': 11, 'type': 1, 'subType': 4, 'read': unread == 0},
            {'id': 12, 'type': 0, 'read': true},
          ],
          'total': 2,
        };
      default:
        unread = 0;
        return {'confirmed': true};
    }
  }
}

void main() {
  test('categories map SCM type and trade sub-type', () {
    expect(marketNoticeCategory({'type': 0}), 'system');
    expect(marketNoticeCategory({'type': 2}), 'chat');
    expect(marketNoticeCategory({'type': 1, 'subType': 1}), 'trade.request');
    expect(marketNoticeCategory({'type': 1, 'subType': 5}), 'trade.delivery');
    expect(marketNoticeCategory({'type': 1, 'subType': 6}), 'trade.review');
    expect(marketNoticeCategory({'type': 1, 'subType': 7}), 'trade.timeout');
    expect(marketNoticeCategory({'type': 1}), 'trade');
  });

  test('counts, filters, marks then re-reads', () async {
    final port = _Port();
    final c = MarketplaceNoticesController(port);
    addTearDown(c.dispose);

    await c.loadCounts();
    expect((c.unreadTotal, c.unreadStation, c.unreadChat), (3, 2, 1));
    await c.filter(type: 1, onlyUnread: true);
    expect(port.calls.last.$2, {'page': 1, 'type': 1, 'unread': true});
    expect(c.page.rows, hasLength(2));

    await c.markAllRead();
    expect(port.calls.where((x) => x.$1 == 'readAll').single.$2, {'type': 1});
    expect(c.unreadTotal, 0, reason: 'counts read again after the mark');
    expect(c.page.rows.first['read'], isTrue);

    c.reset();
    expect(c.page.rows, isEmpty);
    expect(c.type, isNull);
  });
}
