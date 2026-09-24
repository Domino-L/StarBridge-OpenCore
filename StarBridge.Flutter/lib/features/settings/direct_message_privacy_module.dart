import 'dart:async';

import 'package:flutter/foundation.dart';

enum DirectMessagePrivacyAvailability {
  loading,
  signedOut,
  unavailable,
  available,
}

enum DirectMessagePrivacyOperation { none, saving }

enum DirectMessagePrivacyFailure {
  hostUnavailable,
  identityUnavailable,
  readFailed,
  writeFailed,
  outcomeUnknown,
  invalidResponse,
}

@immutable
final class DirectMessagePrivacySnapshot {
  const DirectMessagePrivacySnapshot.loading()
    : availability = DirectMessagePrivacyAvailability.loading,
      allowStrangerDirectMessages = null,
      updatedAt = null,
      failure = null;

  const DirectMessagePrivacySnapshot.signedOut()
    : availability = DirectMessagePrivacyAvailability.signedOut,
      allowStrangerDirectMessages = null,
      updatedAt = null,
      failure = null;

  const DirectMessagePrivacySnapshot.unavailable(this.failure)
    : availability = DirectMessagePrivacyAvailability.unavailable,
      allowStrangerDirectMessages = null,
      updatedAt = null;

  const DirectMessagePrivacySnapshot.available({
    required this.allowStrangerDirectMessages,
    required this.updatedAt,
  }) : availability = DirectMessagePrivacyAvailability.available,
       failure = null;

  final DirectMessagePrivacyAvailability availability;
  final bool? allowStrangerDirectMessages;
  final DateTime? updatedAt;
  final DirectMessagePrivacyFailure? failure;
}

enum DirectMessagePrivacyWriteOutcome { completed, rejected, unknown }

@immutable
final class DirectMessagePrivacyWriteResult {
  const DirectMessagePrivacyWriteResult.completed(this.snapshot)
    : outcome = DirectMessagePrivacyWriteOutcome.completed,
      failure = null;

  const DirectMessagePrivacyWriteResult.rejected(this.failure)
    : outcome = DirectMessagePrivacyWriteOutcome.rejected,
      snapshot = null;

  const DirectMessagePrivacyWriteResult.unknown()
    : outcome = DirectMessagePrivacyWriteOutcome.unknown,
      snapshot = null,
      failure = DirectMessagePrivacyFailure.outcomeUnknown;

  final DirectMessagePrivacyWriteOutcome outcome;
  final DirectMessagePrivacySnapshot? snapshot;
  final DirectMessagePrivacyFailure? failure;
}

abstract interface class DirectMessagePrivacyPort {
  Stream<void> get invalidations;

  Future<DirectMessagePrivacySnapshot> read();

  Future<DirectMessagePrivacyWriteResult> save(
    bool allowStrangerDirectMessages,
  );

  Future<void> close();
}

@immutable
final class DirectMessagePrivacyProjection {
  const DirectMessagePrivacyProjection({
    required this.snapshot,
    this.operation = DirectMessagePrivacyOperation.none,
    this.failure,
  });

  final DirectMessagePrivacySnapshot snapshot;
  final DirectMessagePrivacyOperation operation;
  final DirectMessagePrivacyFailure? failure;

  bool get canEdit =>
      snapshot.availability == DirectMessagePrivacyAvailability.available &&
      operation == DirectMessagePrivacyOperation.none;
}

final class DirectMessagePrivacyModule {
  DirectMessagePrivacyModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      // Identity invalidation must never retain another account's settings.
      _epoch++;
      _reading = false;
      _busy = false;
      _refreshPending = false;
      projection.value = const DirectMessagePrivacyProjection(
        snapshot: DirectMessagePrivacySnapshot.loading(),
      );
      unawaited(refresh());
    });
  }

  final DirectMessagePrivacyPort _port;
  final ValueNotifier<DirectMessagePrivacyProjection> projection =
      ValueNotifier(
        const DirectMessagePrivacyProjection(
          snapshot: DirectMessagePrivacySnapshot.loading(),
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
    projection.value = DirectMessagePrivacyProjection(
      snapshot: snapshot,
      failure: snapshot.failure,
    );
    _drainRefresh();
  }

  Future<bool> save(bool allowStrangerDirectMessages) async {
    final current = projection.value;
    if (_disposed || _busy || !current.canEdit) return false;
    _busy = true;
    // Saves take precedence; a late background response cannot undo a receipt.
    final epoch = ++_epoch;
    _reading = false;
    projection.value = DirectMessagePrivacyProjection(
      snapshot: current.snapshot,
      operation: DirectMessagePrivacyOperation.saving,
    );
    final result = await _port.save(allowStrangerDirectMessages);
    if (_disposed || epoch != _epoch) return false;
    _busy = false;
    final updated = result.snapshot;
    if (result.outcome == DirectMessagePrivacyWriteOutcome.completed &&
        updated != null) {
      projection.value = DirectMessagePrivacyProjection(snapshot: updated);
      _drainRefresh();
      return true;
    }
    projection.value = DirectMessagePrivacyProjection(
      snapshot: current.snapshot,
      failure: result.failure ?? DirectMessagePrivacyFailure.writeFailed,
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
