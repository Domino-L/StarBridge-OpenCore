import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ship_statistics_view.dart';
import 'community_ships_port.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';

class CommunityShipStatisticsPanel extends StatefulWidget {
  const CommunityShipStatisticsPanel({
    required this.port,
    required this.targetRef,
    required this.culture,
    required this.firstPage,
    this.loadingHeight,
    this.onHeightChanged,
    super.key,
  });
  final CommunityShipsPort port;
  final String targetRef, culture;
  final CommunityShipsPage? firstPage;
  final double? loadingHeight;
  final ValueChanged<double>? onHeightChanged;
  @override
  State<CommunityShipStatisticsPanel> createState() =>
      _CommunityShipStatisticsPanelState();
}

class _CommunityShipStatisticsPanelState
    extends State<CommunityShipStatisticsPanel> {
  CommunityShipStatistics? statistics;
  bool failed = false, loading = false;
  int epoch = 0;
  final statisticsLayoutKey = GlobalKey();
  double? lastStatisticsHeight;
  DialogRoute<void>? detailsRoute;
  void dismissDetails() {
    final route = detailsRoute;
    detailsRoute = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  late StreamSubscription<void> subscription;
  void subscribe() => subscription = widget.port.invalidations.listen((_) {
    epoch++;
    dismissDetails();
    if (mounted) {
      setState(() {
        statistics = null;
        failed = true;
        loading = false;
      });
    }
  });
  String t(String key) => communityShipsText(context, key);
  @override
  void initState() {
    super.initState();
    subscribe();
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityShipStatisticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      unawaited(subscription.cancel());
      subscribe();
    }
    if (oldWidget.targetRef != widget.targetRef ||
        oldWidget.culture != widget.culture ||
        oldWidget.port != widget.port) {
      epoch++;
      statistics = null;
      dismissDetails();
      _load();
    } else if (!loading &&
        statistics == null &&
        !failed &&
        widget.firstPage != null) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.firstPage == null) return;
    final request = ++epoch;
    dismissDetails();
    setState(() {
      loading = true;
      failed = false;
      statistics = null;
    });
    void current() {
      if (!mounted || epoch != request) throw StateError('Stale statistics');
    }

    try {
      final result = await readCommunityShipStatistics(
        widget.port,
        widget.targetRef,
        widget.culture,
        firstPage: widget.firstPage,
        checkCurrent: current,
      );
      current();
      setState(() {
        statistics = result;
        loading = false;
      });
    } catch (_) {
      if (mounted && epoch == request) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    dismissDetails();
    epoch++;
    unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    final colors = context.tokens.colors;
    if (stats == null) {
      return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          // Preserve the measured layout while a filter invalidates/reloads
          // the same full inventory. High-frequency controls below must not jump.
          height:
              lastStatisticsHeight ??
              widget.loadingHeight ??
              (constraints.maxWidth >= 760 ? 232 : 474),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(failed ? 'statisticsUnavailable' : 'statisticsLoading'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
              if (failed)
                TextButton(onPressed: _load, child: Text(t('imageRetry'))),
            ],
          ),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = statisticsLayoutKey.currentContext?.size;
      if (size != null) {
        lastStatisticsHeight = size.height;
        widget.onHeightChanged?.call(size.height);
      }
    });
    return CommunityShipStatisticsView(
      key: statisticsLayoutKey,
      statistics: stats,
      onDetails: (dispatch) async {
        if (detailsRoute != null) return;
        final route = DialogRoute<void>(
          context: context,
          builder: (_) => CommunityShipStatisticsDetails(
            statistics: stats,
            dispatch: dispatch,
          ),
        );
        detailsRoute = route;
        await Navigator.of(context).push(route);
        if (detailsRoute == route) detailsRoute = null;
      },
    );
  }
}
