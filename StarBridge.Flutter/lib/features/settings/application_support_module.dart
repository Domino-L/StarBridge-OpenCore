import 'dart:async';

import 'package:flutter/foundation.dart';

import 'application_support_models.dart';
import 'application_support_port.dart';

abstract interface class ApplicationSupportModule {
  ValueListenable<ApplicationSupportProjection> get projection;

  Future<void> initialize();
  Future<void> refresh();
  Future<ApplicationSupportActionResult> openDataDirectory();
  void dispose();
}

ApplicationSupportModule createApplicationSupportModule(
  ApplicationSupportPort port,
) => _DefaultApplicationSupportModule(port);

final class _DefaultApplicationSupportModule
    implements ApplicationSupportModule {
  _DefaultApplicationSupportModule(this._port);

  final ApplicationSupportPort _port;
  final ValueNotifier<ApplicationSupportProjection> _projection = ValueNotifier(
    const ApplicationSupportProjection.loading(),
  );
  bool _initialized = false;
  bool _reading = false;
  bool _refreshPending = false;
  bool _disposed = false;

  @override
  ValueListenable<ApplicationSupportProjection> get projection => _projection;

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    _initialized = true;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    if (_disposed) return;
    if (_reading) {
      _refreshPending = true;
      return;
    }

    _reading = true;
    _projection.value = const ApplicationSupportProjection.loading();
    try {
      final snapshot = await _port.inspect();
      if (!_disposed) {
        _projection.value = ApplicationSupportProjection.ready(snapshot);
      }
    } on ApplicationSupportException catch (error) {
      if (!_disposed) {
        _projection.value = ApplicationSupportProjection.failed(error.failure);
      }
    } on Object {
      if (!_disposed) {
        _projection.value = const ApplicationSupportProjection.failed(
          ApplicationSupportFailure.invalidResponse,
        );
      }
    } finally {
      _reading = false;
      if (!_disposed && _refreshPending) {
        _refreshPending = false;
        await refresh();
      }
    }
  }

  @override
  Future<ApplicationSupportActionResult> openDataDirectory() async {
    if (_disposed) return ApplicationSupportActionResult.hostUnavailable;
    try {
      await _port.openDataDirectory();
      return ApplicationSupportActionResult.completed;
    } on ApplicationSupportException catch (error) {
      return switch (error.failure) {
        ApplicationSupportFailure.hostUnavailable ||
        ApplicationSupportFailure.timeout =>
          ApplicationSupportActionResult.hostUnavailable,
        ApplicationSupportFailure.inspectionFailed ||
        ApplicationSupportFailure.invalidResponse =>
          ApplicationSupportActionResult.failed,
      };
    } on Object {
      return ApplicationSupportActionResult.failed;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _projection.dispose();
    unawaited(_port.close());
  }
}
