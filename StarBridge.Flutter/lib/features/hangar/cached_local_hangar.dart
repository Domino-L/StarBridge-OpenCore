import 'local_hangar_port.dart';
import 'local_hangar_reconciliation.dart';
import 'local_hangar_images.dart';
import 'ship_specifications_port.dart';
import 'local_hangar_read_scope.dart';
import 'local_hangar_view_state.dart';

/// One authenticated feature lifetime, not a global or cross-account cache.
/// Reads remain explicit fresh reads; pages may synchronously reuse [snapshot].
final class CachedLocalHangar
    implements
        LocalHangarPort,
        LocalHangarImageProvider,
        ShipSpecificationsProvider,
        LocalHangarFavoritesPort,
        LocalHangarPersonalDataPort,
        LocalHangarReadScopeSource,
        LocalHangarReadFailures,
        LocalHangarReconciliationPort,
        LocalHangarViewSource {
  CachedLocalHangar(this._source, {required this.isCurrent});
  final LocalHangarPort _source;
  final bool Function() isCurrent;
  LocalHangarSnapshot? _snapshot;
  Future<LocalHangarSnapshot>? _pending;
  int _epoch = 0;
  final _view = LocalHangarViewState();
  @override
  LocalHangarViewState get view => isCurrent() ? _view : LocalHangarViewState();
  @override
  int get viewEpoch => 0;

  LocalHangarSnapshot? get snapshot => isCurrent() ? _snapshot : null;
  @override
  bool isTransientReadFailure(Object error) =>
      isCurrent() &&
      (_source is LocalHangarReadFailures
          ? (_source as LocalHangarReadFailures).isTransientReadFailure(error)
          : isRecoverableLocalHangarRead(error));
  @override
  LocalHangarReadScope? get readScope =>
      isCurrent() && _source is LocalHangarReadScopeSource
      ? (_source as LocalHangarReadScopeSource).readScope
      : null;
  @override
  bool get specificationsAvailable =>
      isCurrent() &&
      _source is ShipSpecificationsProvider &&
      (_source as ShipSpecificationsProvider).specificationsAvailable;

  @override
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  }) async {
    _check();
    if (!specificationsAvailable) {
      throw const LocalHangarFailure('ships.unavailable');
    }
    final result = await (_source as ShipSpecificationsProvider)
        .specificationsFor(ship, refresh: refresh);
    _check();
    return result;
  }

  @override
  bool get favoritesAvailable =>
      isCurrent() &&
      _source is LocalHangarFavoritesPort &&
      (_source as LocalHangarFavoritesPort).favoritesAvailable;

  @override
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  ) async {
    _check();
    if (!favoritesAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    final epoch = ++_epoch;
    _pending = null;
    final value = await (_source as LocalHangarFavoritesPort).setFavorite(
      shipId,
      favorite,
      expectedRevision,
    );
    _check();
    if (epoch == _epoch) {
      ++_epoch;
      _pending = null;
      _snapshot = value;
    }
    return value;
  }

  @override
  LocalHangarImagePort? imageFor(String shipId, int revision) {
    _check();
    final source = _source;
    return source is LocalHangarImageProvider
        ? (source as LocalHangarImageProvider).imageFor(shipId, revision)
        : null;
  }

  void invalidateAfterImageSave() {
    _check();
    ++_epoch;
    _pending = null;
    _snapshot = null;
  }

  void _check() {
    if (!isCurrent()) {
      _snapshot = null;
      throw const LocalHangarFailure('hangar.account_changed');
    }
  }

  @override
  Future<LocalHangarSnapshot> read() {
    _check();
    return _pending ??= _read(_epoch);
  }

  Future<LocalHangarSnapshot> _read(int epoch) async {
    try {
      final value = await Future<LocalHangarSnapshot>.sync(_source.read);
      _check();
      if (epoch != _epoch) {
        if (_snapshot != null) return _snapshot!;
        throw const LocalHangarFailure('hangar.inventory_changed');
      }
      _snapshot = value;
      return value;
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  bool get personalDataAvailable =>
      isCurrent() &&
      _source is LocalHangarPersonalDataPort &&
      (_source as LocalHangarPersonalDataPort).personalDataAvailable;
  @override
  Future<LocalHangarSnapshot> readPersonalDataReceipt() => _save(() {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (_source as LocalHangarPersonalDataPort).readPersonalDataReceipt();
  });
  @override
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  }) => _save(() {
    if (!personalDataAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (_source as LocalHangarPersonalDataPort).savePersonalData(
      shipId,
      nickname,
      notes,
      expectedRevision,
      operationId: operationId,
    );
  });

  @override
  bool get reconciliationAvailable =>
      isCurrent() &&
      _source is LocalHangarReconciliationPort &&
      (_source as LocalHangarReconciliationPort).reconciliationAvailable;

  @override
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  ) async {
    _check();
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    final groups = await (_source as LocalHangarReconciliationPort)
        .previewRemovals(operationId, expectedRevision);
    _check();
    return groups;
  }

  @override
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  }) => _save(() {
    if (!reconciliationAvailable) {
      throw const LocalHangarFailure('hangar.unavailable');
    }
    return (_source as LocalHangarReconciliationPort).saveResolved(
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
    () =>
        _source.save(operationId, expectedRevision, confirmEmpty: confirmEmpty),
  );

  Future<LocalHangarSnapshot> _save(
    Future<LocalHangarSnapshot> Function() action,
  ) async {
    _check();
    final epoch = ++_epoch;
    _pending = null;
    final value = await action();
    _check();
    if (epoch == _epoch) {
      // A concurrent older inventory read must not overwrite the saved scan.
      ++_epoch;
      _pending = null;
      _snapshot = value;
    }
    return value;
  }
}
