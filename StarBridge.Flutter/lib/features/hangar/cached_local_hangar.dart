import 'local_hangar_port.dart';

/// One authenticated feature lifetime, not a global or cross-account cache.
/// Reads remain explicit fresh reads; pages may synchronously reuse [snapshot].
final class CachedLocalHangar implements LocalHangarPort {
  CachedLocalHangar(this._source, {required this.isCurrent});
  final LocalHangarPort _source;
  final bool Function() isCurrent;
  LocalHangarSnapshot? _snapshot;
  Future<LocalHangarSnapshot>? _pending;
  int _epoch = 0;

  LocalHangarSnapshot? get snapshot => isCurrent() ? _snapshot : null;

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
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    _check();
    final epoch = ++_epoch;
    _pending = null;
    final value = await _source.save(
      operationId,
      expectedRevision,
      confirmEmpty: confirmEmpty,
    );
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
