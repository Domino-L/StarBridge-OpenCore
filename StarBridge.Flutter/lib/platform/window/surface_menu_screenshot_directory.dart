import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_screenshot_directory.dart';

final class SurfaceMenuScreenshotDirectory
    implements MenuScreenshotDirectoryPort {
  const SurfaceMenuScreenshotDirectory(
    this.channel,
    this.opening,
    this.isCurrent,
  );
  final MethodChannel channel;
  final int opening;
  final bool Function() isCurrent;
  @override
  Future<MenuScreenshotDirectory> read() => _call('read');
  @override
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved) =>
      _call('choose', saved);
  @override
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved) =>
      _call('reset', saved);
  @override
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved) =>
      _call('open', saved);

  Future<MenuScreenshotDirectory> _call(
    String action, [
    MenuScreenshotDirectory? saved,
  ]) async {
    void current() {
      if (!isCurrent()) {
        throw const BridgeClientException(
          'menuScreenshotDirectory.session_unavailable',
        );
      }
    }

    current();
    try {
      final reply = await channel
          .invokeMethod<String>('screenshotDirectory', {
            'opening': opening,
            'action': action,
            if (saved != null) 'revision': saved.revision,
          })
          .timeout(
            action == 'choose'
                ? const Duration(minutes: 6)
                : const Duration(seconds: 8),
          );
      current();
      if (reply == null || reply.length > 262144) {
        throw const FormatException('Invalid directory reply');
      }
      final value = MenuScreenshotDirectory.parse(jsonDecode(reply));
      if ((saved != null && value.revision < saved.revision) ||
          (action != 'choose' && value.cancelled) ||
          (action == 'open' ? !value.opened : value.opened) ||
          (action == 'open' &&
              (value.revision != saved!.revision ||
                  value.directory != saved.directory))) {
        throw const FormatException('Invalid directory operation result');
      }
      return value;
    } on PlatformException catch (error) {
      throw BridgeClientException(error.code);
    }
  }
}
