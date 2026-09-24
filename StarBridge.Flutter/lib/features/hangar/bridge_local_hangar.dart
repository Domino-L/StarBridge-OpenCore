import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'local_hangar_port.dart';
import 'legacy_profile_hangar.dart';
import '../../shared/ships/ship_reviewed_display.dart';

final class BridgeLocalHangar implements LocalHangarPort {
  BridgeLocalHangar(this._session);
  final BridgeClientSession _session;
  BridgeAccountContext? _account;
  int? _generation;
  bool _legacy = false;
  static bool _sameAccount(BridgeAccountContext? a, BridgeAccountContext? b) =>
      a != null &&
      b != null &&
      a.environment == b.environment &&
      a.authority == b.authority &&
      a.subject == b.subject;

  Future<void> _bind() async {
    final response = await _session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 60),
    );
    if (!hasRelayAccount(response) ||
        response.accountContext == null ||
        response.sessionGeneration != _session.activeGeneration) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    if (_generation != null &&
        (_generation != response.sessionGeneration ||
            !_sameAccount(_account, response.accountContext))) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    _account = response.accountContext;
    _generation = response.sessionGeneration;
    _legacy = response.payload['state'] == 'legacySignedIn';
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> body,
  ) async {
    if (_account == null || _generation != _session.activeGeneration) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    try {
      final response = await _session.request(
        'hangarReader.$name',
        accountContext: _account,
        payload: {'schemaVersion': 1, ...body},
      );
      if (_generation != _session.activeGeneration ||
          !_sameAccount(response.accountContext, _account) ||
          response.payload['schemaVersion'] != 1) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      return response.payload;
    } on BridgeRemoteException catch (error) {
      throw LocalHangarFailure(error.code);
    }
  }

  @override
  Future<LocalHangarSnapshot> read() async {
    await _bind();
    final saved = await _collect(await _request('inventory', const {}));
    if (!_legacy || saved.revision > 0) return saved;
    // Only an absent new inventory may display the authenticated old profile.
    // A saved empty inventory and SCM-owned reads never take this route.
    final response = await _session.request(
      'personalProfile.getSelf',
      accountContext: _account,
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 60),
    );
    if (_generation != _session.activeGeneration ||
        response.sessionGeneration != _generation ||
        !_sameAccount(response.accountContext, _account) ||
        response.payload['schemaVersion'] != 1) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    return legacyProfileHangar(response.payload);
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    return _collect(
      await _request('save', {
        'operationId': operationId,
        'expectedRevision': expectedRevision,
        'confirmEmpty': confirmEmpty,
      }),
    );
  }

  Future<LocalHangarSnapshot> _collect(
    Map<String, Object?> first, {
    bool former = false,
  }) async {
    final revision = first['revision'] as int;
    final total = first['total'] as int;
    if (total < 0 || total > 20000 || revision < 0) {
      throw const LocalHangarFailure('hangar.invalid_inventory');
    }
    final ships = <LocalHangarShip>[];
    final ids = <String>{};
    var page = first;
    while (true) {
      if (page['revision'] != revision ||
          page['total'] != total ||
          (page['former'] == true) != former ||
          page['operationId'] != first['operationId']) {
        throw const LocalHangarFailure('hangar.revision_conflict');
      }
      final rows = (page['ships'] as List).cast<Map>();
      if (rows.length > 200 || ships.length + rows.length > total) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
      for (final row in rows) {
        final id = row['id'] as String, title = row['title'] as String;
        if (id.isEmpty || title.isEmpty || !ids.add(id)) {
          throw const LocalHangarFailure('hangar.invalid_inventory');
        }
        final names = row['names'] as Map? ?? const {};
        ships.add(
          LocalHangarShip(
            id: id,
            title: title,
            liner: row['liner'] as String?,
            cn: names['zhHans'] as String?,
            tw: names['zhHant'] as String?,
            size: row['combatSize'] as String?,
            addedAt: DateTime.tryParse(row['addedAt'] as String? ?? ''),
            removedAt: DateTime.tryParse(row['removedAt'] as String? ?? ''),
            catalogId: row['catalogId'] as String?,
            display: ShipReviewedDisplay.parse(row['display']),
            category: row['category'] as String?,
            sizeClass: row['sizeClass'] as String?,
            deliveryStatus: row['deliveryStatus'] as String?,
            priceUsd: row['priceUsd'] as num?,
            imageAsset: row['imageAsset'] as String?,
            thumbnailAsset: row['thumbnailAsset'] as String?,
          ),
        );
      }
      final next = page['nextOffset'] as int?;
      if (next == null) break;
      if (rows.isEmpty || next != ships.length || next >= total) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
      page = await _request('inventory', {
        'offset': next,
        'revision': revision,
        if (former) 'former': true,
      });
    }
    if (ships.length != total) {
      throw const LocalHangarFailure('hangar.invalid_inventory');
    }
    final formerTotal = first['formerTotal'] as int? ?? 0;
    if (formerTotal < 0 || formerTotal > 20000) {
      throw const LocalHangarFailure('hangar.invalid_inventory');
    }
    final history = !former && formerTotal > 0
        ? await _collect(
            await _request('inventory', {'revision': revision, 'former': true}),
            former: true,
          )
        : null;
    if (history != null &&
        (history.revision != revision ||
            history.operationId != first['operationId'] ||
            history.ships.length != formerTotal ||
            history.ships.any((s) => ids.contains(s.id)))) {
      throw const LocalHangarFailure('hangar.revision_conflict');
    }
    return LocalHangarSnapshot(
      revision: revision,
      ships: List.unmodifiable(ships),
      formerShips: history?.ships ?? const [],
      savedAt: DateTime.tryParse(first['savedAt'] as String? ?? ''),
      operationId: first['operationId'] as String?,
      partial: first['partial'] == true,
    );
  }
}
