import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_browser_resume.dart';

/// Exact bounded intents only. The primary owner and Host each validate their
/// own lease; no renderer-selected identity, path, script or arbitrary RPC.
abstract final class MenuBrowserResumeRequest {
  static Future<String> handle({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required MenuBrowserResumePort? port,
  }) async {
    const unavailable = 'menuBrowserResume.session_unavailable';
    if (!isCurrent() ||
        arguments is! Map ||
        opening == null ||
        arguments['opening'] != opening ||
        port == null) {
      throw PlatformException(code: unavailable);
    }
    try {
      final action = arguments['action'];
      MenuBrowserResume value;
      if (action == 'get' && arguments.length == 2) {
        value = await port.read();
      } else {
        if (arguments.length != 3 ||
            arguments['payload'] is! String ||
            (arguments['payload'] as String).length > 24576) {
          throw const FormatException('Invalid browser settings intent');
        }
        final raw = jsonDecode(arguments['payload'] as String);
        if (raw is! Map ||
            raw.length != 2 ||
            raw['revision'] is! int ||
            (raw['revision'] as int) < 0) {
          throw const FormatException('Invalid browser settings intent');
        }
        // No URL from a UI policy update is accepted or saved.
        if (action == 'update' && raw['enabled'] is bool) {
          value = await port.setEnabled(
            MenuBrowserResume(raw['revision'], false, null),
            raw['enabled'],
          );
        } else if (action == 'remember' &&
            raw['url'] is String &&
            MenuBrowserResume.validUrl(raw['url'])) {
          value = await port.remember(
            MenuBrowserResume(raw['revision'], true, null),
            raw['url'],
          );
        } else {
          throw const FormatException('Invalid browser settings intent');
        }
      }
      if (!isCurrent()) throw PlatformException(code: unavailable);
      return jsonEncode(value.toMap());
    } on PlatformException {
      rethrow;
    } on BridgeClientException catch (error) {
      throw PlatformException(code: error.code);
    } on Object {
      throw PlatformException(code: 'menuBrowserResume.unavailable');
    }
  }
}
