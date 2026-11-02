import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/window/menu_exec_hangar_game_overlay.dart';

final class ExecHangarReminders {
  const ExecHangarReminders({
    this.enabled = false,
    this.onOpen = true,
    this.beforeOpen = true,
    this.beforeOpenMinutes = 5,
    this.beforeChange = true,
    this.beforeChangeMinutes = 5,
    bool? beforeClose,
    int? beforeCloseMinutes,
    this.onClose = false,
    this.leaveWarning = false,
    this.autoDuringGame = false,
  }) : beforeClose = beforeClose ?? beforeChange,
       beforeCloseMinutes = beforeCloseMinutes ?? beforeChangeMinutes;
  final bool enabled, onOpen, beforeOpen, beforeChange;
  final int beforeOpenMinutes, beforeChangeMinutes;
  final bool beforeClose, onClose;
  final bool leaveWarning;
  final bool autoDuringGame;
  final int beforeCloseMinutes;
  Map<String, Object> get wire => {
    'enabled': enabled,
    'onOpen': onOpen,
    'beforeOpen': beforeOpen,
    'beforeOpenMinutes': beforeOpenMinutes,
    'beforeChange': beforeChange,
    'beforeChangeMinutes': beforeChangeMinutes,
    'beforeClose': beforeClose,
    'beforeCloseMinutes': beforeCloseMinutes,
    'onClose': onClose,
    'leaveWarning': leaveWarning,
    'autoDuringGame': autoDuringGame,
  };
  bool get hasRules =>
      onOpen ||
      beforeOpen ||
      beforeClose ||
      beforeChange ||
      onClose ||
      leaveWarning;
}

enum ExecHangarAction { start, continuous, stop, extend, addHour, restore }

final class ExecHangarNotice {
  const ExecHangarNotice(
    this.due,
    this.boundary,
    this.opening, {
    this.kind = '',
  });
  final DateTime due, boundary;
  final bool opening;
  final String kind;
}

final class ExecHangarPlan {
  const ExecHangarPlan({
    required this.active,
    required this.state,
    required this.onlyNext,
    this.endsAt,
    this.next,
    this.outside,
    this.target,
    this.waiting,
    this.mutedBoundary,
    this.startedAt,
  });
  final bool active, onlyNext;
  final String state;
  final DateTime? endsAt, target, mutedBoundary, startedAt;
  final ExecHangarNotice? next, outside, waiting;
}

final class ExecHangarPhase {
  const ExecHangarPhase(this.start, this.end, this.open, this.green, this.red);
  final DateTime start, end;
  final bool open;
  final int green, red;
}

final class ExecHangarWindow {
  const ExecHangarWindow(this.open, this.close);
  final DateTime open, close;
}

final class ExecHangarSnapshot {
  const ExecHangarSnapshot({
    required this.revision,
    required this.reminders,
    required this.now,
    required this.reliable,
    required this.refreshFailed,
    required this.deliveryState,
    required this.phases,
    required this.windows,
    this.version,
    this.lastModified,
    this.sourceUrl,
    this.fetchedAt,
    this.plan,
    this.monitoringSource = 'none',
    this.gameMonitoringState = 'disabled',
  });
  final int revision;
  final ExecHangarReminders reminders;
  final DateTime now;
  final bool reliable, refreshFailed;
  final String deliveryState;
  final List<ExecHangarPhase> phases;
  final List<ExecHangarWindow> windows;
  final String? version, lastModified, sourceUrl;
  final DateTime? fetchedAt;
  final ExecHangarPlan? plan;
  final String monitoringSource, gameMonitoringState;
}

abstract interface class ExecHangarPort {
  Future<ExecHangarSnapshot> read({bool refresh = false});
  Future<ExecHangarSnapshot> save(ExecHangarReminders reminders, int revision);
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  });
}

abstract interface class ExecHangarExperiencePort {
  Future<ExecHangarSnapshot> preview(
    ExecHangarReminders reminders,
    int minutes,
    bool onlyNext,
  );
  Future<ExecHangarSnapshot> testReminder();
}

final class BridgeExecHangar
    implements
        ExecHangarPort,
        ExecHangarExperiencePort,
        MenuExecHangarGameOverlayPort {
  BridgeExecHangar(this.session);
  final BridgeClientSession session;
  @override
  bool get gameOverlayAvailable => const [
    'execHangar.gameOverlay.read',
    'execHangar.gameOverlay.pin',
    'execHangar.gameOverlay.unpin',
  ].every(session.hostCapabilities.contains);
  Future<MenuExecHangarGameState> _overlay(
    String action, [
    MenuExecHangarGamePosition? position,
  ]) async {
    if (!gameOverlayAvailable) {
      throw const BridgeFormatException('Game overlay unavailable.');
    }
    final generation = session.activeGeneration;
    final reply = await session.request(
      'execHangar.gameOverlay.$action',
      payload: {
        'schemaVersion': 1,
        if (position != null) 'position': position.name,
      },
    );
    if (session.activeGeneration != generation) {
      throw const BridgeFormatException('Stale game overlay response.');
    }
    return MenuExecHangarGameState.parse(reply.payload);
  }

  @override
  Future<MenuExecHangarGameState> readGameOverlay() => _overlay('read');
  @override
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  ) => _overlay('pin', position);
  @override
  Future<MenuExecHangarGameState> unpinFromGame() => _overlay('unpin');
  Future<ExecHangarSnapshot> _request(
    String name,
    Map<String, Object> payload,
  ) async {
    if (!session.hostCapabilities.contains(name)) {
      throw const BridgeFormatException('Hangar capability unavailable.');
    }
    final generation = session.activeGeneration;
    final reply = await session.request(name, payload: payload);
    if (session.activeGeneration != generation) {
      throw const BridgeFormatException('Stale hangar response.');
    }
    return parse(reply.payload);
  }

  @override
  Future<ExecHangarSnapshot> preview(
    ExecHangarReminders reminders,
    int minutes,
    bool onlyNext,
  ) => _request('execHangar.preview', {
    'schemaVersion': 1,
    'durationMinutes': minutes,
    'onlyNext': onlyNext,
    ...reminders.wire,
  });
  @override
  Future<ExecHangarSnapshot> testReminder() =>
      _request('execHangar.test', {'schemaVersion': 1});
  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) => _request(
    refresh ? 'execHangar.refresh' : 'execHangar.read',
    {'schemaVersion': 1},
  );
  @override
  Future<ExecHangarSnapshot> save(
    ExecHangarReminders reminders,
    int revision,
  ) => _request('execHangar.save', {
    'schemaVersion': 1,
    'expectedRevision': revision,
    ...reminders.wire,
  });
  @override
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) => _request('execHangar.${action.name}', {
    'schemaVersion': 1,
    'expectedRevision': revision,
    if (action == ExecHangarAction.start) ...{
      'durationMinutes': durationMinutes,
      'onlyNext': onlyNext,
    },
  });

  static ExecHangarSnapshot parse(Map<String, Object?> body) {
    Never bad() =>
        throw const BridgeFormatException('Invalid hangar snapshot.');
    DateTime date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw)?.toUtc() ?? bad() : bad();
    Map<String, Object?> map(Object? raw) =>
        raw is Map<String, Object?> ? raw : bad();
    bool flag(Object? raw) => raw is bool ? raw : bad();
    int integer(Object? raw, int min, int max) =>
        raw is int && raw >= min && raw <= max ? raw : bad();
    String? text(Object? raw, int max) => raw == null
        ? null
        : raw is String && raw.length <= max
        ? raw
        : bad();
    if (body['schemaVersion'] != 1) bad();
    final reminders = map(body['reminders']);
    final config = body['config'] == null ? null : map(body['config']);
    final rawPhases = body['phases'], rawWindows = body['windows'];
    if (rawPhases is! List ||
        rawPhases.length > 22 ||
        rawWindows is! List ||
        rawWindows.length > 6) {
      bad();
    }
    final phases = rawPhases.map((raw) {
      final p = map(raw);
      final start = date(p['start']), end = date(p['end']);
      final green = integer(p['greenLights'], 0, 5),
          red = integer(p['redLights'], 0, 5);
      if (!end.isAfter(start) || green + red > 5) bad();
      return ExecHangarPhase(start, end, flag(p['open']), green, red);
    }).toList();
    for (var i = 1; i < phases.length; i++) {
      if (phases[i].start != phases[i - 1].end) bad();
    }
    final windows = rawWindows.map((raw) {
      final w = map(raw);
      final open = date(w['open']), close = date(w['close']);
      if (!close.isAfter(open)) bad();
      return ExecHangarWindow(open, close);
    }).toList();
    if (config == null &&
        (phases.isNotEmpty || windows.isNotEmpty || flag(body['reliable']))) {
      bad();
    }
    final source = config == null ? null : text(config['sourceUrl'], 2048);
    if (source != null &&
        (Uri.tryParse(source)?.scheme != 'https' ||
            Uri.parse(source).userInfo.isNotEmpty)) {
      bad();
    }
    final delivery = text(body['deliveryState'], 40);
    final monitoringSource = text(body['monitoringSource'], 20) ?? 'none';
    final gameMonitoringState =
        text(body['gameMonitoringState'], 20) ?? 'disabled';
    if (!['none', 'manual', 'game'].contains(monitoringSource) ||
        ![
          'disabled',
          'waiting',
          'watching',
          'paused',
          'unknown',
          'noRules',
        ].contains(gameMonitoringState)) {
      bad();
    }
    ExecHangarNotice? notice(Object? raw) {
      if (raw == null) return null;
      final n = map(raw);
      final due = date(n['due']), boundary = date(n['boundary']);
      if (due.isAfter(boundary) ||
          boundary.difference(due) > const Duration(minutes: 120)) {
        bad();
      }
      return ExecHangarNotice(
        due,
        boundary,
        flag(n['opening']),
        kind: text(n['kind'], 30) ?? '',
      );
    }

    final rawPlan = body['plan'] == null ? null : map(body['plan']);
    final planState = rawPlan == null ? null : text(rawPlan['state'], 20);
    if (rawPlan != null &&
        ![
          'stopped',
          'complete',
          'expired',
          'noRules',
          'noEvent',
          'watching',
          'waiting',
          'muted',
        ].contains(planState)) {
      bad();
    }
    if (![
      'idle',
      'paused',
      'submitted',
      'soundOnly',
      'failed',
      'suppressed',
      'windowsDisabled',
      'doNotDisturb',
      'fullScreen',
      'inactiveDesktop',
      'quietTime',
      'systemBusy',
      'queueFull',
      'expired',
      'environmentUnknown',
      'desktopUnavailable',
    ].contains(delivery)) {
      bad();
    }
    return ExecHangarSnapshot(
      revision: integer(body['revision'], 0, 0x7fffffff),
      reminders: ExecHangarReminders(
        enabled: flag(reminders['enabled']),
        onOpen: flag(reminders['onOpen']),
        beforeOpen: flag(reminders['beforeOpen']),
        beforeOpenMinutes: integer(reminders['beforeOpenMinutes'], 1, 120),
        beforeChange: flag(reminders['beforeChange']),
        beforeChangeMinutes: integer(reminders['beforeChangeMinutes'], 1, 120),
        beforeClose: reminders['beforeClose'] == null
            ? flag(reminders['beforeChange'])
            : flag(reminders['beforeClose']),
        beforeCloseMinutes: reminders['beforeCloseMinutes'] == null
            ? integer(reminders['beforeChangeMinutes'], 1, 120)
            : integer(reminders['beforeCloseMinutes'], 1, 120),
        onClose: reminders['onClose'] == null
            ? false
            : flag(reminders['onClose']),
        leaveWarning: reminders['leaveWarning'] == null
            ? false
            : flag(reminders['leaveWarning']),
        autoDuringGame: reminders['autoDuringGame'] == null
            ? false
            : flag(reminders['autoDuringGame']),
      ),
      monitoringSource: monitoringSource,
      gameMonitoringState: gameMonitoringState,
      now: date(body['now']),
      reliable: flag(body['reliable']),
      refreshFailed: flag(body['refreshFailed']),
      deliveryState: delivery!,
      phases: List.unmodifiable(phases),
      windows: List.unmodifiable(windows),
      version: config == null ? null : text(config['version'], 80),
      lastModified: config == null ? null : text(config['lastModified'], 120),
      sourceUrl: source,
      fetchedAt: body['fetchedAt'] == null ? null : date(body['fetchedAt']),
      plan: rawPlan == null
          ? null
          : ExecHangarPlan(
              active: flag(rawPlan['active']),
              state: planState!,
              onlyNext: flag(rawPlan['onlyNext']),
              endsAt: rawPlan['endsAt'] == null
                  ? null
                  : date(rawPlan['endsAt']),
              next: notice(rawPlan['next']),
              outside: notice(rawPlan['outside']),
              waiting: notice(rawPlan['waiting']),
              mutedBoundary: rawPlan['mutedBoundary'] == null
                  ? null
                  : date(rawPlan['mutedBoundary']),
              target: rawPlan['target'] == null
                  ? null
                  : date(rawPlan['target']),
              startedAt: rawPlan['startedAt'] == null
                  ? null
                  : date(rawPlan['startedAt']),
            ),
    );
  }
}
