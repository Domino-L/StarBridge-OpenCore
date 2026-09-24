import 'dart:async';

import 'package:flutter/services.dart';

import 'application_lifecycle_port.dart';

final class MethodChannelApplicationLifecycle
    implements ApplicationLifecyclePort {
  MethodChannelApplicationLifecycle() {
    _channel.setMethodCallHandler(_handleNativeMethod);
  }

  static const MethodChannel _channel = MethodChannel(
    'starbridge/application-lifecycle',
  );
  final StreamController<void> _closeRequests =
      StreamController<void>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  Future<void> configure(ApplicationWindowBehavior behavior) =>
      _invoke('configure', {
        'keepRunningInBackground': behavior.keepRunningInBackground,
        'startMinimized': behavior.startMinimized,
      });

  @override
  Future<void> hideToTray({required bool showHint}) =>
      _invoke('hideToTray', {'showHint': showHint});

  @override
  Future<void> exitApplication() => _invoke('exitApplication');

  @override
  Future<void> cancelCloseRequest() => _invoke('cancelCloseRequest');

  Future<void> _handleNativeMethod(MethodCall call) async {
    if (!_disposed && call.method == 'closeRequested') {
      _closeRequests.add(null);
    }
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Widget tests intentionally run without the Win32 runner.
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_closeRequests.close());
  }
}
