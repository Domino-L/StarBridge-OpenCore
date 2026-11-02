import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../onboarding/connection_mode_port.dart';

typedef MarketRow = Map<String, Object?>;
num? marketSevenDaySellChange(List<MarketRow> rows) {
  if (rows.isEmpty) return null;
  final dated =
      rows
          .where((r) => DateTime.tryParse(r['date']?.toString() ?? '') != null)
          .toList()
        ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
  if (dated.isEmpty) return null;
  final last = dated.last;
  final target = DateTime.parse(last['date'].toString())
      .subtract(const Duration(days: 7));
  final before = dated
      .where((r) => DateTime.parse(r['date'].toString()) == target)
      .firstOrNull;
  final a = marketNumber(before?['sellPrice']),
      b = marketNumber(last['sellPrice']);
  return a == null || b == null || a <= 0 || b <= 0 ? null : (b - a) / a * 100;
}

final class MarketRead {
  const MarketRead(this.data, this.readAt);
  final MarketRow data;
  final DateTime readAt;
  List<MarketRow> get rows => marketRows(data['rows']);
  int? get total => data['total'] as int?;
}

List<MarketRow> marketRows(Object? value) => value is List
    ? value.map((e) => Map<String, Object?>.from(e as Map)).toList()
    : const [];
num? marketNumber(Object? value) => value is num
    ? value
    : value is String
    ? num.tryParse(value)
    : null;
String marketName(MarketRow row, String locale, {String field = 'itemName'}) {
  final key = locale == 'en'
      ? (field == 'itemName' ? 'itemNameEn' : 'nameEn')
      : locale == 'hant'
      ? '${field}Hant'
      : field;
  return (row[key] as String?)?.trim().isNotEmpty == true
      ? row[key] as String
      : row[field] as String? ?? '';
}

abstract interface class MarketplacePort {
  bool get available;
  int get generation;
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  });
  Future<MarketRow> preferences([MarketRow? value]);
  void dispose();
}

abstract interface class MarketplaceTradePort {
  Future<MarketRow> trade(String operation, [MarketRow input = const {}]);
}

abstract interface class MarketplaceTradeEvents {
  Stream<void> get tradeChanges;
}

abstract interface class MarketplaceTradeProfilePort {
  Future<MarketRow> tradeProfile([MarketRow? changes]);
}

/// The member's own records (0.7.2 G5/G6/G7): received reviews, reports,
/// blocklist and unblock. Blocked users are opaque Host references.
abstract interface class MarketplaceRecordsPort {
  bool get recordsSupported;
  Future<MarketRow> records(String operation, [MarketRow input = const {}]);
}

/// SCM trade messages (0.7.2 G9), two-way with the SCM site. Peers are opaque
/// Host references. `chatPushes` carries each live push itself
/// (`kind`: message / unread / resync), so it shows without a round trip.
abstract interface class MarketplaceChatPort {
  bool get chatSupported;
  Stream<MarketRow> get chatPushes;
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]);
}

/// SCM contracts (0.7.2 G1): public list, mine, detail and the contract
/// actions. People are masked; `chat` fields are opaque message references.
abstract interface class MarketplaceContractsPort {
  bool get contractsSupported;
  Future<MarketRow> contracts(String operation, [MarketRow input = const {}]);
}

/// The member's own SCM warehouse, read only (0.7.2 G2).
abstract interface class MarketplaceWarehousePort {
  bool get warehouseSupported;
  Future<MarketRow> warehouse(String operation, [MarketRow input = const {}]);
}

/// SCM station messages for the notification center (0.7.2 G8): system,
/// trade and chat-fallback notices with read marks. Traders are masked.
abstract interface class MarketplaceNoticesPort {
  bool get noticesSupported;
  Future<MarketRow> notices(String operation, [MarketRow input = const {}]);
}

bool _accountScoped(String name) =>
    name == 'marketplace.trade' ||
    name == 'marketplace.records' ||
    name == 'marketplace.chat' ||
    name == 'marketplace.contracts' ||
    name == 'marketplace.warehouse' ||
    name == 'marketplace.notices' ||
    name == 'marketplace.listings' ||
    name.startsWith('tradeProfile.');

class MarketplaceTradeError implements Exception {
  const MarketplaceTradeError(this.code);
  final String code;
}

final class BridgeMarketplacePort
    implements
        MarketplacePort,
        MarketplaceTradePort,
        MarketplaceTradeEvents,
        MarketplaceTradeProfilePort,
        MarketplaceRecordsPort,
        MarketplaceChatPort,
        MarketplaceContractsPort,
        MarketplaceWarehousePort,
        MarketplaceNoticesPort {
  BridgeMarketplacePort(this.session, this.mode) {
    _removeParticipant = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _paused = true;
          await Future.wait(_pending.toList().map((work) => work.cancel()));
        },
        reconcile: () async {
          _paused = false;
        },
      ),
    );
  }
  final BridgeClientSession session;
  @override
  Stream<void> get tradeChanges => session.events
      .where(
        (event) =>
            event.name == 'marketplace.changed' && !_disposed && !_paused,
      )
      .map((_) {});
  final ConnectionModeControl? mode;
  final _pending = <BridgeRequestOperation>{};
  bool _disposed = false;
  bool _paused = false;
  late final void Function() _removeParticipant;
  @override
  bool get available =>
      !_disposed && session.hostCapabilities.contains('marketplace.read');
  @override
  int get generation => session.activeGeneration;
  Future<MarketRow> _request(String name, MarketRow payload) async {
    if (_disposed ||
        _paused ||
        !session.hostCapabilities.contains(name) ||
        session.connectionModeChanging ||
        name != 'marketplace.preferences' &&
            mode?.allowsOnlineTraffic != true) {
      throw const FormatException('marketplace.unavailable');
    }
    final generation = this.generation;
    BridgeAccountContext? owner;
    if (_accountScoped(name)) {
      final account = await session.request(
        'account.getCurrent',
        payload: {'schemaVersion': 1},
      );
      if (_disposed ||
          _paused ||
          this.generation != generation ||
          account.sessionGeneration != generation ||
          session.connectionModeChanging ||
          mode?.allowsOnlineTraffic != true) {
        throw const MarketplaceTradeError('marketplace.context_changed');
      }
      if (account.status != 'ok' ||
          account.payload['schemaVersion'] != 1 ||
          account.payload['state'] != 'signedIn' ||
          account.accountContext == null) {
        throw const MarketplaceTradeError('marketplace.sign_in_required');
      }
      owner = account.accountContext;
    }
    final work = session.beginRequest(
      name,
      payload: payload,
      accountContext: owner,
      timeout: const Duration(seconds: 22),
    );
    _pending.add(work);
    try {
      final BridgeEnvelope response;
      try {
        response = await work.future;
      } on BridgeRemoteException catch (error) {
        // The session surfaces Host errors as exceptions; keep the stable code for account-scoped calls.
        if (_accountScoped(name)) {
          throw MarketplaceTradeError(error.code);
        }
        rethrow;
      }
      if (response.status == 'error' && (_accountScoped(name))) {
        throw MarketplaceTradeError(
          response.error?.code ?? 'marketplace.unavailable',
        );
      }
      if (_disposed ||
          this.generation != generation ||
          response.sessionGeneration != generation ||
          response.status != 'ok') {
        throw const FormatException('marketplace.unavailable');
      }
      return response.payload;
    } finally {
      _pending.remove(work);
    }
  }

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
    final pending = _request('marketplace.read', {
      'schemaVersion': 1,
      'operation': operation,
      'id': id,
      'keyword': keyword,
      'category': category,
      'side': side,
      'page': page,
      'language': language,
      if (options.isNotEmpty) 'options': options,
    });
    // Every read shares one bridge name; this consumer span names the
    // operation (fixed labels only, see LoadingMetrics) so a slow first
    // screen shows which read it waits on.
    LoadingMetrics.current?.observe(
      'marketplace.read.$operation',
      pending,
      transport: false,
    );
    final response = await pending;
    if (response['schemaVersion'] != 1 || response['data'] is! Map) {
      throw const FormatException('Invalid marketplace response');
    }
    return MarketRead(
      Map<String, Object?>.from(response['data'] as Map),
      DateTime.parse(response['readAt'] as String),
    );
  }

  @override
  Future<MarketRow> trade(
    String operation, [
    MarketRow input = const {},
  ]) async {
    try {
      final response = await _request('marketplace.trade', {
        ...input,
        'schemaVersion': 1,
        'operation': operation,
      });
      return Map<String, Object?>.from(response['data'] as Map);
    } on BridgeRemoteException catch (error) {
      throw MarketplaceTradeError(error.code);
    } on Object catch (error) {
      // Types/codes only: never log account context, payloads or server messages.
      debugPrint(
        'marketplace-trade | errorType=${error.runtimeType}'
        '${error is MarketplaceTradeError ? ' code=${error.code}' : ''}',
      );
      rethrow;
    }
  }

  @override
  bool get recordsSupported =>
      !_disposed && session.hostCapabilities.contains('marketplace.records');

  @override
  Future<MarketRow> records(
    String operation, [
    MarketRow input = const {},
  ]) async {
    final response = await _request('marketplace.records', {
      ...input,
      'schemaVersion': 1,
      'operation': operation,
    });
    return Map<String, Object?>.from(response['data'] as Map);
  }

  @override
  bool get contractsSupported =>
      !_disposed && session.hostCapabilities.contains('marketplace.contracts');

  @override
  Future<MarketRow> contracts(String operation, [MarketRow input = const {}]) =>
      _hall('marketplace.contracts', operation, input);

  @override
  bool get noticesSupported =>
      !_disposed && session.hostCapabilities.contains('marketplace.notices');

  @override
  Future<MarketRow> notices(String operation, [MarketRow input = const {}]) =>
      _hall('marketplace.notices', operation, input);

  @override
  bool get warehouseSupported =>
      !_disposed && session.hostCapabilities.contains('marketplace.warehouse');

  @override
  Future<MarketRow> warehouse(String operation, [MarketRow input = const {}]) =>
      _hall('marketplace.warehouse', operation, input);

  Future<MarketRow> _hall(
    String name,
    String operation,
    MarketRow input,
  ) async {
    final response = await _request(name, {
      ...input,
      'schemaVersion': 1,
      'operation': operation,
    });
    return Map<String, Object?>.from(response['data'] as Map);
  }

  @override
  bool get chatSupported =>
      !_disposed && session.hostCapabilities.contains('marketplace.chat');

  @override
  Stream<MarketRow> get chatPushes => session.events
      .where(
        (event) =>
            event.name == 'marketplace.chatPushed' && !_disposed && !_paused,
      )
      .map((event) => event.payload['push'])
      .where((push) => push is Map)
      .map((push) => (push as Map).cast<String, Object?>());

  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) async {
    final response = await _request('marketplace.chat', {
      ...input,
      'schemaVersion': 1,
      'operation': operation,
    });
    return Map<String, Object?>.from(response['data'] as Map);
  }

  @override
  Future<MarketRow> preferences([MarketRow? value]) => _request(
    'marketplace.preferences',
    {'schemaVersion': 1, 'value': ?value},
  );

  Future<MarketRow> listings(
    String operation, [
    MarketRow input = const {},
  ]) async {
    final response = await _request('marketplace.listings', {
      ...input,
      'schemaVersion': 1,
      'operation': operation,
    });
    return Map<String, Object?>.from(response['data'] as Map);
  }

  @override
  Future<MarketRow> tradeProfile([MarketRow? changes]) async {
    final response = await _request(
      changes == null ? 'tradeProfile.read' : 'tradeProfile.write',
      {'schemaVersion': 1, 'changes': ?changes},
    );
    return Map<String, Object?>.from(response['data'] as Map);
  }

  @override
  void dispose() {
    _disposed = true;
    _removeParticipant();
    for (final work in _pending.toList()) {
      unawaited(work.cancel());
    }
    _pending.clear();
  }
}

final class UnavailableMarketplacePort implements MarketplacePort {
  @override
  bool get available => false;
  @override
  int get generation => 0;
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
  }) => Future.error(const FormatException('marketplace.unavailable'));
  @override
  Future<MarketRow> preferences([MarketRow? value]) =>
      Future.error(const FormatException('marketplace.unavailable'));
  @override
  void dispose() {}
}
