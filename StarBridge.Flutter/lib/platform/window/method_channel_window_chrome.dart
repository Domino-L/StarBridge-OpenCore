import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_chrome_port.dart';

final class MethodChannelWindowChrome implements WindowChromePort {
  MethodChannelWindowChrome() {
    _channel.setMethodCallHandler(_handleNativeMethod);
    unawaited(_refreshMaximizedState());
  }

  static const MethodChannel _channel = MethodChannel(
    'starbridge/window-chrome',
  );
  final ValueNotifier<bool> _isMaximized = ValueNotifier(false);

  @override
  ValueListenable<bool> get isMaximized => _isMaximized;

  @override
  Future<void> beginDrag() => _invoke('beginDrag');

  @override
  Future<void> minimize() => _invoke('minimize');

  @override
  Future<void> toggleMaximize() async {
    await _invoke('toggleMaximize');
    await _refreshMaximizedState();
  }

  @override
  Future<void> close() => _invoke('close');

  Future<void> _handleNativeMethod(MethodCall call) async {
    if (call.method == 'windowStateChanged' && call.arguments is bool) {
      _isMaximized.value = call.arguments as bool;
    }
  }

  Future<void> _refreshMaximizedState() async {
    try {
      final value = await _channel.invokeMethod<bool>('getIsMaximized');
      if (value != null) {
        _isMaximized.value = value;
      }
    } on MissingPluginException {
      // Widget tests intentionally run without the Win32 runner.
    }
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Widget tests intentionally run without the Win32 runner.
    }
  }
}
