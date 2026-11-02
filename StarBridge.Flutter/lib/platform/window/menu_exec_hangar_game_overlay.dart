import 'dart:convert';

import 'package:flutter/services.dart';

enum MenuExecHangarGamePosition {
  topLeft,
  topCenter,
  topRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
}

final class MenuExecHangarGameState {
  const MenuExecHangarGameState(this.pinned, this.position);
  final bool pinned;
  final MenuExecHangarGamePosition position;
  Map<String, Object> toMap() => {
    'schemaVersion': 1,
    'pinned': pinned,
    'position': position.name,
  };
  static MenuExecHangarGameState parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 3 ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        raw['pinned'] is! bool) {
      throw const FormatException('Invalid game overlay state');
    }
    final position = MenuExecHangarGamePosition.values
        .where((p) => p.name == raw['position'])
        .firstOrNull;
    if (position == null) {
      throw const FormatException('Invalid game overlay position');
    }
    return MenuExecHangarGameState(raw['pinned'], position);
  }
}

abstract interface class MenuExecHangarGameOverlayPort {
  bool get gameOverlayAvailable;
  Future<MenuExecHangarGameState> readGameOverlay();
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  );
  Future<MenuExecHangarGameState> unpinFromGame();
}

/// Exact local display intents. No reminder, account, file, HWND or arbitrary RPC payload.
abstract final class MenuExecHangarGameOverlayRequest {
  static bool available(Object? port) =>
      port is MenuExecHangarGameOverlayPort && port.gameOverlayAvailable;
  static Future<String> handle({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required MenuExecHangarGameOverlayPort? port,
  }) async {
    const unavailable = 'menuExecHangar.session_unavailable';
    if (!isCurrent() ||
        opening == null ||
        arguments is! Map ||
        arguments['opening'] is! int ||
        arguments['opening'] != opening ||
        port?.gameOverlayAvailable != true) {
      throw PlatformException(code: unavailable);
    }
    final action = arguments['action'];
    MenuExecHangarGamePosition? position;
    if (action == 'pin') {
      position = MenuExecHangarGamePosition.values
          .where((p) => p.name == arguments['position'])
          .firstOrNull;
    }
    final fields = action == 'pin'
        ? {'opening', 'action', 'position'}
        : {'opening', 'action'};
    if (!{'read', 'pin', 'unpin'}.contains(action) ||
        arguments.length != fields.length ||
        arguments.keys.any((key) => !fields.contains(key)) ||
        action == 'pin' && position == null) {
      throw PlatformException(code: unavailable);
    }
    try {
      final state = action == 'read'
          ? await port!.readGameOverlay()
          : action == 'pin'
          ? await port!.pinToGame(position!)
          : await port!.unpinFromGame();
      if (!isCurrent()) throw PlatformException(code: unavailable);
      return jsonEncode(state.toMap());
    } on PlatformException {
      rethrow;
    } on Object {
      throw PlatformException(code: 'menuExecHangar.unavailable');
    }
  }
}

final class SurfaceMenuExecHangarGameOverlay
    implements MenuExecHangarGameOverlayPort {
  const SurfaceMenuExecHangarGameOverlay(
    this.channel,
    this.opening,
    this.isCurrent,
  );
  final MethodChannel channel;
  final int opening;
  final bool Function() isCurrent;
  @override
  bool get gameOverlayAvailable => true;
  Future<MenuExecHangarGameState> _request(
    String action, [
    MenuExecHangarGamePosition? position,
  ]) async {
    if (!isCurrent()) {
      throw PlatformException(code: 'menuExecHangar.session_unavailable');
    }
    final raw = await channel
        .invokeMethod<String>('execHangarGameOverlay', {
          'opening': opening,
          'action': action,
          if (position != null) 'position': position.name,
        })
        .timeout(const Duration(seconds: 6));
    if (!isCurrent()) {
      throw PlatformException(code: 'menuExecHangar.session_unavailable');
    }
    if (raw == null || raw.length > 256) {
      throw const FormatException('Invalid game overlay state');
    }
    return MenuExecHangarGameState.parse(jsonDecode(raw));
  }

  @override
  Future<MenuExecHangarGameState> readGameOverlay() => _request('read');
  @override
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  ) => _request('pin', position);
  @override
  Future<MenuExecHangarGameState> unpinFromGame() => _request('unpin');
}
