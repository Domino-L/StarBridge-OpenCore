import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which Flutter engine of the client this isolate draws.
enum FrameSurface { main, menu, tray, friends, messages, notifications }

/// Presence only, read from the native "starbridge/frame-pressure" channel.
typedef FramePressure = ({
  bool gameRunning,
  bool gameInFront,
  bool ownForeground,
});

/// How hard a surface may draw right now.
enum FrameMode {
  /// No game, client in front (or nothing known): the display's own rate.
  open,

  /// The player is using the client while a game runs.
  focusedWithGame,

  /// Another program is in front, but not a game.
  background,

  /// A game is in front: the client is behind it and leaves the GPU alone.
  gameInFront,
}

/// Frame rate while the client is in front and a game runs. 60 by default;
/// lab builds compare other values with --dart-define.
const focusedWithGameFps = int.fromEnvironment(
  'STARBRIDGE_FRAME_CAP_FOCUSED',
  defaultValue: 60,
);

FrameMode frameModeFor(FramePressure? pressure) {
  if (pressure == null) return FrameMode.open;
  if (pressure.ownForeground) {
    return pressure.gameRunning ? FrameMode.focusedWithGame : FrameMode.open;
  }
  return pressure.gameInFront ? FrameMode.gameInFront : FrameMode.background;
}

/// Shortest time between two frame starts; null means no limit.
Duration? frameIntervalFor(
  FrameMode mode,
  FrameSurface surface, {
  int focusedFps = focusedWithGameFps,
}) => switch (mode) {
  FrameMode.open => null,
  FrameMode.focusedWithGame => _perSecond(focusedFps),
  FrameMode.background => _perSecond(30),
  // The menu and visor are drawn over the game on purpose; keep them readable.
  FrameMode.gameInFront =>
    surface == FrameSurface.menu ? _perSecond(30) : _perSecond(5),
};

Duration? _perSecond(int fps) =>
    fps <= 0 ? null : Duration(microseconds: 1000000 ~/ fps);

/// Looping or repeating decoration may run only while the player is in the
/// client and no game runs (user 11-07: pause while a game runs or the window
/// is not in front). Unknown pressure allows it.
bool decorativeMotionAllowedFor(FramePressure? pressure) =>
    pressure == null || (pressure.ownForeground && !pressure.gameRunning);

/// The current engine's decoration switch; always on outside the client
/// binding (tests, review shells).
ValueListenable<bool> decorativeMotion() {
  final binding = WidgetsBinding.instance;
  return binding is StarBridgeBinding
      ? binding.governor.decorativeMotion
      : const _Fixed(true);
}

/// Lab only (C-lite experiment): draw the light visuals all the time, so the
/// cost can be compared on this computer without the game.
const forceLightVisuals = bool.fromEnvironment('STARBRIDGE_LAB_FORCE_LIGHT');

/// While a game runs, the most expensive effects (backdrop blurs) are swapped
/// for flat equivalents: under GPU contention every offscreen pass waits
/// behind a game frame (in-game test 11-08). Unknown pressure keeps the full
/// look; the game closing restores it. Only while the user's performance mode
/// setting is on (off by default, user 11-10): with it off the full look stays
/// even with a game. The frame cap (A) does not depend on it.
bool lightVisualsFor(FramePressure? pressure, {bool performanceMode = false}) =>
    forceLightVisuals || (performanceMode && pressure?.gameRunning == true);

/// The user's performance mode setting, kept in step with the application
/// preferences by the app; off until they are read.
final performanceModePreference = ValueNotifier<bool>(false);

/// Widget tests drive the light visuals without a governed binding.
@visibleForTesting
ValueListenable<bool>? debugLightVisualsOverride;

/// The current engine's light-visuals switch; off outside the client binding
/// (tests, review shells) unless the lab define forces it.
ValueListenable<bool> lightVisuals() {
  final override = debugLightVisualsOverride;
  if (override != null) return override;
  final binding = WidgetsBinding.instance;
  return binding is StarBridgeBinding
      ? binding.governor.lightVisuals
      : const _Fixed(forceLightVisuals);
}

final class _Fixed implements ValueListenable<bool> {
  const _Fixed(this.value);
  @override
  final bool value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

Future<FramePressure?> readNativeFramePressure() async {
  const channel = MethodChannel('starbridge/frame-pressure');
  return parseFramePressure(
    await channel.invokeMapMethod<String, Object?>('read'),
  );
}

/// Only a complete answer counts. The native side answers null when it could
/// not tell (no foreground window, no process id, process list unavailable);
/// a missing or non-boolean field is treated the same: unknown, never limit.
FramePressure? parseFramePressure(Map<String, Object?>? value) {
  if (value == null) return null;
  final running = value['gameRunning'];
  final inFront = value['gameInFront'];
  final own = value['ownForeground'];
  if (running is! bool || inFront is! bool || own is! bool) return null;
  return (gameRunning: running, gameInFront: inFront, ownForeground: own);
}

/// Decides when a requested frame may start. Animations keep real time
/// (frame timestamps), so a lower rate only makes them coarser, never slower.
/// Pressure is read on demand, only while frames are being requested, so an
/// idle unlimited client asks nothing. While limited or with decoration
/// paused, a slow probe keeps reading so the client recovers by itself even
/// when nothing else asks for a frame. Anything unknown (no answer within
/// [readTimeout], an error, an incomplete answer) means: never limit.
final class FrameGovernor {
  FrameGovernor({
    required this.surface,
    Future<FramePressure?> Function()? readPressure,
    Duration Function()? clock,
    this.refreshAfter = const Duration(milliseconds: 500),
    this.readTimeout = const Duration(seconds: 2),
    this.probeEvery = const Duration(seconds: 2),
    this.focusedFps = focusedWithGameFps,
    ValueListenable<bool>? performanceMode,
  }) : _read = readPressure ?? readNativeFramePressure,
       _clock = clock ?? _stopwatchClock(),
       _performanceMode = performanceMode ?? performanceModePreference {
    _performanceMode.addListener(_updateLightVisuals);
  }

  final ValueListenable<bool> _performanceMode;

  void _updateLightVisuals() {
    if (_disposed) return;
    _lightVisuals.value = lightVisualsFor(
      _pressure,
      performanceMode: _performanceMode.value,
    );
  }

  final FrameSurface surface;
  final Duration refreshAfter;
  final Duration readTimeout;
  final Duration probeEvery;
  Future<FramePressure?> Function()? _read;
  final Duration Function() _clock;
  final int focusedFps;

  FramePressure? _pressure;
  Duration? _readAt;
  bool _reading = false;
  bool _disposed = false;
  Duration? _lastFrameStart;
  Timer? _deferred;
  Timer? _probe;
  VoidCallback? _pendingSchedule;

  final _decorativeMotion = ValueNotifier(true);
  ValueListenable<bool> get decorativeMotion => _decorativeMotion;
  final _lightVisuals = ValueNotifier(forceLightVisuals);
  ValueListenable<bool> get lightVisuals => _lightVisuals;

  /// Frames started and requests delayed, per mode; read by the diagnostics.
  final frames = <FrameMode, int>{};
  int deferrals = 0;

  FrameMode get mode => frameModeFor(_pressure);
  Duration? get interval =>
      frameIntervalFor(mode, surface, focusedFps: focusedFps);
  @visibleForTesting
  bool get hasDeferredFrame => _deferred != null;
  @visibleForTesting
  bool get isProbing => _probe != null;

  static Duration Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// [schedule] asks the engine for the next vsync.
  void request(VoidCallback schedule) {
    _refreshIfStale();
    if (_deferred != null) {
      _pendingSchedule = schedule;
      return;
    }
    final wait = _waitBeforeNextFrame();
    if (wait == null) {
      schedule();
      return;
    }
    deferrals++;
    _pendingSchedule = schedule;
    _deferred = Timer(wait, _releaseDeferred);
  }

  void frameStarted() {
    _lastFrameStart = _clock();
    frames.update(mode, (count) => count + 1, ifAbsent: () => 1);
  }

  void dispose() {
    // A read still in flight must not apply its answer or restart the probe.
    _disposed = true;
    _performanceMode.removeListener(_updateLightVisuals);
    _deferred?.cancel();
    _deferred = null;
    _probe?.cancel();
    _probe = null;
    _pendingSchedule = null;
  }

  Duration? _waitBeforeNextFrame() {
    final limit = interval;
    final last = _lastFrameStart;
    if (limit == null || last == null) return null;
    final wait = limit - (_clock() - last);
    return wait > Duration.zero ? wait : null;
  }

  void _releaseDeferred() {
    _deferred = null;
    final schedule = _pendingSchedule;
    _pendingSchedule = null;
    if (schedule == null) return;
    // The rule may have tightened meanwhile (a game came to the front).
    request(schedule);
  }

  void _refreshIfStale() {
    final read = _read;
    if (_disposed || read == null || _reading) return;
    final readAt = _readAt;
    if (readAt != null && _clock() - readAt < refreshAfter) return;
    _reading = true;
    unawaited(_refresh(read));
  }

  Future<void> _refresh(Future<FramePressure?> Function() read) async {
    try {
      // A channel that never answers must not keep an old limit forever.
      _apply(await read().timeout(readTimeout));
    } on MissingPluginException {
      // Tests and hosts without the channel: never limit.
      _read = null;
      _apply(null);
    } catch (_) {
      _apply(null);
    } finally {
      _reading = false;
      _readAt = _clock();
    }
  }

  void _apply(FramePressure? pressure) {
    if (_disposed) return;
    _pressure = pressure;
    _decorativeMotion.value = decorativeMotionAllowedFor(pressure);
    _updateLightVisuals();
    _updateProbe();
    final schedule = _pendingSchedule;
    if (_deferred == null || schedule == null) return;
    // Re-decide a waiting frame under the new rule: coming back to the client
    // must not sit out the old 200 ms slot.
    _deferred!.cancel();
    _deferred = null;
    _pendingSchedule = null;
    final wait = _waitBeforeNextFrame();
    if (wait == null) {
      schedule();
    } else {
      _pendingSchedule = schedule;
      _deferred = Timer(wait, _releaseDeferred);
    }
  }

  // Probe only while something is held back (a limit or paused decoration);
  // an unlimited client with decoration running reads nothing when idle.
  void _updateProbe() {
    final held = _read != null && (interval != null || !_decorativeMotion.value);
    if (!held) {
      _probe?.cancel();
      _probe = null;
      return;
    }
    _probe ??= Timer.periodic(probeEvery, (_) => _refreshIfStale());
  }
}

/// The client's binding: WidgetsFlutterBinding with a [FrameGovernor] in
/// front of every frame request. Forced and warm-up frames are not delayed.
class StarBridgeBinding extends WidgetsFlutterBinding {
  StarBridgeBinding._(this.governor);

  final FrameGovernor governor;

  /// Use instead of [WidgetsFlutterBinding.ensureInitialized], once per
  /// engine, before anything else creates a binding. An existing binding
  /// (tests, or a second call) is returned unchanged.
  static WidgetsBinding ensureInitialized(FrameSurface surface) {
    WidgetsBinding? existing;
    try {
      existing = WidgetsBinding.instance;
    } catch (_) {}
    if (existing != null) return existing;
    final binding = StarBridgeBinding._(FrameGovernor(surface: surface));
    // The periodic timer keeps the log alive for the isolate's lifetime.
    FrameGovernorLog.start(binding.governor);
    return binding;
  }

  @override
  void scheduleFrame() {
    if (hasScheduledFrame || !framesEnabled) return;
    governor.request(() => super.scheduleFrame());
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    governor.frameStarted();
    super.handleBeginFrame(rawTimeStamp);
  }
}

/// While "记录界面流畅度" is on, each surface appends one line a minute:
/// frames per mode and delayed requests. The switch's marker file (the same
/// one [FramePaceRecorder] uses) is checked every minute, so turning it on or
/// off in settings takes effect for every open surface within a minute.
/// Counts only; nothing about the game or other programs is written.
final class FrameGovernorLog {
  @visibleForTesting
  FrameGovernorLog(this._governor, this._file, this._marker);

  final FrameGovernor _governor;
  final File _file;
  final File _marker;

  static void start(FrameGovernor governor) {
    try {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null ||
          local.isEmpty ||
          Platform.environment.containsKey('FLUTTER_TEST')) {
        return;
      }
      final sep = Platform.pathSeparator;
      final directory = '$local${sep}StarBridge${sep}Diagnostics';
      final log = FrameGovernorLog(
        governor,
        File(
          '$directory${sep}frame-governor-${governor.surface.name}.jsonl',
        ),
        File('$directory${sep}frame-pace.on'),
      );
      Timer.periodic(const Duration(minutes: 1), (_) {
        unawaited(log.tick());
      });
    } catch (_) {}
  }

  /// One minute's line, written only while the switch is on. Counts are
  /// always reset, so turning the switch on later starts from a fresh minute.
  @visibleForTesting
  Future<void> tick() async {
    final frames = Map.of(_governor.frames);
    final deferrals = _governor.deferrals;
    _governor.frames.clear();
    _governor.deferrals = 0;
    bool on;
    try {
      on = await _marker.exists();
    } catch (_) {
      on = false;
    }
    if (!on || (frames.isEmpty && deferrals == 0)) return;
    final line = jsonEncode({
      'at': DateTime.now().toUtc().toIso8601String(),
      'surface': _governor.surface.name,
      'mode': _governor.mode.name,
      'focusedCap': focusedWithGameFps,
      'frames': {for (final e in frames.entries) e.key.name: e.value},
      'deferrals': deferrals,
    });
    try {
      if (await _file.exists() && await _file.length() > 1024 * 1024) {
        await _file.writeAsString('$line\n', flush: true);
      } else {
        await _file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      }
    } catch (_) {}
  }
}
