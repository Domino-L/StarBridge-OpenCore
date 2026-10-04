import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_browser_resume.dart';

final class SurfaceMenuBrowserResume implements MenuBrowserResumePort {
  const SurfaceMenuBrowserResume(this.channel, this.opening, this.isCurrent);
  final MethodChannel channel;
  final int opening;
  final bool Function() isCurrent;
  @override
  Future<MenuBrowserResume> read() => _call('get');
  @override
  Future<MenuBrowserResume> setEnabled(MenuBrowserResume saved, bool enabled) =>
      _call('update', {'revision': saved.revision, 'enabled': enabled});
  @override
  Future<MenuBrowserResume> remember(MenuBrowserResume saved, String url) {
    if (!saved.enabled || !MenuBrowserResume.validUrl(url)) {
      throw const FormatException('Browser address saving is not permitted');
    }
    return _call('remember', {'revision': saved.revision, 'url': url});
  }

  Future<MenuBrowserResume> _call(
    String action, [
    Map<String, Object?>? payload,
  ]) async {
    if (!isCurrent()) {
      throw const BridgeClientException(
        'menuBrowserResume.session_unavailable',
      );
    }
    try {
      final reply = await channel
          .invokeMethod<String>('browserResume', {
            'opening': opening,
            'action': action,
            if (payload != null) 'payload': jsonEncode(payload),
          })
          .timeout(const Duration(seconds: 6));
      if (!isCurrent()) {
        throw const BridgeClientException(
          'menuBrowserResume.session_unavailable',
        );
      }
      if (reply == null || reply.length > 24576) {
        throw const FormatException('Invalid browser settings reply');
      }
      return MenuBrowserResume.parse(jsonDecode(reply));
    } on PlatformException catch (error) {
      throw BridgeClientException(error.code);
    }
  }
}
