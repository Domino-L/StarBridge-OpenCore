import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../onboarding/connection_mode_port.dart';

typedef CatalogRow = Map<String, Object?>;

enum CatalogKind { missions, blueprints }

CatalogRow catalogObject(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<CatalogRow> catalogRows(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList()
    : const [];

String catalogName(
  CatalogRow row,
  String locale,
  String english, [
  String? chinese,
]) {
  final en = row[english]?.toString().trim() ?? '';
  if (locale == 'en') return en.isEmpty ? '—' : en;
  final cn = row[chinese ?? '${english}Cn']?.toString().trim() ?? '';
  return cn.isEmpty ? (en.isEmpty ? '—' : en) : cn;
}

final class CatalogFailure implements Exception {
  const CatalogFailure([this.code = 'catalog.unavailable']);
  final String code;
  bool get limited => code == 'catalog.rate_limited';
}

abstract interface class CatalogPort {
  bool get canOpenWebsite;
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  });
  Future<void> openWebsite(CatalogKind kind, CatalogRow detail);
  void dispose();
}

final class UnavailableCatalogPort implements CatalogPort {
  const UnavailableCatalogPort();
  @override
  bool get canOpenWebsite => false;
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) async => throw const CatalogFailure();
  @override
  Future<void> openWebsite(CatalogKind kind, CatalogRow detail) async =>
      throw const CatalogFailure();
  @override
  void dispose() {}
}

/// No HTTP client or endpoint knowledge in Flutter. The Host owns cache and budgets.
final class BridgeCatalogPort implements CatalogPort {
  BridgeCatalogPort(this.session, this.mode) {
    _remove = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _paused = true;
          await Future.wait(
            _pending.toList().map((request) => request.cancel()),
          );
        },
        reconcile: () async {
          _paused = false;
        },
      ),
    );
  }
  final BridgeClientSession session;
  final ConnectionModeControl? mode;
  final _pending = <BridgeRequestOperation>{};
  late final void Function() _remove;
  bool _disposed = false, _paused = false;
  @override
  bool get canOpenWebsite =>
      session.hostCapabilities.contains('catalog.openScm');

  Future<CatalogRow> _request(String name, CatalogRow input) async {
    if (_disposed ||
        _paused ||
        session.connectionModeChanging ||
        mode?.allowsOnlineTraffic != true ||
        !session.hostCapabilities.contains(
          name == 'catalog.openScm' ? name : 'catalog.read',
        )) {
      throw const CatalogFailure();
    }
    final generation = session.activeGeneration;
    final work = session.beginRequest(
      name,
      payload: {'schemaVersion': 1, ...input},
      timeout: const Duration(seconds: 22),
    );
    _pending.add(work);
    try {
      final response = await work.future;
      if (_disposed ||
          _paused ||
          generation != session.activeGeneration ||
          generation != response.sessionGeneration ||
          session.connectionModeChanging ||
          mode?.allowsOnlineTraffic != true ||
          response.status != 'ok' ||
          response.payload['schemaVersion'] != 1) {
        throw const CatalogFailure();
      }
      return response.payload;
    } on BridgeRemoteException catch (error) {
      throw CatalogFailure(error.code);
    } finally {
      _pending.remove(work);
    }
  }

  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) async {
    final response = await _request(operation, {
      ...parameters,
      if (refresh) 'refresh': true,
    });
    final data = response['data'];
    if (data is! Map) throw const CatalogFailure();
    return Map<String, Object?>.from(data);
  }

  @override
  Future<void> openWebsite(CatalogKind kind, CatalogRow detail) async {
    await _request('catalog.openScm', {
      'kind': kind.name,
      if (kind == CatalogKind.blueprints) 'id': detail['id'],
      if (kind == CatalogKind.missions)
        'title': (detail['titleCn']?.toString().trim().isNotEmpty == true)
            ? detail['titleCn']
            : detail['title'],
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _remove();
    for (final request in _pending.toList()) {
      unawaited(request.cancel());
    }
  }
}
