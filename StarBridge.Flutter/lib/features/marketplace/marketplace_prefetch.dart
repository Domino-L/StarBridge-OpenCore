import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'marketplace_copy.dart';
import 'marketplace_states.dart' show marketRetryAction;
import 'marketplace_port.dart';

bool marketHasMore(MarketRead? read) =>
    read != null &&
    read.data['pageEnd'] != true &&
    read.total != null &&
    read.rows.length < read.total!;

/// Fetch while the reader still has two screens of content ahead. Metrics also
/// cover initial short pages and window resizing without requiring a scroll.
class MarketPrefetch extends StatefulWidget {
  const MarketPrefetch({
    super.key,
    required this.child,
    required this.read,
    required this.loading,
    required this.failed,
    required this.load,
  });
  final Widget child;
  final MarketRead? read;
  final bool loading, failed;
  final Future<void> Function() load;
  @override
  State<MarketPrefetch> createState() => _MarketPrefetchState();
}

class _MarketPrefetchState extends State<MarketPrefetch> {
  ScrollMetrics? _metrics;
  bool _scheduled = false, _request = false;
  void _check() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          _request ||
          widget.loading ||
          widget.failed ||
          !marketHasMore(widget.read)) {
        return;
      }
      final metrics = _metrics;
      if (metrics == null ||
          metrics.extentAfter > math.max(800, metrics.viewportDimension * 2)) {
        return;
      }
      _request = true;
      unawaited(
        widget.load().whenComplete(() {
          _request = false;
        }),
      );
    });
  }

  @override
  void didUpdateWidget(covariant MarketPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.read != widget.read) _metrics = null;
    _check();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) {
          if (n.depth == 0) {
            _metrics = n.metrics;
            _check();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) {
              _metrics = n.metrics;
              _check();
            }
            return false;
          },
          child: widget.child,
        ),
      );
}

class MarketPageStatus extends StatelessWidget {
  const MarketPageStatus({
    super.key,
    required this.read,
    required this.loading,
    required this.failed,
    required this.load,
  });
  final MarketRead read;
  final bool loading, failed;
  final Future<void> Function() load;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(
      child: failed
          ? marketRetryAction(
              loading ? null : load,
              key: const Key('market-page-status-retry'),
            )
          : Text(
              loading
                  ? marketText(context, 'loading')
                  : marketHasMore(read) || read.total == null
                  ? ''
                  : marketLocale(context) == 'en'
                  ? 'All ${read.rows.length} shown'
                  : marketLocale(context) == 'hant'
                  ? '已顯示全部，共 ${read.rows.length} 項'
                  : '已显示全部，共 ${read.rows.length} 项',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    ),
  );
}
