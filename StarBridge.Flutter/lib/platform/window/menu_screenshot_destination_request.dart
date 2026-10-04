import 'package:flutter/services.dart';

import 'menu_screenshot_directory.dart';

/// Trusted primary-to-native reply only. No auxiliary caller can choose a
/// path; the native relay consumes the confirmed directory for one export.
abstract final class MenuScreenshotDestinationRequest {
  static Future<String> handle({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required MenuScreenshotDirectoryPort? port,
  }) async {
    if (arguments is! Map ||
        arguments.length != 1 ||
        arguments['opening'] is! int ||
        opening == null ||
        opening <= 0 ||
        arguments['opening'] != opening ||
        !isCurrent() ||
        port == null) {
      throw PlatformException(code: 'menu.screenshot_directory_unavailable');
    }
    final value = await port.read();
    if (!isCurrent()) throw PlatformException(code: 'menu.closed');
    return value.directory;
  }
}
