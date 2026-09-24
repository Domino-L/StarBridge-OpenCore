// Temporary, opt-in local acceptance instrumentation. Remove after diagnosis.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/widgets.dart';

class PageFrameProbe extends StatefulWidget {
  const PageFrameProbe({required this.route, required this.child, super.key});
  final String route;
  final Widget child;
  @override
  State<PageFrameProbe> createState() => _PageFrameProbeState();
}

class _PageFrameProbeState extends State<PageFrameProbe> {
  final _rows = <Map<String, Object>>[];
  Timer? _flushTimer;
  Timer? _stopTimer;
  IOSink? _sink;
  int _frames = 0;
  @override
  void initState() {
    super.initState();
    final path = Platform.environment['STARBRIDGE_FRAME_TRACE_PATH'];
    if (path == null || path.isEmpty) return;
    _sink = File(path).openWrite();
    unawaited(_sink!.done.catchError((Object _) {}));
    _mark();
    WidgetsBinding.instance.addTimingsCallback(_timings);
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flush());
    _stopTimer = Timer(const Duration(minutes: 10), _stop);
  }

  void _mark() => _rows.add({
    'kind': 'route',
    'us': Timeline.now,
    // Static feature route only, never parameters or account content.
    'route': widget.route.split('?').first,
    'width': WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize
        .width,
    'height': WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize
        .height,
    'dpr':
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
  });

  @override
  void didUpdateWidget(covariant PageFrameProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sink != null && oldWidget.route != widget.route) _mark();
  }

  void _timings(List<FrameTiming> timings) {
    for (final frame in timings) {
      if (_frames++ >= 12000) {
        _stop();
        return;
      }
      _rows.add({
        'kind': 'frame',
        'us': frame.timestampInMicroseconds(FramePhase.vsyncStart),
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
        'totalUs': frame.totalSpan.inMicroseconds,
        'layerCacheCount': frame.layerCacheCount,
        'layerCacheBytes': frame.layerCacheBytes,
        'pictureCacheCount': frame.pictureCacheCount,
      });
    }
  }

  void _flush() {
    final sink = _sink;
    if (sink == null || _rows.isEmpty) return;
    sink.write(_rows.map(jsonEncode).join('\n'));
    sink.writeln();
    _rows.clear();
  }

  void _stop() {
    if (_sink == null) return;
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _flushTimer?.cancel();
    _stopTimer?.cancel();
    _flush();
    final sink = _sink;
    _sink = null;
    if (sink != null) unawaited(sink.close().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
