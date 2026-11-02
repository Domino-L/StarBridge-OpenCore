import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Loads the next ship page while the reader still has two screens ahead, like
/// the trading hall (user 2026-10-30: no manual loading). Metrics also cover a
/// first page shorter than a maximized window, which never scrolls at all.
class CommunityShipsPrefetch extends StatefulWidget {
  const CommunityShipsPrefetch({
    required this.child,
    required this.canLoad,
    required this.load,
    super.key,
  });

  final Widget child;

  /// False while reading, after a failure, or with nothing more to read.
  final bool canLoad;
  final VoidCallback load;

  @override
  State<CommunityShipsPrefetch> createState() => _CommunityShipsPrefetchState();
}

class _CommunityShipsPrefetchState extends State<CommunityShipsPrefetch> {
  ScrollMetrics? _metrics;
  bool _scheduled = false;

  void _check() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final metrics = _metrics;
      if (!mounted ||
          !widget.canLoad ||
          metrics == null ||
          metrics.extentAfter > math.max(800, metrics.viewportDimension * 2)) {
        return;
      }
      widget.load();
    });
  }

  bool _observe(ScrollMetrics metrics, int depth) {
    if (depth == 0) {
      _metrics = metrics;
      _check();
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant CommunityShipsPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _observe(n.metrics, n.depth),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _observe(n.metrics, n.depth),
          child: widget.child,
        ),
      );
}
