// 0.7.2 G1/G2 data layers (UI waits for the approved previews).
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_contracts_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_warehouse_controller.dart';

class _Port implements MarketplaceContractsPort, MarketplaceWarehousePort {
  final calls = <(String, MarketRow)>[];
  bool refuseApply = false;
  int applicants = 2;
  @override
  bool get contractsSupported => true;
  @override
  bool get warehouseSupported => true;

  @override
  Future<MarketRow> contracts(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add(('c.$operation', input));
    switch (operation) {
      case 'list':
        final page = input['page'] as int;
        return {
          'rows': [
            {'id': page, 'type': input['type'] ?? 'SERVICE', 'status': 1},
          ],
          'total': 2,
        };
      case 'mine':
        return input['scope'] == 'participated'
            ? {
                'rows': [
                  {'id': 8, 'status': 2},
                ],
                'total': 1,
              }
            : {
                'rows': [
                  {'id': 17, 'status': 1, 'applications': applicants},
                  {'id': 18, 'status': 3},
                ],
                'total': 2,
              };
      case 'detail':
        return {
          'contract': {'id': input['id'], 'status': 1},
          'milestones': const [],
          'participants': {'rows': const [], 'total': 0},
        };
      case 'apply':
        if (refuseApply) {
          throw const MarketplaceTradeError('marketplace.trade_rejected');
        }
        return {'confirmed': true, 'participantId': 6};
      default:
        return {'confirmed': true};
    }
  }

  @override
  Future<MarketRow> warehouse(
    String operation, [
    MarketRow input = const {},
  ]) async {
    calls.add(('w.$operation', input));
    return switch (operation) {
      'spaces' => {
        'rows': [
          {'id': 3, 'name': '主仓', 'available': 100},
        ],
      },
      'summary' => {'items': 5},
      'inventory' || 'ledger' => {
        'rows': [
          {'id': 9},
        ],
        'total': 1,
      },
      _ => {
        'rows': [
          {'id': input['after'] == null ? 40 : 41},
        ],
        'next': input['after'] == null ? 41 : null,
        'more': input['after'] == null,
      },
    };
  }
}

void main() {
  test(
    'contracts: filters, paging, attention, one-shot actions then re-read',
    () async {
      final port = _Port();
      final c = MarketplaceContractsController(port);
      addTearDown(c.dispose);

      await c.filter(type: 'BOUNTY', status: 1, keyword: ' 货船 ');
      expect(port.calls.last.$2, {
        'page': 1,
        'type': 'BOUNTY',
        'status': 1,
        'keyword': '货船',
      });
      await c.loadPublic(more: true);
      expect(c.public.rows.map((r) => r['id']), [1, 2]);

      await c.loadMine('created');
      await c.loadMine('participated');
      expect(c.attention, 1, reason: 'recruiting with applicants');

      await c.open(17);
      expect((c.detail!['contract'] as Map)['id'], 17);
      expect(await c.act('apply', {'message': '有 Hornet'}), isTrue);
      expect(port.calls.where((x) => x.$1 == 'c.apply').single.$2, {
        'id': 17,
        'message': '有 Hornet',
      });
      expect(
        port.calls.where((x) => x.$1 == 'c.detail'),
        hasLength(2),
        reason: 'detail read again after the action',
      );

      port.refuseApply = true;
      expect(await c.act('apply'), isFalse);
      expect(c.actionError, 'marketplace.trade_rejected');
      expect(port.calls.where((x) => x.$1 == 'c.apply'), hasLength(2));

      c.reset();
      expect(c.public.rows, isEmpty);
      expect(c.detail, isNull);
    },
  );

  test(
    'warehouse: spaces with summary, filtered inventory, escrow cursor',
    () async {
      final port = _Port();
      final w = MarketplaceWarehouseController(port);
      addTearDown(w.dispose);

      await w.loadSpaces();
      expect(w.spaces.single['name'], '主仓');
      expect(w.summary!['items'], 5);
      await w.select(3);
      await w.search(keyword: ' 钛 ', onlyAvailable: true);
      expect(port.calls.last.$2, {
        'page': 1,
        'spaceId': 3,
        'keyword': '钛',
        'available': true,
      });
      expect(
        port.calls.any((x) => x.$1 == 'w.ledger' && x.$2['spaceId'] == 3),
        isTrue,
      );

      await w.loadEscrow();
      expect(w.escrowMore, isTrue);
      await w.loadEscrow(more: true);
      expect(w.escrow.map((r) => r['id']), [40, 41]);
      expect(port.calls.last.$2, {'after': 41});
      expect(w.escrowMore, isFalse);
      await w.loadEscrow(more: true);
      expect(port.calls.where((x) => x.$1 == 'w.escrow'), hasLength(2));

      w.reset();
      expect(w.spaces, isEmpty);
      expect(w.spaceId, isNull);
    },
  );
}
