import 'dart:async';

import 'package:flutter/foundation.dart';

enum RecentlyPlayedPrivacyAvailability {
  loading,
  available,
  signedOut,
  unavailable,
}

enum RecentlyPlayedPrivacyOperation { none, saving }

enum RecentlyPlayedPrivacyFailure {
  hostUnavailable,
  identityUnavailable,
  readFailed,
  writeFailed,
  writeConflict,
  invalidResponse,
  outcomeUnknown,
}

@immutable
final class RecentlyPlayedPrivacySnapshot {
  const RecentlyPlayedPrivacySnapshot.loading()
    : availability = RecentlyPlayedPrivacyAvailability.loading,
      enabled = null,
      enabledAt = null,
      disabledAt = null,
      revision = null,
      failure = null;

  const RecentlyPlayedPrivacySnapshot.signedOut()
    : availability = RecentlyPlayedPrivacyAvailability.signedOut,
      enabled = null,
      enabledAt = null,
      disabledAt = null,
      revision = null,
      failure = null;

  const RecentlyPlayedPrivacySnapshot.unavailable(this.failure)
    : availability = RecentlyPlayedPrivacyAvailability.unavailable,
      enabled = null,
      enabledAt = null,
      disabledAt = null,
      revision = null;

  const RecentlyPlayedPrivacySnapshot.available({
    required this.enabled,
    required this.enabledAt,
    required this.disabledAt,
    required this.revision,
  }) : availability = RecentlyPlayedPrivacyAvailability.available,
       failure = null;

  final RecentlyPlayedPrivacyAvailability availability;
  final bool? enabled;
  final DateTime? enabledAt;
  final DateTime? disabledAt;
  final int? revision;
  final RecentlyPlayedPrivacyFailure? failure;
}

enum RecentlyPlayedPrivacyWriteOutcome { completed, rejected, unknown }

@immutable
final class RecentlyPlayedPrivacyWriteResult {
  const RecentlyPlayedPrivacyWriteResult.completed(this.snapshot)
    : outcome = RecentlyPlayedPrivacyWriteOutcome.completed,
      failure = null;
  const RecentlyPlayedPrivacyWriteResult.rejected(this.failure)
    : outcome = RecentlyPlayedPrivacyWriteOutcome.rejected,
      snapshot = null;
  const RecentlyPlayedPrivacyWriteResult.unknown()
    : outcome = RecentlyPlayedPrivacyWriteOutcome.unknown,
      snapshot = null,
      failure = RecentlyPlayedPrivacyFailure.outcomeUnknown;

  final RecentlyPlayedPrivacyWriteOutcome outcome;
  final RecentlyPlayedPrivacySnapshot? snapshot;
  final RecentlyPlayedPrivacyFailure? failure;
}

abstract interface class RecentlyPlayedPrivacyPort {
  Stream<void> get invalidations;
  Future<RecentlyPlayedPrivacySnapshot> read();
  Future<RecentlyPlayedPrivacyWriteResult> save(
    bool enabled,
    int expectedRevision,
  );
  Future<void> close();
}

@immutable
final class RecentlyPlayedPrivacyProjection {
  const RecentlyPlayedPrivacyProjection({
    required this.snapshot,
    this.operation = RecentlyPlayedPrivacyOperation.none,
    this.failure,
  });

  final RecentlyPlayedPrivacySnapshot snapshot;
  final RecentlyPlayedPrivacyOperation operation;
  final RecentlyPlayedPrivacyFailure? failure;

  bool get canEdit =>
      snapshot.availability == RecentlyPlayedPrivacyAvailability.available &&
      operation == RecentlyPlayedPrivacyOperation.none;
}

final class RecentlyPlayedPrivacyModule {
  RecentlyPlayedPrivacyModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      // Identity invalidation must never retain another account's settings.
      _epoch++;
      _reading = false;
      _busy = false;
      _refreshPending = false;
      projection.value = const RecentlyPlayedPrivacyProjection(
        snapshot: RecentlyPlayedPrivacySnapshot.loading(),
      );
      unawaited(refresh());
    });
  }

  final RecentlyPlayedPrivacyPort _port;
  final ValueNotifier<RecentlyPlayedPrivacyProjection> projection =
      ValueNotifier(
        const RecentlyPlayedPrivacyProjection(
          snapshot: RecentlyPlayedPrivacySnapshot.loading(),
        ),
      );
  late final StreamSubscription<void> _subscription;
  bool _initialized = false;
  bool _busy = false;
  bool _reading = false;
  int _epoch = 0;
  bool _refreshPending = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_busy) {
      _refreshPending = true;
      return;
    }
    if (_reading) return;
    _reading = true;
    final epoch = _epoch;
    final snapshot = await _port.read();
    if (_disposed || epoch != _epoch) return;
    _reading = false;
    projection.value = RecentlyPlayedPrivacyProjection(
      snapshot: snapshot,
      failure: snapshot.failure,
    );
    _drainRefresh();
  }

  Future<bool> save(bool enabled) async {
    final current = projection.value;
    final revision = current.snapshot.revision;
    if (_disposed || _busy || !current.canEdit || revision == null) {
      return false;
    }
    _busy = true;
    // Saves take precedence; a late background response cannot undo a receipt.
    final epoch = ++_epoch;
    _reading = false;
    projection.value = RecentlyPlayedPrivacyProjection(
      snapshot: current.snapshot,
      operation: RecentlyPlayedPrivacyOperation.saving,
    );
    final result = await _port.save(enabled, revision);
    if (_disposed || epoch != _epoch) return false;
    _busy = false;
    final updated = result.snapshot;
    if (result.outcome == RecentlyPlayedPrivacyWriteOutcome.completed &&
        updated != null) {
      projection.value = RecentlyPlayedPrivacyProjection(snapshot: updated);
      _drainRefresh();
      return true;
    }
    projection.value = RecentlyPlayedPrivacyProjection(
      snapshot: current.snapshot,
      failure: result.failure ?? RecentlyPlayedPrivacyFailure.writeFailed,
    );
    _drainRefresh();
    return false;
  }

  void _drainRefresh() {
    if (!_refreshPending) return;
    _refreshPending = false;
    unawaited(refresh());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    projection.dispose();
    unawaited(_port.close());
  }
}
