import 'dart:math';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'local_hangar_port.dart';
import 'local_hangar_reconciliation.dart';
import 'ship_specifications_port.dart';
import 'local_hangar_images.dart';
import 'bridge_local_hangar_images.dart';
import 'legacy_profile_hangar.dart';
import 'hangar_read_diagnostics.dart';
import 'hangar_loading_metrics.dart';
import 'local_hangar_read_scope.dart';
import '../account/account_models.dart';

export 'hangar_loading_metrics.dart' show HangarReadOrigin;
import '../../shared/ships/ship_reviewed_display.dart';

final class BridgeLocalHangar
    implements
        LocalHangarPort,
        LocalHangarImageProvider,
        ShipSpecificationsProvider,
        LocalHangarFavoritesPort,
        LocalHangarPersonalDataPort,
        LocalHangarReadScopeSource,
        LocalHangarReconciliationPort,
        LocalHangarReadFailures {
  BridgeLocalHangar(
    this._session, {
    this.diagnosticCapture = HangarReadDiagnostics.enabled,
    this.readOrigin = HangarReadOrigin.unknown,
    this.displayHandoff,
  }) : _offlineRevision = null,
       _retainedReadId = null,
       _retainedCurrent = null;
  BridgeLocalHangar.offline(this._session, int modeRevision)
    : _offlineRevision = modeRevision,
      _retainedReadId = null,
      _retainedCurrent = null,
      displayHandoff = null,
      readOrigin = HangarReadOrigin.unknown,
      diagnosticCapture = false;
  BridgeLocalHangar.retained(
    this._session,
    String readId, {
    required bool Function() isCurrent,
  }) : _offlineRevision = null,
       _retainedReadId = readId,
       _retainedCurrent = isCurrent,
       displayHandoff = null,
       readOrigin = HangarReadOrigin.unknown,
       diagnosticCapture = false {
    _generation = _session.activeGeneration;
  }
  final int? _offlineRevision;
  final String? _retainedReadId;
  final bool Function()? _retainedCurrent;
  bool get _readOnly => _offlineRevision != null || _retainedReadId != null;
  final BridgeClientSession _session;
  final bool diagnosticCapture;
  final HangarReadOrigin readOrigin;
  final AccountDisplayHandoff? Function()? displayHandoff;
  AccountDisplayHandoff? _pendingProof;
  LocalHangarReadScope? _readScope;
  @override
  LocalHangarReadScope? get readScope =>
      !_session.connectionModeChanging &&
          _readScope?.generation == _session.activeGeneration
      ? _readScope
      : null;
  @override
  bool isTransientReadFailure(Object error) =>
      error is BridgeTimeoutException ||
      error is BridgeDisconnectedException ||
      isRecoverableLocalHangarRead(error);
  bool get _proofCurrent =>
      _pendingProof == null || displayHandoff?.call() == _pendingProof;
  Future<T> _diagnose<T>(HangarReadStage stage, Future<T> Function() action) =>
      HangarReadDiagnostics.capture(
        stage,
        () => observeHangarRead(readOrigin, stage, action),
        enabled: diagnosticCapture,
      );
  BridgeAccountContext? _account;
  int? _generation;
  bool _legacy = false;
  @override
  bool get specificationsAvailable =>
      !_readOnly && _session.hostCapabilities.contains('ships.specifications');

  @override
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  }) async {
    if (!specificationsAvailable ||
        _account == null ||
        _generation != _session.activeGeneration) {
      throw const LocalHangarFailure('ships.unavailable');
    }
    final account = _account, generation = _generation;
    final response = await _session.request(
      'ships.specifications',
      accountContext: account,
      payload: {'schemaVersion': 1, 'model': ship.title, 'refresh': refresh},
      timeout: const Duration(seconds: 25),
    );
    if (_generation != generation ||
        generation != _session.activeGeneration ||
        response.sessionGeneration != generation ||
        !_sameAccount(response.accountContext, account)) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    if (response.payload['schemaVersion'] != 1 ||
        response.payload['specifications'] is! Map) {
      throw const FormatException('Invalid specification response');
    }
    return ShipSpecifications.fromJson(
      Map<String, Object?>.from(response.payload['specifications'] as Map),
    );
  }

  @override
  bool get favoritesAvailable =>
      _offlineRevision == null &&
      _retainedReadId == null &&
      _session.hostCapabilities.contains('hangar.localFavorites');

  @override
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  ) async {
    if (!favoritesAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return _collect(
      await _request('favorite', {
        'shipId': shipId,
        'favorite': favorite,
        'expectedRevision': expectedRevision,
        'operationId': List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      }),
    );
  }

  @override
  LocalHangarImagePort? imageFor(String shipId, int revision) =>
      _account != null &&
          _generation == _session.activeGeneration &&
          revision > 0 &&
          _session.hostCapabilities.contains('hangar.localImages')
      ? BridgeLocalHangarImages(
          _session,
          _account!,
          _generation!,
          shipId,
          revision,
        )
      : null;
  static bool _sameAccount(BridgeAccountContext? a, BridgeAccountContext? b) =>
      a != null &&
      b != null &&
      a.environment == b.environment &&
      a.authority == b.authority &&
      a.subject == b.subject;

  Future<void> _bind() async {
    final expected = displayHandoff?.call();
    final response = await _session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 60),
    );
    if (response.payload['schemaVersion'] is! int ||
        !hasRelayAccount(response) ||
        response.accountContext == null ||
        response.sessionGeneration != _session.activeGeneration) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    final context = response.accountContext!;
    if (displayHandoff?.call() != expected ||
        expected != null &&
            (expected.generation != response.sessionGeneration ||
                !expected.matchesRoute(
                  AccountRoute(
                    environment: context.environment,
                    authority: context.authority,
                    subject: context.subject,
                  ),
                ))) {
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
    _pendingProof = expected;
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> body,
  ) async {
    if (_readOnly) {
      if (name != 'inventory') {
        throw const LocalHangarFailure('account.local_mode');
      }
      final generation = _session.activeGeneration;
      bool current() =>
          _retainedReadId == null ||
          (_generation == generation && _retainedCurrent!());
      if (!current()) throw const LocalHangarFailure('hangar.account_changed');
      final response = await _session.request(
        _retainedReadId == null
            ? 'onboarding.mode.hangar'
            : 'account.offlineData.read',
        payload: {
          'schemaVersion': 1,
          if (_retainedReadId == null) 'revision': _offlineRevision,
          if (_retainedReadId != null) ...{
            'readId': _retainedReadId,
            'kind': 'hangar',
          },
          if (body['revision'] != null) 'inventoryRevision': body['revision'],
          if (body['offset'] != null) 'offset': body['offset'],
          if (body['former'] != null) 'former': body['former'],
        },
      );
      if (!current() ||
          _session.activeGeneration != generation ||
          response.sessionGeneration != generation ||
          response.accountContext != null ||
          response.payload['schemaVersion'] is! int ||
          response.payload['schemaVersion'] != 1) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      return response.payload;
    }
    if (_account == null ||
        _generation != _session.activeGeneration ||
        !_proofCurrent) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    try {
      final response = await _session.request(
        'hangarReader.$name',
        accountContext: _account,
        payload: {'schemaVersion': 1, ...body},
      );
      if (_generation != _session.activeGeneration ||
          response.sessionGeneration != _generation ||
          !_proofCurrent ||
          !_sameAccount(response.accountContext, _account) ||
          response.payload['schemaVersion'] is! int ||
          response.payload['schemaVersion'] != 1) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      return response.payload;
    } on BridgeRemoteException catch (error) {
      throw LocalHangarFailure(error.code, retryable: error.retryable);
    }
  }

  @override
  Future<LocalHangarSnapshot> read() async {
    _readScope = null;
    final result = await _readInventory();
    if (!_readOnly) {
      final context = _account;
      if (context == null ||
          _generation != _session.activeGeneration ||
          !_proofCurrent) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      _readScope = LocalHangarReadScope(
        generation: _generation!,
        route: AccountRoute(
          environment: context.environment,
          authority: context.authority,
          subject: context.subject,
        ),
      );
      _pendingProof = null;
    }
    return result;
  }

  Future<LocalHangarSnapshot> _readInventory() async {
    if (_readOnly) {
      return _collect(await _request('inventory', const {}));
    }
    await _diagnose(HangarReadStage.bind, _bind);
    final first = await _diagnose(
      HangarReadStage.inventory,
      () => _request('inventory', const {}),
    );
    final saved = await _diagnose(
      HangarReadStage.inventoryProjection,
      () => _collect(first),
    );
    if (!_legacy || saved.revision > 0) return saved;
    // Only an absent new inventory may display the authenticated old profile.
    // A saved empty inventory and SCM-owned reads never take this route.
    final response = await _diagnose(
      HangarReadStage.legacyRead,
      () => _session.request(
        'personalProfile.getSelf',
        accountContext: _account,
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 60),
      ),
    );
    return _diagnose(HangarReadStage.legacyProjection, () async {
      if (_generation != _session.activeGeneration ||
          response.sessionGeneration != _generation ||
          !_sameAccount(response.accountContext, _account) ||
          response.payload['schemaVersion'] != 1) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      // An optional profile display is not authoritative local inventory. Keep
      // the successful local read when that display is absent; do not save,
      // migrate, or reinterpret a malformed/failed response as an empty hangar.
      return legacyProfileHangar(response.payload) ?? saved;
    });
  }

  @override
  bool get personalDataAvailable =>
      !_readOnly &&
      _session.hostCapabilities.contains('hangar.localPersonalData');

  @override
  Future<LocalHangarSnapshot> readPersonalDataReceipt() async {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return read();
  }

  @override
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  }) async {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return _collect(
      await _request('personalData', {
        'operationId': operationId,
        'expectedRevision': expectedRevision,
        'shipId': shipId,
        'nickname': nickname,
        'notes': notes,
      }),
    );
  }

  @override
  bool get reconciliationAvailable =>
      !_readOnly &&
      _session.hostCapabilities.contains('hangar.localReconciliation');

  @override
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  ) async {
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    final rows = <Map>[];
    int? total;
    while (true) {
      final page = await _request('removals', {
        'operationId': operationId,
        'expectedRevision': expectedRevision,
        'offset': rows.length,
      });
      final pageTotal = page['total'];
      if (page['revision'] != expectedRevision ||
          page['operationId'] != operationId ||
          pageTotal is! int ||
          pageTotal < 0 ||
          pageTotal > 20000 ||
          (total != null && total != pageTotal) ||
          page['rows'] is! List) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
      total = pageTotal;
      final batch = (page['rows'] as List).cast<Map>();
      if (batch.length > 200 || rows.length + batch.length > total) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
      rows.addAll(batch);
      if (page['nextOffset'] == null) break;
      if (batch.isEmpty ||
          page['nextOffset'] != rows.length ||
          rows.length >= total) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
    }
    if (rows.length != total) {
      throw const LocalHangarFailure('hangar.invalid_inventory');
    }
    final groups = <String, List<String>>{},
        required = <String, int>{},
        sizes = <String, int>{};
    final ids = <String>{};
    for (final row in rows) {
      final group = row['groupId'],
          id = row['shipId'],
          count = row['requiredCount'],
          size = row['groupSize'];
      if (group is! String ||
          group.isEmpty ||
          id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          count is! int ||
          size is! int ||
          count < 1 ||
          count >= size ||
          size > 20000 ||
          (required[group] != null && required[group] != count) ||
          (sizes[group] != null && sizes[group] != size)) {
        throw const LocalHangarFailure('hangar.invalid_inventory');
      }
      required[group] = count;
      sizes[group] = size;
      (groups[group] ??= []).add(id);
    }
    return groups.entries
        .map((g) {
          if (g.value.length != sizes[g.key] || !g.value.contains(g.key)) {
            throw const LocalHangarFailure('hangar.invalid_inventory');
          }
          return LocalHangarRemovalGroup(
            id: g.key,
            requiredCount: required[g.key]!,
            shipIds: List.unmodifiable(g.value),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  }) async {
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return _collect(
      await _request('save', {
        'operationId': operationId,
        'expectedRevision': expectedRevision,
        'confirmEmpty': confirmEmpty,
        'removedShipIds': removedShipIds,
      }),
    );
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
            isFavorite: row['isFavorite'] == true,
            nickname: row['nickname'] as String?,
            notes: row['notes'] as String?,
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
      inventorySavedAt: DateTime.tryParse(
        first['inventorySavedAt'] as String? ?? '',
      ),
      operationId: first['operationId'] as String?,
      partial: first['partial'] == true,
    );
  }
}
