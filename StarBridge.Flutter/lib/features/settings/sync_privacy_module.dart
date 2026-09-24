import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_privacy_models.dart';
import 'sync_privacy_port.dart';

abstract interface class SyncPrivacyModule {
  ValueListenable<SyncPrivacyProjection> get projection;

  Future<void> initialize();
  Future<void> refresh();
  Future<bool> save(SyncPrivacySettingsValue settings);
  void dispose();
}

SyncPrivacyModule createSyncPrivacyModule(SyncPrivacyPort port) =>
    _DefaultSyncPrivacyModule(port);

final class _DefaultSyncPrivacyModule implements SyncPrivacyModule {
  _DefaultSyncPrivacyModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        // Invalidation is a context barrier, not a request to wait behind an
        // old account's pending operation. Late replies cannot cross it.
        _epoch++;
        _reading = false;
        _refreshPending = false;
        _projection.value = const SyncPrivacyProjection.loading();
        unawaited(refresh());
      }
    });
  }

  final SyncPrivacyPort _port;
  final ValueNotifier<SyncPrivacyProjection> _projection = ValueNotifier(
    const SyncPrivacyProjection.loading(),
  );
  late final StreamSubscription<void> _subscription;
  bool _initialized = false;
  bool _reading = false;
  bool _refreshPending = false;
  bool _disposed = false;
  int _epoch = 0;

  @override
  ValueListenable<SyncPrivacyProjection> get projection => _projection;

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (_reading ||
        _projection.value.operation == SyncPrivacyOperation.saving) {
      _refreshPending = true;
      return;
    }
    _reading = true;
    final epoch = _epoch;
    final previous = _projection.value;
    _projection.value = previous.settings == null
        ? const SyncPrivacyProjection.loading()
        : previous.copyWith(operation: SyncPrivacyOperation.refreshing);
    SyncPrivacySnapshot snapshot;
    try {
      snapshot = await _port.read();
    } catch (_) {
      snapshot = const SyncPrivacySnapshot.unavailable(
        failure: SyncPrivacyFailure.readFailed,
      );
    }
    if (_disposed || epoch != _epoch) {
      return;
    }
    _reading = false;
    _projection.value =
        snapshot.availability == SyncPrivacyAvailability.unavailable &&
            previous.settings != null
        ? previous.copyWith(
            operation: SyncPrivacyOperation.none,
            allowEditing: false,
            failure: snapshot.failure,
          )
        : SyncPrivacyProjection.fromSnapshot(snapshot);
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  @override
  Future<bool> save(SyncPrivacySettingsValue settings) async {
    final current = _projection.value;
    final revision = current.revision;
    if (_disposed || !current.canEdit || revision == null) {
      return false;
    }
    _projection.value = current.copyWith(
      operation: SyncPrivacyOperation.saving,
      clearFailure: true,
    );
    final epoch = _epoch;
    SyncPrivacyWriteResult result;
    try {
      result = await _port.update(settings, expectedRevision: revision);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        // The write may have reached its owner. Keep the last confirmed values
        // read-only until a fresh read; never retry the mutation automatically.
        _projection.value = current.copyWith(
          operation: SyncPrivacyOperation.none,
          allowEditing: false,
          failure: SyncPrivacyFailure.writeFailed,
        );
        unawaited(refresh());
      }
      return false;
    }
    if (_disposed || epoch != _epoch) {
      return false;
    }
    final updated = result.snapshot;
    if (result.outcome == SyncPrivacyWriteOutcome.completed &&
        updated != null) {
      _projection.value = SyncPrivacyProjection.fromSnapshot(updated);
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refresh());
      }
      return true;
    }
    _projection.value = current.copyWith(
      operation: SyncPrivacyOperation.none,
      allowEditing: result.failure == SyncPrivacyFailure.writeConflict
          ? false
          : current.allowEditing,
      failure: result.failure ?? SyncPrivacyFailure.writeFailed,
    );
    if (_refreshPending || result.failure == SyncPrivacyFailure.writeConflict) {
      _refreshPending = false;
      unawaited(refresh());
    }
    return false;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _epoch++;
    unawaited(_subscription.cancel());
    _projection.dispose();
    unawaited(_port.close());
  }
}
