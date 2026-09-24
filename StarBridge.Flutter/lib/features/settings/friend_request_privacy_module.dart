import 'dart:async';

import 'package:flutter/foundation.dart';

enum FriendRequestPrivacyAvailability {
  loading,
  available,
  signedOut,
  unavailable,
}

enum FriendRequestPrivacyOperation { none, saving }

enum FriendRequestPrivacyFailure {
  hostUnavailable,
  identityUnavailable,
  readFailed,
  writeFailed,
  invalidResponse,
  outcomeUnknown,
}

@immutable
final class FriendRequestPrivacySnapshot {
  const FriendRequestPrivacySnapshot.loading()
    : availability = FriendRequestPrivacyAvailability.loading,
      allowFriendRequests = null,
      updatedAt = null,
      failure = null;

  const FriendRequestPrivacySnapshot.signedOut()
    : availability = FriendRequestPrivacyAvailability.signedOut,
      allowFriendRequests = null,
      updatedAt = null,
      failure = null;

  const FriendRequestPrivacySnapshot.unavailable(this.failure)
    : availability = FriendRequestPrivacyAvailability.unavailable,
      allowFriendRequests = null,
      updatedAt = null;

  const FriendRequestPrivacySnapshot.available({
    required this.allowFriendRequests,
    required this.updatedAt,
  }) : availability = FriendRequestPrivacyAvailability.available,
       failure = null;

  final FriendRequestPrivacyAvailability availability;
  final bool? allowFriendRequests;
  final DateTime? updatedAt;
  final FriendRequestPrivacyFailure? failure;
}

enum FriendRequestPrivacyWriteOutcome { completed, rejected, unknown }

@immutable
final class FriendRequestPrivacyWriteResult {
  const FriendRequestPrivacyWriteResult.completed(this.snapshot)
    : outcome = FriendRequestPrivacyWriteOutcome.completed,
      failure = null;

  const FriendRequestPrivacyWriteResult.rejected(this.failure)
    : outcome = FriendRequestPrivacyWriteOutcome.rejected,
      snapshot = null;

  const FriendRequestPrivacyWriteResult.unknown()
    : outcome = FriendRequestPrivacyWriteOutcome.unknown,
      snapshot = null,
      failure = FriendRequestPrivacyFailure.outcomeUnknown;

  final FriendRequestPrivacyWriteOutcome outcome;
  final FriendRequestPrivacySnapshot? snapshot;
  final FriendRequestPrivacyFailure? failure;
}

abstract interface class FriendRequestPrivacyPort {
  Stream<void> get invalidations;

  Future<FriendRequestPrivacySnapshot> read();

  Future<FriendRequestPrivacyWriteResult> save(bool allowFriendRequests);

  Future<void> close();
}

@immutable
final class FriendRequestPrivacyProjection {
  const FriendRequestPrivacyProjection({
    required this.snapshot,
    this.operation = FriendRequestPrivacyOperation.none,
    this.failure,
  });

  final FriendRequestPrivacySnapshot snapshot;
  final FriendRequestPrivacyOperation operation;
  final FriendRequestPrivacyFailure? failure;

  bool get canEdit =>
      snapshot.availability == FriendRequestPrivacyAvailability.available &&
      operation == FriendRequestPrivacyOperation.none;
}

final class FriendRequestPrivacyModule {
  FriendRequestPrivacyModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      // Identity invalidation must never retain another account's settings.
      _epoch++;
      _reading = false;
      _busy = false;
      _refreshPending = false;
      projection.value = const FriendRequestPrivacyProjection(
        snapshot: FriendRequestPrivacySnapshot.loading(),
      );
      unawaited(refresh());
    });
  }

  final FriendRequestPrivacyPort _port;
  final ValueNotifier<FriendRequestPrivacyProjection> projection =
      ValueNotifier(
        const FriendRequestPrivacyProjection(
          snapshot: FriendRequestPrivacySnapshot.loading(),
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
    projection.value = FriendRequestPrivacyProjection(
      snapshot: snapshot,
      failure: snapshot.failure,
    );
    _drainRefresh();
  }

  Future<bool> save(bool allowFriendRequests) async {
    final current = projection.value;
    if (_disposed || _busy || !current.canEdit) return false;
    _busy = true;
    // Saves take precedence; a late background response cannot undo a receipt.
    final epoch = ++_epoch;
    _reading = false;
    projection.value = FriendRequestPrivacyProjection(
      snapshot: current.snapshot,
      operation: FriendRequestPrivacyOperation.saving,
    );
    final result = await _port.save(allowFriendRequests);
    if (_disposed || epoch != _epoch) return false;
    _busy = false;
    final updated = result.snapshot;
    if (result.outcome == FriendRequestPrivacyWriteOutcome.completed &&
        updated != null) {
      projection.value = FriendRequestPrivacyProjection(snapshot: updated);
      _drainRefresh();
      return true;
    }
    projection.value = FriendRequestPrivacyProjection(
      snapshot: current.snapshot,
      failure: result.failure ?? FriendRequestPrivacyFailure.writeFailed,
    );
    _drainRefresh();
    return false;
  }

  void _drainRefresh() {
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    projection.dispose();
    unawaited(_port.close());
  }
}
