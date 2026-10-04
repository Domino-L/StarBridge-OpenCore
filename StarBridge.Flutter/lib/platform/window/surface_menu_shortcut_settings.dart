import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_shortcut_settings.dart';

/// The auxiliary engine has no Host/account connection. The primary owner
/// validates this opening and delegates to the same settings port as the app.
final class SurfaceMenuShortcutSettings implements MenuShortcutSettingsPort {
  const SurfaceMenuShortcutSettings(this.channel, this.opening, this.isCurrent);
  final MethodChannel channel;
  final int opening;
  final bool Function() isCurrent;
  @override
  Future<MenuShortcutSettings> readShortcut() => _call();
  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) =>
      _call(value);
  Future<MenuShortcutSettings> _call([MenuShortcutSettings? value]) async {
    if (!isCurrent()) {
      throw const BridgeClientException('menuHotkey.session_unavailable');
    }
    try {
      final reply = await channel
          .invokeMethod<String>('shortcutSettings', {
            'opening': opening,
            'action': value == null ? 'get' : 'update',
            if (value != null) 'payload': jsonEncode(value.toMap()),
          })
          .timeout(const Duration(seconds: 6));
      if (!isCurrent()) {
        throw const BridgeClientException('menuHotkey.session_unavailable');
      }
      if (reply == null || reply.length > 1024) {
        throw const FormatException('Invalid settings reply');
      }
      final raw = jsonDecode(reply);
      if (raw is! Map) throw const FormatException('Invalid settings reply');
      return MenuShortcutSettings.parse(Map<String, Object?>.from(raw));
    } on PlatformException catch (error) {
      throw BridgeClientException(error.code);
    }
  }
}
