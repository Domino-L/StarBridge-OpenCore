import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_shortcut_settings.dart';

/// Bounded UI intent into the shared shortcut owner. Every asynchronous step
/// keeps the current opening check; errors preserve the Host's stable code.
abstract final class MenuShortcutRequest {
  static Future<String> handle({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required MenuShortcutSettingsPort? port,
    required Future<void> Function() afterSave,
  }) async {
    if (!isCurrent() ||
        arguments is! Map ||
        arguments['opening'] != opening ||
        port == null) {
      throw PlatformException(code: 'menuHotkey.session_unavailable');
    }
    try {
      final action = arguments['action'];
      MenuShortcutSettings value;
      if (action == 'get' && arguments.length == 2) {
        value = await port.readShortcut();
      } else if (action == 'update' &&
          arguments.length == 3 &&
          arguments['payload'] is String &&
          (arguments['payload'] as String).length <= 1024) {
        final raw = jsonDecode(arguments['payload'] as String);
        if (raw is! Map) throw const FormatException('Invalid settings');
        value = await port.saveShortcut(
          MenuShortcutSettings.parse(Map<String, Object?>.from(raw)),
        );
        if (isCurrent()) await afterSave();
      } else {
        throw const FormatException('Invalid settings intent');
      }
      if (!isCurrent()) {
        throw PlatformException(code: 'menuHotkey.session_unavailable');
      }
      return jsonEncode(value.toMap());
    } on PlatformException {
      rethrow;
    } on BridgeClientException catch (error) {
      throw PlatformException(code: error.code);
    } on Object {
      throw PlatformException(code: 'menuHotkey.unavailable');
    }
  }
}
