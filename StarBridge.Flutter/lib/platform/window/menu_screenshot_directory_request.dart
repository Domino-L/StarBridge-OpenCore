import 'dart:convert';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import 'menu_screenshot_directory.dart';
import 'menu_screenshot_destination_request.dart';

/// The menu can request a picker or an existing setting, never supply a path.
/// The displayed path is local settings content, not a tool/export argument.
final class MenuScreenshotDirectoryRequest {
  MenuScreenshotDirectoryRequest(
    MenuScreenshotDirectoryPort? source, {
    this.sourceProvider,
  }) : _source = source;
  final MenuScreenshotDirectoryPort? _source;
  final MenuScreenshotDirectoryPort? Function()? sourceProvider;
  MenuScreenshotDirectoryPort? get source => sourceProvider?.call() ?? _source;
  MenuScreenshotDirectoryPort? _scope;

  Future<String> dispatch({
    required String method,
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
  }) {
    if (method == 'screenshotDestination') {
      return MenuScreenshotDestinationRequest.handle(
        arguments: arguments,
        opening: opening,
        isCurrent: isCurrent,
        port: source,
      );
    }
    if (method == 'screenshotDirectory') {
      return handle(
        arguments: arguments,
        opening: opening,
        isCurrent: isCurrent,
      );
    }
    return Future.error(
      PlatformException(code: 'menuScreenshotDirectory.unavailable'),
    );
  }

  void retire() {
    final scope = _scope;
    _scope = null;
    if (scope is ScopedMenuScreenshotDirectory) scope.dispose();
  }

  Future<String> handle({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
  }) async {
    const unavailable = 'menuScreenshotDirectory.session_unavailable';
    if (!isCurrent() ||
        source == null ||
        arguments is! Map ||
        opening == null ||
        opening <= 0 ||
        arguments['opening'] is! int ||
        arguments['opening'] != opening) {
      throw PlatformException(code: unavailable);
    }
    try {
      final action = arguments['action'];
      final reading = action == 'read';
      if (reading
          ? arguments.length != 2
          : !const {'choose', 'reset', 'open'}.contains(action) ||
                arguments.length != 3 ||
                arguments['revision'] is! int ||
                (arguments['revision'] as int) < 0) {
        throw const FormatException('Invalid screenshot settings intent');
      }
      final port = _scope ??= source is ScopedMenuScreenshotDirectory
          ? (source as ScopedMenuScreenshotDirectory).fork()
          : source!;
      // Re-read the trusted path; the surface sends only the revision it saw.
      var value = await port.read();
      if (!isCurrent()) throw PlatformException(code: unavailable);
      if (!reading) {
        if (value.revision != arguments['revision']) {
          throw PlatformException(
            code: 'menuScreenshotDirectory.revision_conflict',
          );
        }
        value = await switch (action) {
          'choose' => port.choose(value),
          'reset' => port.reset(value),
          _ => port.open(value),
        };
      }
      if (!isCurrent()) throw PlatformException(code: unavailable);
      return jsonEncode(value.toMap());
    } on PlatformException {
      rethrow;
    } on BridgeClientException catch (error) {
      throw PlatformException(code: error.code);
    } on Object {
      throw PlatformException(code: 'menuScreenshotDirectory.unavailable');
    }
  }
}
