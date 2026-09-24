import 'dart:async';

import 'package:flutter/foundation.dart';

import 'notification_settings_models.dart';
import 'notification_settings_port.dart';

abstract interface class NotificationSettingsModule {
  ValueListenable<NotificationSettingsProjection> get projection;

  Future<void> initialize();
  Future<void> refresh();
  Future<bool> save(NotificationSettingsValue settings);
  void dispose();
}

NotificationSettingsModule createNotificationSettingsModule(
  NotificationSettingsPort port,
) => _DefaultNotificationSettingsModule(port);

final class _DefaultNotificationSettingsModule
    implements NotificationSettingsModule {
  _DefaultNotificationSettingsModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        unawaited(refresh());
      }
    });
  }

  final NotificationSettingsPort _port;
  final ValueNotifier<NotificationSettingsProjection> _projection =
      ValueNotifier(const NotificationSettingsProjection.loading());
  late final StreamSubscription<void> _subscription;
  bool _initialized = false;
  bool _reading = false;
  bool _refreshPending = false;
  bool _disposed = false;

  @override
  ValueListenable<NotificationSettingsProjection> get projection => _projection;

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
        _projection.value.operation == NotificationSettingsOperation.saving) {
      _refreshPending = true;
      return;
    }
    _reading = true;
    _projection.value = const NotificationSettingsProjection.loading();
    final snapshot = await _port.read();
    _reading = false;
    if (_disposed) {
      return;
    }
    _projection.value = NotificationSettingsProjection.fromSnapshot(snapshot);
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  @override
  Future<bool> save(NotificationSettingsValue settings) async {
    final current = _projection.value;
    final revision = current.revision;
    if (_disposed || !current.canEdit || revision == null) {
      return false;
    }
    _projection.value = current.copyWith(
      operation: NotificationSettingsOperation.saving,
      clearFailure: true,
    );
    final result = await _port.update(settings, expectedRevision: revision);
    if (_disposed) {
      return false;
    }
    final updated = result.snapshot;
    if (result.outcome == NotificationSettingsWriteOutcome.completed &&
        updated != null) {
      _projection.value = NotificationSettingsProjection.fromSnapshot(updated);
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refresh());
      }
      return true;
    }
    _projection.value = current.copyWith(
      operation: NotificationSettingsOperation.none,
      failure: result.failure ?? NotificationSettingsFailure.writeFailed,
    );
    return false;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_subscription.cancel());
    _projection.dispose();
    unawaited(_port.close());
  }
}
