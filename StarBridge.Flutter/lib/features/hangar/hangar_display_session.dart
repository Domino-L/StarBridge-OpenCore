import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import '../communities/community_logo_port.dart';
import 'local_hangar_images.dart';
import 'local_hangar_port.dart';
import 'local_hangar_reconciliation.dart';
import 'local_hangar_read_scope.dart';
import 'ship_specifications_port.dart';
import 'local_hangar_view_state.dart';
export 'local_hangar_view_state.dart';

/// Bounded presentation across one proven restore. Business IO remains with
/// the original readonly selection and the newly scoped local inventory owner.
final class HangarDisplaySession extends ChangeNotifier
    implements
        LocalHangarPort,
        LocalHangarImageProvider,
        LocalHangarFavoritesPort,
        LocalHangarPersonalDataPort,
        LocalHangarReconciliationPort,
        ShipSpecificationsProvider,
        LocalHangarViewSource {
  HangarDisplaySession({
    required this.account,
    required this.retainedFactory,
    required this.localFactory,
    this.mode,
  }) {
    account.addListener(_reconcile);
    mode?.addListener(_reconcile);
    _reconcile();
  }
  final ValueListenable<AccountProjection> account;
  final LocalHangarPort Function(String) retainedFactory;
  final LocalHangarPort Function() localFactory;
  final ConnectionModeControl? mode;
  LocalHangarPort? _source;
  LocalHangarSnapshot? _snapshot;
  ({int generation, String id, Object mode})? _selection;
  AccountDisplayHandoff? _proof;
  Object? _freshKey, _confirmedMode;
  int? _confirmedGeneration;
  Future<LocalHangarSnapshot>? _pending;
  int _epoch = 0, _mediaEpoch = 0, _writeEpoch = 0;
  bool _disposed = false,
      _activated = false,
      _retained = false,
      _materialized = false,
      _reading = false,
      _waiting = false;
  bool failed = false;
  @override
  int viewEpoch = 0;
  int contentEpoch = 0;
  @override
  LocalHangarViewState view = LocalHangarViewState();
  LocalHangarSnapshot? get snapshot => _snapshot;
  bool get canDisplay => !_disposed && (_source != null || _snapshot != null);
  bool get refreshing => _reading || _waiting;
  bool get canRefresh =>
      !_disposed &&
      _source != null &&
      (_retained
          ? account.value.hasRetainedDisplayRead
          : _online && account.value.isSignedIn);
  bool get _online =>
      mode == null || !mode!.failed && mode!.allowsOnlineTraffic;
  Object _mode({ConnectionModeSnapshot? snapshot, Object? scope}) => (
    scope ?? snapshot?.scope ?? mode?.snapshot.scope,
    snapshot?.revision ?? mode?.snapshot.revision,
    snapshot?.state ?? mode?.snapshot.state,
    mode?.failed,
    (snapshot ?? mode?.snapshot)?.offlineAccount?.displayName,
    (snapshot ?? mode?.snapshot)?.offlineAccount?.cachedAtUtc,
  );

  bool _sameDisplayMode(AccountDisplayHandoff proof, Object original) {
    if (_online &&
        (original == _mode() ||
            mode?.snapshot.scope == proof.generation &&
                original == _mode(scope: proof.sourceGeneration))) {
      return true;
    }
    final control = mode;
    final continuity = control is ConnectionModeDisplayContinuitySource
        ? (control as ConnectionModeDisplayContinuitySource).displayContinuity
        : null;
    return control != null &&
        !control.failed &&
        control.snapshot.state == ConnectionModeState.unavailable &&
        continuity != null &&
        continuity.sourceGeneration == proof.sourceGeneration &&
        continuity.generation == proof.generation &&
        original ==
            _mode(
              snapshot: ConnectionModeSnapshot(
                scope: continuity.sourceGeneration,
                revision: continuity.revision,
                state: ConnectionModeState.online,
              ),
            );
  }

  bool get _confirmedOwner =>
      !_disposed &&
      _online &&
      account.value.isSignedIn &&
      account.value.generation == _confirmedGeneration &&
      _confirmedMode == _mode();
  bool get confirmed {
    final source = _source, proof = _proof;
    return _confirmedOwner &&
        source is LocalHangarReadScopeSource &&
        proof != null &&
        (source as LocalHangarReadScopeSource).readScope?.matches(proof) ==
            true;
  }

  void _retireSource() {
    ++_epoch;
    ++_mediaEpoch;
    _pending = null;
    _source = null;
    _reading = false;
    _freshKey = null;
  }

  void _clear() {
    _retireSource();
    _snapshot = null;
    _selection = null;
    _proof = null;
    _confirmedGeneration = null;
    _confirmedMode = null;
    _materialized = false;
    _retained = false;
    _waiting = false;
    failed = false;
    view = LocalHangarViewState();
    ++viewEpoch;
    ++contentEpoch;
  }

  void _readIfActive() {
    if (_activated && canRefresh) {
      unawaited(read().then<void>((_) {}, onError: (Object _) {}));
    }
  }

  void _reconcile() {
    if (_disposed) return;
    final current = account.value;
    final candidate = current.hasDisplayHandoff ? current.displayHandoff : null;
    final previous = _proof;
    if (candidate != null &&
        previous != null &&
        (candidate.displayKey != previous.displayKey ||
            candidate.sourceGeneration != previous.sourceGeneration ||
            !candidate.matchesRoute(previous.route))) {
      _clear();
      notifyListeners();
      return;
    }
    if (current.hasRetainedDisplayRead && _online) {
      final selection = (
        generation: current.generation,
        id: current.retainedReadId!,
        mode: _mode(),
      );
      if (_retained && _selection == selection) return;
      _clear();
      _selection = selection;
      _retained = true;
      _source = retainedFactory(selection.id);
      notifyListeners();
      _readIfActive();
      return;
    }
    // Once a qualified fresh domain read replaced the cache, removal of the
    // presentation proof alone does not invalidate that confirmed inventory.
    if (_confirmedOwner) return;
    final proof = current.hasDisplayHandoff ? current.displayHandoff : null;
    final selection = _selection;
    if (proof != null &&
        selection != null &&
        _materialized &&
        _snapshot != null &&
        proof.displayKey == selection.id &&
        proof.sourceGeneration == selection.generation &&
        _sameDisplayMode(proof, selection.mode)) {
      _proof = proof;
      if (_retained) {
        _retireSource();
        _retained = false;
      }
      _waiting = true;
      if (_online &&
          current.isSignedIn &&
          current.generation == proof.generation) {
        final key = (current.generation, _mode());
        if (key != _freshKey) {
          _retireSource();
          _freshKey = key;
          _source = localFactory();
          notifyListeners();
          _readIfActive();
          return;
        }
      } else if (_source != null) {
        _retireSource();
      }
      notifyListeners();
      return;
    }
    if (canDisplay || _selection != null) {
      _clear();
      notifyListeners();
    }
  }

  @override
  Future<LocalHangarSnapshot> read() {
    _activated = true;
    if (!canRefresh) {
      final cached = _snapshot;
      return cached != null && canDisplay
          ? Future.value(cached)
          : Future.error(const LocalHangarFailure('hangar.account_changed'));
    }
    return _pending ??= _read(_source!, _epoch);
  }

  Future<LocalHangarSnapshot> _read(LocalHangarPort source, int epoch) async {
    final writesAtStart = _writeEpoch;
    _reading = true;
    failed = false;
    // First activation may originate in a child's initState. Notify after
    // that build so its owning HangarPage is never dirtied mid-rebuild.
    scheduleMicrotask(() {
      if (!_disposed && epoch == _epoch) notifyListeners();
    });
    try {
      final result = await source.read();
      if (_disposed ||
          epoch != _epoch ||
          !identical(source, _source) ||
          !canRefresh) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      // A refresh admitted before a local edit cannot roll back its receipt or
      // invalidate its still-current image leases when that old read arrives.
      if (writesAtStart != _writeEpoch &&
          confirmed &&
          _snapshot != null &&
          result.revision <= _snapshot!.revision) {
        _reading = false;
        notifyListeners();
        return _snapshot!;
      }
      if (!_retained) {
        final proof = _proof;
        final receipt = source is LocalHangarReadScopeSource
            ? (source as LocalHangarReadScopeSource).readScope
            : null;
        if (proof == null ||
            receipt?.matches(proof) != true ||
            account.value.generation != proof.generation ||
            !account.value.isSignedIn) {
          throw const LocalHangarFailure('hangar.account_changed');
        }
        _confirmedGeneration = proof.generation;
        _confirmedMode = _mode();
        _waiting = false;
        ++_mediaEpoch;
        ++contentEpoch;
      } else {
        _materialized = true;
      }
      _snapshot = LocalHangarSnapshot(
        revision: result.revision,
        ships: List.unmodifiable(result.ships),
        formerShips: List.unmodifiable(result.formerShips),
        savedAt: result.savedAt,
        inventorySavedAt: result.inventorySavedAt,
        operationId: result.operationId,
        partial: result.partial,
        fromLegacyProfile: result.fromLegacyProfile,
      );
      _reading = false;
      notifyListeners();
      return _snapshot!;
    } catch (error) {
      final transientAfterWrite = source is LocalHangarReadFailures
          ? (source as LocalHangarReadFailures).isTransientReadFailure(error)
          : isRecoverableLocalHangarRead(error);
      if (transientAfterWrite &&
          !_disposed &&
          epoch == _epoch &&
          writesAtStart != _writeEpoch &&
          confirmed &&
          _snapshot != null) {
        _reading = false;
        notifyListeners();
        return _snapshot!;
      }
      if (!_disposed && epoch == _epoch) {
        _reading = false;
        _waiting = false;
        failed = true;
        final transient = source is LocalHangarReadFailures
            ? (source as LocalHangarReadFailures).isTransientReadFailure(error)
            : isRecoverableLocalHangarRead(error);
        if (!transient) {
          _snapshot = null;
          _materialized = false;
          _confirmedGeneration = null;
          ++_mediaEpoch;
          ++viewEpoch;
          ++contentEpoch;
          view = LocalHangarViewState();
        }
        notifyListeners();
      }
      rethrow;
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  void _requireConfirmed([int? mediaEpoch]) {
    if (!confirmed || mediaEpoch != null && mediaEpoch != _mediaEpoch) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
  }

  @override
  bool get favoritesAvailable =>
      confirmed &&
      _source is LocalHangarFavoritesPort &&
      (_source as LocalHangarFavoritesPort).favoritesAvailable;
  @override
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  ) async {
    _requireConfirmed();
    if (!favoritesAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    final source = _source!, epoch = _epoch;
    final result = await (source as LocalHangarFavoritesPort).setFavorite(
      shipId,
      favorite,
      expectedRevision,
    );
    _requireConfirmed();
    if (epoch != _epoch || !identical(source, _source)) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    _snapshot = result;
    ++_writeEpoch;
    notifyListeners();
    return result;
  }

  @override
  bool get personalDataAvailable =>
      confirmed &&
      _source is LocalHangarPersonalDataPort &&
      (_source as LocalHangarPersonalDataPort).personalDataAvailable;
  @override
  Future<LocalHangarSnapshot> readPersonalDataReceipt() => _save((source) {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (source as LocalHangarPersonalDataPort).readPersonalDataReceipt();
  });
  @override
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  }) => _save((source) {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (source as LocalHangarPersonalDataPort).savePersonalData(
      shipId,
      nickname,
      notes,
      expectedRevision,
      operationId: operationId,
    );
  });

  @override
  bool get reconciliationAvailable =>
      confirmed &&
      _source is LocalHangarReconciliationPort &&
      (_source as LocalHangarReconciliationPort).reconciliationAvailable;

  @override
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  ) async {
    _requireConfirmed();
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    final source = _source!, epoch = _epoch;
    final groups = await (source as LocalHangarReconciliationPort)
        .previewRemovals(operationId, expectedRevision);
    _requireConfirmed();
    if (epoch != _epoch || !identical(source, _source)) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    return groups;
  }

  @override
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  }) => _save((source) {
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (source as LocalHangarReconciliationPort).saveResolved(
      operationId,
      expectedRevision,
      removedShipIds: removedShipIds,
      confirmEmpty: confirmEmpty,
    );
  });

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => _save(
    (source) =>
        source.save(operationId, expectedRevision, confirmEmpty: confirmEmpty),
  );

  Future<LocalHangarSnapshot> _save(
    Future<LocalHangarSnapshot> Function(LocalHangarPort) action,
  ) async {
    _requireConfirmed();
    final source = _source!, epoch = _epoch;
    final result = await action(source);
    _requireConfirmed();
    if (epoch != _epoch || !identical(source, _source)) {
      throw const LocalHangarFailure('hangar.account_changed');
    }
    _snapshot = result;
    ++_writeEpoch;
    notifyListeners();
    return result;
  }

  @override
  bool get specificationsAvailable =>
      confirmed &&
      _source is ShipSpecificationsProvider &&
      (_source as ShipSpecificationsProvider).specificationsAvailable;
  @override
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  }) async {
    _requireConfirmed();
    final epoch = _mediaEpoch;
    if (!specificationsAvailable) {
      throw const LocalHangarFailure('ships.unavailable');
    }
    final result = await (_source as ShipSpecificationsProvider)
        .specificationsFor(ship, refresh: refresh);
    _requireConfirmed(epoch);
    return result;
  }

  @override
  LocalHangarImagePort? imageFor(String shipId, int revision) {
    if (!confirmed || _source is! LocalHangarImageProvider) return null;
    final port = (_source as LocalHangarImageProvider).imageFor(
      shipId,
      revision,
    );
    if (port == null) return null;
    final epoch = _mediaEpoch;
    return _ScopedHangarImage(port, () => _requireConfirmed(epoch));
  }

  void invalidateAfterImageSave() {
    _requireConfirmed();
    ++contentEpoch;
    ++_mediaEpoch;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retireSource();
    _snapshot = null;
    account.removeListener(_reconcile);
    mode?.removeListener(_reconcile);
    super.dispose();
  }
}

final class _ScopedHangarImage implements LocalHangarImagePort {
  _ScopedHangarImage(this._source, this._check);
  final LocalHangarImagePort _source;
  final void Function() _check;
  Future<T> _run<T>(Future<T> Function() action) async {
    _check();
    final value = await action();
    _check();
    return value;
  }

  @override
  Future<String?> readImage() => _run(_source.readImage);
  @override
  Future<void> saveImage() => _run(_source.saveImage);
  @override
  Future<void> restoreImage() => _run(_source.restoreImage);
  @override
  bool get canPickLogo {
    try {
      _check();
      return _source.canPickLogo;
    } on LocalHangarFailure {
      return false;
    }
  }

  @override
  Future<CommunityLogoSource?> pickLogo() => _run(_source.pickLogo);
  @override
  Future<String> cropLogo(String sourceRef, double x, double y, double size) =>
      _run(() => _source.cropLogo(sourceRef, x, y, size));
  @override
  Future<void> clearLogo() => _run(_source.clearLogo);
}
