import 'dart:convert';

import 'package:flutter/services.dart';

import '../../features/tools/exec_hangar_port.dart';
import 'menu_exec_hangar_game_overlay.dart';

/// Bounded local clock projection. Reminder preferences, receipts and any Host
/// or account authority stay in the primary engine.
final class MenuExecHangarSummary {
  const MenuExecHangarSummary(
    this.now,
    this.reliable,
    this.fetchedAt,
    this.phases,
    this.windows,
  );
  final DateTime now;
  final bool reliable;
  final DateTime? fetchedAt;
  final List<ExecHangarPhase> phases;
  final List<ExecHangarWindow> windows;
  factory MenuExecHangarSummary.fromSnapshot(ExecHangarSnapshot value) =>
      MenuExecHangarSummary(
        value.now,
        value.reliable,
        value.fetchedAt,
        value.phases,
        value.windows,
      );
  Map<String, Object?> toMap() => {
    'now': now.toIso8601String(),
    'reliable': reliable,
    'fetchedAt': fetchedAt?.toIso8601String(),
    'phases': [
      for (final p in phases)
        {
          'start': p.start.toIso8601String(),
          'end': p.end.toIso8601String(),
          'open': p.open,
          'green': p.green,
          'red': p.red,
        },
    ],
    'windows': [
      for (final w in windows)
        {'open': w.open.toIso8601String(), 'close': w.close.toIso8601String()},
    ],
  };
  static MenuExecHangarSummary parse(Object? raw) {
    Never bad() => throw const FormatException('Invalid hangar summary');
    DateTime date(Object? v) => v is String && v.length <= 40
        ? DateTime.tryParse(v)?.toUtc() ?? bad()
        : bad();
    if (raw is! Map ||
        raw.length != 5 ||
        raw['reliable'] is! bool ||
        raw['phases'] is! List ||
        raw['windows'] is! List) {
      bad();
    }
    final phases = raw['phases'] as List, windows = raw['windows'] as List;
    if (phases.length > 22 || windows.length > 6) bad();
    final parsedPhases = <ExecHangarPhase>[];
    for (final p in phases) {
      if (p is! Map ||
          p.length != 5 ||
          p['open'] is! bool ||
          p['green'] is! int ||
          p['red'] is! int ||
          p['green'] < 0 ||
          p['red'] < 0 ||
          p['green'] + p['red'] > 5) {
        bad();
      }
      final start = date(p['start']), end = date(p['end']);
      if (!end.isAfter(start) ||
          parsedPhases.isNotEmpty && parsedPhases.last.end != start) {
        bad();
      }
      parsedPhases.add(
        ExecHangarPhase(start, end, p['open'], p['green'], p['red']),
      );
    }
    final parsedWindows = <ExecHangarWindow>[];
    for (final w in windows) {
      if (w is! Map || w.length != 2) bad();
      final open = date(w['open']), close = date(w['close']);
      if (!close.isAfter(open) ||
          parsedWindows.isNotEmpty && !open.isAfter(parsedWindows.last.close)) {
        bad();
      }
      parsedWindows.add(ExecHangarWindow(open, close));
    }
    return MenuExecHangarSummary(
      date(raw['now']),
      raw['reliable'],
      raw['fetchedAt'] == null ? null : date(raw['fetchedAt']),
      List.unmodifiable(parsedPhases),
      List.unmodifiable(parsedWindows),
    );
  }
}

abstract interface class MenuExecHangarSummaryPort {
  Future<MenuExecHangarSummary> read();
}

/// Exact read/navigation intents, never a configurable Host RPC tunnel.
abstract final class MenuExecHangarRequest {
  static bool accepts(String method) => const {
    'execHangarSummary',
    'openExecHangar',
    'execHangarGameOverlay',
  }.contains(method);
  static Map<String, bool> presentation(ExecHangarPort? port) => {
    'execHangar': port != null,
    'execHangarGameOverlay': MenuExecHangarGameOverlayRequest.available(port),
  };
  static Future<Object?> handle({
    required String method,
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required ExecHangarPort? port,
    required void Function() openTool,
  }) async {
    if (method == 'execHangarGameOverlay') {
      return MenuExecHangarGameOverlayRequest.handle(
        arguments: arguments,
        opening: opening,
        isCurrent: isCurrent,
        port: port is MenuExecHangarGameOverlayPort
            ? port as MenuExecHangarGameOverlayPort
            : null,
      );
    }
    const unavailable = 'menuExecHangar.session_unavailable';
    if (!isCurrent() ||
        opening == null ||
        arguments is! Map ||
        arguments.length != 1 ||
        arguments['opening'] != opening ||
        port == null) {
      throw PlatformException(code: unavailable);
    }
    if (method == 'openExecHangar') {
      openTool();
      return true;
    }
    if (method != 'execHangarSummary') {
      throw PlatformException(code: unavailable);
    }
    try {
      final value = MenuExecHangarSummary.fromSnapshot(await port.read());
      if (!isCurrent()) throw PlatformException(code: unavailable);
      return jsonEncode(value.toMap());
    } on PlatformException {
      rethrow;
    } on Object {
      throw PlatformException(code: 'menuExecHangar.unavailable');
    }
  }
}

final class SurfaceMenuExecHangarSummary
    implements MenuExecHangarSummaryPort, MenuExecHangarGameOverlayPort {
  const SurfaceMenuExecHangarSummary(
    this.channel,
    this.opening,
    this.isCurrent, {
    this.gameOverlayAvailable = false,
  });
  @override
  final bool gameOverlayAvailable;
  SurfaceMenuExecHangarGameOverlay get _overlay =>
      SurfaceMenuExecHangarGameOverlay(channel, opening, isCurrent);
  @override
  Future<MenuExecHangarGameState> readGameOverlay() =>
      _overlay.readGameOverlay();
  @override
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  ) => _overlay.pinToGame(position);
  @override
  Future<MenuExecHangarGameState> unpinFromGame() => _overlay.unpinFromGame();
  final MethodChannel channel;
  final int opening;
  final bool Function() isCurrent;
  @override
  Future<MenuExecHangarSummary> read() async {
    if (!isCurrent()) {
      throw PlatformException(code: 'menuExecHangar.session_unavailable');
    }
    final raw = await channel
        .invokeMethod<String>('execHangarSummary', {'opening': opening})
        .timeout(const Duration(seconds: 6));
    if (!isCurrent()) {
      throw PlatformException(code: 'menuExecHangar.session_unavailable');
    }
    if (raw == null || raw.length > 12288) {
      throw const FormatException('Invalid hangar summary');
    }
    return MenuExecHangarSummary.parse(jsonDecode(raw));
  }
}
