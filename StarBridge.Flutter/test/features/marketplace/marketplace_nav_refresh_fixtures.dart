import 'dart:async';

import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'marketplace_test.dart' show FixturePort;

class NavPort extends FixturePort implements MarketplaceContractsPort,
    MarketplaceWarehousePort, MarketplaceRecordsPort, MarketplaceTradePort,
    MarketplaceTradeProfilePort, MarketplaceChatPort {
  final calls = <String>[];
  final queries = <(String, String, int, Map<String, String>)>[];
  Completer<void>? watchGate, tradeGate;
  MarketRow profile = {
    'timezoneId': 1, 'tradeTime': [1, 1, 1, 1, 1, 1, 1],
    'tradeStartTime': '10:00', 'tradeEndTime': '12:00',
    'userMobile': 'fixture-only',
  };
  @override
  bool get contractsSupported => true;
  @override
  bool get warehouseSupported => true;
  @override
  bool get recordsSupported => true;
  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => const Stream.empty();

  @override
  Future<MarketRead> read(String operation, {int id = 0, String keyword = '',
    int category = 0, int side = 1, int page = 1, String language = 'CN',
    Map<String, String> options = const {}}) async {
    calls.add(operation);
    queries.add((operation, keyword, category, {...options}));
    if (operation == 'offers' && id == 99) await watchGate?.future;
    if (operation == 'timezones') {
      return MarketRead({
        'rows': [{'id': 1, 'label': 'UTC', 'offsetMinutes': 0}],
      }, DateTime.utc(2026));
    }
    return super.read(operation, id: id, keyword: keyword, category: category,
      side: side, page: page, language: language, options: options);
  }

  @override
  Future<MarketRow> contracts(String operation, [MarketRow input = const {}]) async {
    calls.add('contracts:$operation:${input['scope'] ?? ''}');
    return {'rows': <MarketRow>[], 'total': 0};
  }
  @override
  Future<MarketRow> warehouse(String operation, [MarketRow input = const {}]) async {
    calls.add('warehouse:$operation');
    return {'rows': <MarketRow>[], 'total': 0};
  }
  @override
  Future<MarketRow> records(String operation, [MarketRow input = const {}]) async {
    calls.add('records:$operation');
    return {'rows': <MarketRow>[], 'total': 0};
  }
  @override
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]) async {
    calls.add('trade:$operation');
    if (operation == 'list') await tradeGate?.future;
    return {'rows': <MarketRow>[], 'total': 0};
  }
  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    calls.add('chat:$operation');
    return {'rows': <MarketRow>[], 'total': 0};
  }
  @override
  Future<MarketRow> tradeProfile([MarketRow? changes]) async {
    calls.add(changes == null ? 'profile:read' : 'profile:write');
    if (changes == null) return profile;
    profile = {...profile, ...changes};
    return {'profile': profile, 'confirmed': true};
  }
}

/// Uses the real listings adapter, but every operation terminates in memory.
class NavBridge {
  final fake = NavPort();
  int limit = 20;
  final rows = <MarketRow>[];
  Future<MarketRow> listings(String operation, [MarketRow input = const {}]) async {
    fake.calls.add('listings:$operation');
    if (operation == 'read') {
      return {
      'rows': rows, 'total': rows.length, 'limit': limit,
      'items': <MarketRow>[], 'manifests': <MarketRow>[],
      'locations': <MarketRow>[],
    };
    }
    return {'confirmed': true};
  }
  Future<MarketRow> respond(String name, MarketRow input) async {
    fake.profile['orderLimit'] = limit;
    final operation = input['operation'] as String? ?? '';
    if (name == 'account.getCurrent') return {'schemaVersion': 1, 'state': 'signedIn'};
    if (name == 'marketplace.preferences') return fake.preferences(input['value'] as MarketRow?);
    final MarketRow data;
    switch (name) {
      case 'marketplace.read':
        data = (await fake.read(operation, id: input['id'] as int? ?? 0,
          keyword: input['keyword'] as String? ?? '', category: input['category'] as int? ?? 0,
          side: input['side'] as int? ?? 1, page: input['page'] as int? ?? 1)).data;
      case 'marketplace.listings':
        data = await listings(operation, input);
      case 'marketplace.trade':
        data = await fake.trade(operation, input);
      case 'marketplace.records':
        data = await fake.records(operation, input);
      case 'tradeProfile.read':
        data = await fake.tradeProfile();
      case 'tradeProfile.write':
        data = await fake.tradeProfile(input['changes'] as MarketRow?);
      default:
        throw StateError('Unexpected in-memory request: $name');
    }
    return {'schemaVersion': 1, 'data': data, 'readAt': '2026-11-14T00:00:00Z'};
  }
}
