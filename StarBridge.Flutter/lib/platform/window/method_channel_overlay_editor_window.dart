import 'package:flutter/services.dart';

import 'overlay_editor_window_port.dart';

final class MethodChannelOverlayEditorWindow
    implements OverlayEditorWindowPort {
  const MethodChannelOverlayEditorWindow();

  static const _channel = MethodChannel('starbridge/window-chrome');

  @override
  Future<void> enter() => _channel.invokeMethod<void>('enterOverlayEditor');

  @override
  Future<void> exit() => _channel.invokeMethod<void>('exitOverlayEditor');
}
