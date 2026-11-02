import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'loading_metrics.dart';

/// Observes the exact content branch a page paints. No requests, timers or
/// presentation are added. A child behind zero opacity does not paint, and an
/// outgoing route cannot report readiness for the new destination. Engine
/// FrameTiming subsequently confirms rasterization of that same painted scene.
class LoadingContentProbe extends StatelessWidget {
  const LoadingContentProbe({
    required this.route,
    required this.status,
    required this.child,
    this.items = 0,
    this.visualPart,
    super.key,
  });

  final String route;
  final LoadingContentStatus status;
  final int items;
  final LoadingVisualPart? visualPart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = LoadingMetrics.current;
    // Retain the render wrapper after the bounded recorder stops. Removing it
    // would replace the child's element and discard retained workspace state.
    if (metrics == null) return child;
    return _ContentPaintProbe(
      metrics: metrics,
      route: route,
      status: status,
      items: items,
      visualPart: visualPart,
      child: child,
    );
  }
}

class _ContentPaintProbe extends SingleChildRenderObjectWidget {
  const _ContentPaintProbe({
    required this.metrics,
    required this.route,
    required this.status,
    required this.items,
    required this.visualPart,
    required super.child,
  });
  final LoadingMetrics metrics;
  final String route;
  final LoadingContentStatus status;
  final int items;
  final LoadingVisualPart? visualPart;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ContentPaintRecorder(metrics, route, status, items, visualPart);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ContentPaintRecorder renderObject,
  ) => renderObject.configure(metrics, route, status, items, visualPart);
}

class _ContentPaintRecorder extends RenderProxyBox {
  _ContentPaintRecorder(
    this.metrics,
    this.route,
    this.status,
    this.items,
    this.visualPart,
  );
  LoadingMetrics metrics;
  String route;
  LoadingContentStatus status;
  int items;
  LoadingVisualPart? visualPart;
  (int, LoadingContentStatus, int)? _last;

  void configure(
    LoadingMetrics recorder,
    String nextRoute,
    LoadingContentStatus nextStatus,
    int nextItems,
    LoadingVisualPart? nextVisualPart,
  ) {
    if (metrics == recorder &&
        route == nextRoute &&
        status == nextStatus &&
        items == nextItems &&
        visualPart == nextVisualPart &&
        _last?.$1 == recorder.visitFor(nextRoute)) {
      return;
    }
    metrics = recorder;
    route = nextRoute;
    status = nextStatus;
    items = nextItems;
    visualPart = nextVisualPart;
    _last = null;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final visit = metrics.visitFor(route);
    if (visit == null) return;
    final value = (visit, status, items);
    if (_last == value) return;
    _last = value;
    final part = visualPart;
    if (part == null) {
      metrics.contentPainted(route, status, items: items);
    } else {
      metrics.visualPainted(route, part, status, items: items);
    }
  }
}
