import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming, Size, TimingsCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'frame_pace_log.dart';
import 'frame_pace_summary.dart';

/// What else is happening on the desktop, as presence only.
typedef GameActivity = ({
  bool? maximized,
  bool? starCitizen,
  bool? otherFullscreen,
});

/// Opt-in "记录界面流畅度（排查卡顿用）". Off by default; while off nothing is
/// registered with the engine and no timer runs. The switch lives on this
/// device only, as a marker file next to the log.
final class FramePaceRecorder {
  FramePaceRecorder({
    required this.directory,
    Future<GameActivity?> Function()? readActivity,
    void Function(TimingsCallback)? addTimings,
    void Function(TimingsCallback)? removeTimings,
    Size? Function()? windowSize,
    DateTime Function()? now,
    int Function()? clockUs,
    this.interval = const Duration(minutes: 1),
    int maxBytes = 1024 * 1024,
  }) : _readActivity = readActivity ?? readNativeGameActivity,
       _addTimings = addTimings ?? WidgetsBinding.instance.addTimingsCallback,
       _removeTimings =
           removeTimings ?? WidgetsBinding.instance.removeTimingsCallback,
       _windowSize = windowSize ?? _primaryWindowSize,
       _now = now ?? DateTime.now,
       _clockUs = clockUs ?? (() => Timeline.now),
       log = FramePaceLog(directory, maxBytes: maxBytes) {
    var on = false;
    try {
      on = _marker.existsSync();
    } catch (_) {}
    if (on) _start();
  }

  /// Only the real client records; tests and review shells get no recorder.
  static FramePaceRecorder? fromEnvironment(Map<String, String> environment) {
    final local = environment['LOCALAPPDATA'];
    if (local == null ||
        local.isEmpty ||
        environment.containsKey('FLUTTER_TEST') ||
        !Directory(local).isAbsolute) {
      return null;
    }
    final separator = Platform.pathSeparator;
    return FramePaceRecorder(
      directory: Directory(
        '$local${separator}StarBridge${separator}Diagnostics',
      ),
    );
  }

  static const markerName = 'frame-pace.on';

  final Directory directory;
  final Duration interval;
  final FramePaceLog log;
  final Future<GameActivity?> Function() _readActivity;
  final void Function(TimingsCallback) _addTimings;
  final void Function(TimingsCallback) _removeTimings;
  final Size? Function() _windowSize;
  final DateTime Function() _now;
  // The engine's frame clock: page switches and frame timestamps compare.
  final int Function() _clockUs;
  final _enabled = ValueNotifier(false);
  String _page = '/';
  // Timings arrive in batches up to a second late. The shell reports a page
  // while building that page's first frame, so a frame belongs to the page
  // current when its build finished, not when its batch arrives.
  final _switches = <(int, String)>[];
  String _pageBeforeSwitches = '/';
  // Frames built before this round began belong to an earlier round.
  int _roundStartUs = 0;
  FramePaceSummary? _summary;
  Timer? _timer;
  bool _disposed = false;

  ValueListenable<bool> get enabled => _enabled;

  File get _marker =>
      File('${directory.path}${Platform.pathSeparator}$markerName');

  /// The shell's current page; a plain field write while recording is off.
  set page(String value) {
    if (value == _page) return;
    if (_summary case final summary?) {
      if (_switches.length >= 64) {
        _pageBeforeSwitches = _switches.removeAt(0).$2;
      }
      _switches.add((_clockUs(), value));
      summary.page = value;
    }
    _page = value;
  }

  String _pageAt(int us) {
    var page = _pageBeforeSwitches;
    for (final (at, next) in _switches) {
      if (at > us) break;
      page = next;
    }
    return page;
  }

  /// Saves the choice first; recording follows only what was saved.
  Future<bool> setEnabled(bool value) async {
    if (_disposed) return false;
    try {
      if (value) {
        await directory.create(recursive: true);
        await _marker.writeAsString('1', flush: true);
      } else if (await _marker.exists()) {
        await _marker.delete();
      }
    } catch (_) {
      return false;
    }
    if (_disposed) return false;
    if (value) {
      _start();
    } else {
      await _stop(writeLast: true);
    }
    return true;
  }

  void _start() {
    if (_summary != null || _disposed) return;
    _summary = FramePaceSummary(_page);
    _switches.clear();
    _pageBeforeSwitches = _page;
    _roundStartUs = _clockUs();
    _addTimings(_frames);
    _timer = Timer.periodic(interval, (_) => unawaited(writeMinute()));
    _enabled.value = true;
  }

  Future<void> _stop({required bool writeLast}) async {
    final summary = _summary;
    if (summary == null) return;
    _summary = null;
    _removeTimings(_frames);
    _timer?.cancel();
    _timer = null;
    if (!_disposed) _enabled.value = false;
    if (writeLast) await _write(summary);
  }

  void _frames(List<FrameTiming> frames) {
    final summary = _summary;
    if (summary == null) return;
    var latest = -1;
    for (final frame in frames) {
      final built = frame.timestampInMicroseconds(FramePhase.buildFinish);
      if (built < _roundStartUs) continue;
      if (built > latest) latest = built;
      summary.frame(
        buildUs: frame.buildDuration.inMicroseconds,
        rasterUs: frame.rasterDuration.inMicroseconds,
        totalUs: frame.totalSpan.inMicroseconds,
        page: _pageAt(built),
      );
    }
    // Frames come in order: switches before the latest frame are settled.
    while (_switches.isNotEmpty && _switches.first.$1 <= latest) {
      _pageBeforeSwitches = _switches.removeAt(0).$2;
    }
  }

  /// Closes the current minute. Called by the timer; public for tests.
  @visibleForTesting
  Future<void> writeMinute() async {
    final summary = _summary;
    if (summary != null) await _write(summary);
  }

  /// The minute is taken at once, so a stop or another tick while the native
  /// answer is pending can neither lose nor repeat frames.
  Future<void> _write(FramePaceSummary summary) async {
    final size = _windowSize();
    final lines = summary.take(
      now: _now(),
      context: {
        'width': size?.width.round(),
        'height': size?.height.round(),
        'maximized': null,
        'starCitizen': null,
        'otherFullscreen': null,
      },
    );
    GameActivity? activity;
    try {
      activity = await _readActivity();
    } catch (_) {}
    // Released while the native answer was pending: nothing more is written.
    if (_disposed) return;
    for (final line in lines) {
      line['maximized'] = activity?.maximized;
      line['starCitizen'] = activity?.starCitizen;
      line['otherFullscreen'] = activity?.otherFullscreen;
    }
    await log.append(lines);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_stop(writeLast: false));
    _enabled.dispose();
  }

  static Size? _primaryWindowSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? null : views.first.physicalSize;
  }
}

const _windowChannel = MethodChannel('starbridge/window-chrome');

Future<GameActivity?> readNativeGameActivity() async {
  try {
    final value = await _windowChannel.invokeMapMethod<String, Object?>(
      'readGameActivity',
    );
    if (value == null) return null;
    bool? flag(String key) => value[key] is bool ? value[key] as bool : null;
    return (
      maximized: flag('maximized'),
      starCitizen: flag('starCitizen'),
      otherFullscreen: flag('otherFullscreen'),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Hands the application's recorder to the shell and the diagnostics page.
class FramePaceScope extends InheritedWidget {
  const FramePaceScope({
    required this.recorder,
    required super.child,
    super.key,
  });

  final FramePaceRecorder? recorder;

  /// No dependency: the recorder never changes for a running client.
  static FramePaceRecorder? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FramePaceScope>()?.recorder;

  @override
  bool updateShouldNotify(FramePaceScope oldWidget) =>
      recorder != oldWidget.recorder;
}
