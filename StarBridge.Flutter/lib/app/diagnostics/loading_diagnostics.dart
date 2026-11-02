import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/widgets.dart';

import '../../shared/diagnostics/loading_metrics.dart';
import 'loading_tour.dart';

const _loadingTraceZoneKey = #starBridgeLoadingTrace;

/// Explicit local opt-in. No process-global mutable state, and no output during
/// ordinary startup. The diagnostic zone is also the Flutter binding's zone.
abstract final class LoadingDiagnostics {
  static bool get enabled => LoadingMetrics.current?.stopped == false;
  static String? auxiliaryTracePath(
    Map<String, String> environment,
    LoadingAuxiliarySurface surface,
  ) {
    final path = environment['STARBRIDGE_LOADING_TRACE_PATH'];
    if (path == null ||
        path.isEmpty ||
        !File(path).isAbsolute ||
        path.startsWith(r'\\')) {
      return null;
    }
    return '$path.${surface.name}.jsonl';
  }

  static void runAuxiliary(
    Map<String, String> environment,
    LoadingAuxiliarySurface surface,
    VoidCallback launch,
  ) {
    final path = auxiliaryTracePath(environment, surface);
    run(
      path == null
          ? const {}
          : {
              'STARBRIDGE_LOADING_TRACE_PATH': path,
              // Auxiliary engines never navigate or bootstrap a second account.
            },
      launch,
      auxiliarySurface: surface,
    );
  }

  static void run(
    Map<String, String> environment,
    VoidCallback launch, {
    LoadingAuxiliarySurface? auxiliarySurface,
  }) {
    final path = environment['STARBRIDGE_LOADING_TRACE_PATH'];
    if (path == null ||
        path.isEmpty ||
        !File(path).isAbsolute ||
        path.startsWith(r'\\')) {
      WidgetsFlutterBinding.ensureInitialized();
      launch();
      return;
    }
    final trace = _LoadingTrace(
      File(path),
      tourEnabled: environment['STARBRIDGE_LOADING_TOUR'] == 'primary-v1',
      auxiliarySurface: auxiliarySurface,
    );
    runZoned(
      () {
        WidgetsFlutterBinding.ensureInitialized();
        trace.start();
        launch();
      },
      zoneValues: {
        loadingMetricsZoneKey: trace.metrics,
        _loadingTraceZoneKey: trace,
      },
    );
  }

  static void stage(String value) {
    LoadingMetrics.current?.stage(value);
    (Zone.current[_loadingTraceZoneKey] as _LoadingTrace?)?.stage(value);
  }

  static void route(String value) => LoadingMetrics.current?.route(value);
  static VoidCallback? bindTour(LoadingTourNavigate navigate) =>
      (Zone.current[_loadingTraceZoneKey] as _LoadingTrace?)?.tour?.bind(
        navigate,
      );

  /// Only a running opt-in tour receives the window; otherwise a no-op.
  static VoidCallback? registerTourWindow(
    String kind,
    LoadingTourWindow window,
  ) => (Zone.current[_loadingTraceZoneKey] as _LoadingTrace?)?.tour
      ?.registerWindow(kind, window);
}

final class _LoadingTrace with WidgetsBindingObserver {
  _LoadingTrace(this.file, {bool tourEnabled = false, this.auxiliarySurface}) {
    metrics = LoadingMetrics(
      nowUs: () => Timeline.now - _originUs,
      write: (event) {
        _buffer.add(event);
        if (_buffer.length >= 256) _flush();
      },
    );
    metrics.mark(
      LoadingMilestone.dartEntry,
      wallUtcUs: DateTime.now().toUtc().microsecondsSinceEpoch,
      clockOriginUs: _originUs,
    );
    if (tourEnabled) {
      tour = LoadingTour(metrics, shellVisible: _shellVisible.future);
    }
  }
  final File file;
  final LoadingAuxiliarySurface? auxiliarySurface;
  final _originUs = Timeline.now;
  late final LoadingMetrics metrics;
  LoadingTour? tour;
  // The shell is shown when startup completes; DL-131 builds it offstage.
  final _shellVisible = Completer<void>();
  void stage(String value) {
    if (value == 'complete' && !_shellVisible.isCompleted) {
      _shellVisible.complete();
    }
  }

  IOSink? _sink;
  final _buffer = <Map<String, Object>>[];
  Timer? _flushTimer, _stopTimer;
  bool _stopped = false;

  void start() {
    try {
      final sink = _sink = file.openWrite();
      unawaited(
        sink.done.catchError((Object _) {
          stop();
        }),
      );
      metrics.stage('connecting');
      metrics.imageTransferRecorderPresent();
      if (auxiliarySurface != null) {
        WidgetsBinding.instance.addObserver(this);
        _lifecycle(WidgetsBinding.instance.lifecycleState);
      }
      WidgetsBinding.instance.addTimingsCallback(_frames);
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
        if (!_stopped) metrics.mark(LoadingMilestone.firstRaster);
      });
      _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          final images = PaintingBinding.instance.imageCache;
          metrics.memory(
            rssBytes: ProcessInfo.currentRss,
            imageBytes: images.currentSizeBytes,
            liveImages: images.liveImageCount,
            pendingImages: images.pendingImageCount,
          );
          _flush();
          if (metrics.stopped) stop();
        } catch (_) {
          stop();
        }
      });
      _stopTimer = Timer(const Duration(minutes: 10), stop);
    } catch (_) {
      stop();
    }
  }

  void _frames(List<FrameTiming> frames) {
    for (final frame in frames) {
      metrics.frame(
        buildUs: frame.buildDuration.inMicroseconds,
        rasterUs: frame.rasterDuration.inMicroseconds,
        totalUs: frame.totalSpan.inMicroseconds,
        vsyncUs:
            frame.timestampInMicroseconds(FramePhase.vsyncStart) - _originUs,
        buildStartUs:
            frame.timestampInMicroseconds(FramePhase.buildStart) - _originUs,
        buildFinishUs:
            frame.timestampInMicroseconds(FramePhase.buildFinish) - _originUs,
        rasterFinishUs:
            frame.timestampInMicroseconds(FramePhase.rasterFinish) - _originUs,
      );
    }
  }

  void _lifecycle(AppLifecycleState? state) {
    final surface = auxiliarySurface;
    if (surface != null) {
      metrics.auxiliaryLifecycle(
        surface,
        state: state?.name,
        framesEnabled: WidgetsBinding.instance.framesEnabled,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _lifecycle(state);

  void _flush() {
    if (_buffer.isEmpty || _sink == null) return;
    try {
      _sink!.write(_buffer.map(jsonEncode).join('\n'));
      _sink!.writeln();
      _buffer.clear();
    } catch (_) {
      _buffer.clear();
      stop();
    }
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    tour?.stop();
    if (auxiliarySurface != null) WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_frames);
    _flushTimer?.cancel();
    _stopTimer?.cancel();
    metrics.mark(LoadingMilestone.stopped);
    metrics.stop();
    _flush();
    final sink = _sink;
    _sink = null;
    if (sink != null) unawaited(sink.close().catchError((Object _) {}));
  }
}

class LoadingRouteProbe extends StatefulWidget {
  const LoadingRouteProbe({
    required this.route,
    required this.child,
    super.key,
  });
  final String route;
  final Widget child;
  @override
  State<LoadingRouteProbe> createState() => _LoadingRouteProbeState();
}

class _LoadingRouteProbeState extends State<LoadingRouteProbe> {
  @override
  void initState() {
    super.initState();
    LoadingDiagnostics.route(widget.route);
  }

  @override
  void didUpdateWidget(LoadingRouteProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) LoadingDiagnostics.route(widget.route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
