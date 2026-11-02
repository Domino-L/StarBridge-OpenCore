import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_fleet_statistics_dialog.dart';
import 'community_image_decoder.dart';
import 'community_ship_statistics.dart';
import 'community_ships_port.dart';
import 'community_ships_summary_strip.dart';

/// Reads the whole shared inventory once, again only when it changed, and shows
/// it as the one-line summary strip. A later read replaces what is shown when it
/// ends, or says it could not; the full statistics open in a dialog (user
/// decision 2026-10-29, option D). The loaded statistics are also reported
/// upward: the ships page draws its filter counts and owner view from them.
class CommunityShipStatisticsPanel extends StatefulWidget {
  const CommunityShipStatisticsPanel({
    required this.port,
    required this.targetRef,
    required this.culture,
    required this.firstPage,
    this.initial,
    this.onStatistics,
    this.avatarOf,
    this.decoder,
    super.key,
  });
  final CommunityShipsPort port;
  final String targetRef, culture;
  final CommunityShipsPage? firstPage;

  /// The inventory held from an earlier visit, shown without a read.
  final CommunityShipStatistics? initial;

  /// Null again whenever the inventory is invalidated or read from nothing.
  final ValueChanged<CommunityShipStatistics?>? onStatistics;
  final Uint8List? Function(String memberRef)? avatarOf;
  final CommunityImageDecoder? decoder;
  @override
  State<CommunityShipStatisticsPanel> createState() =>
      _CommunityShipStatisticsPanelState();
}

class _CommunityShipStatisticsPanelState
    extends State<CommunityShipStatisticsPanel> {
  CommunityShipStatistics? statistics;
  bool failed = false, loading = false;
  int epoch = 0;
  StarBridgeDialogRoute<void>? detailsRoute;
  void dismissDetails() {
    final route = detailsRoute;
    detailsRoute = null;
    retireStarBridgeDialog(route);
  }

  // Never during a build: the parent sets state on this.
  void _publish(CommunityShipStatistics? value) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onStatistics?.call(value);
      });

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
      _publish(null);
    }
  });
  @override
  void initState() {
    super.initState();
    subscribe();
    statistics = widget.initial;
    if (statistics == null) {
      _load();
    } else {
      _publish(statistics);
      if (_inventoryChanged(widget.firstPage)) _load();
    }
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
      _publish(null);
      _load();
    } else if (!loading &&
        statistics == null &&
        !failed &&
        widget.firstPage != null) {
      _load();
    } else if (!loading &&
        !identical(oldWidget.firstPage, widget.firstPage) &&
        _inventoryChanged(widget.firstPage)) {
      _load();
    }
  }

  /// Any page tells whether the count moved, whatever its filter. Only the
  /// unfiltered first page can compare revisions, which hash the query.
  bool _inventoryChanged(CommunityShipsPage? page) {
    final held = statistics;
    if (page == null || held == null) return false;
    if (page.totalCount != held.ships.length) return true;
    return page.offset == 0 &&
        page.query == CommunityShipQuery(culture: widget.culture) &&
        page.revision != held.revision;
  }

  Future<void> _load() async {
    final started = widget.firstPage;
    if (started == null) return;
    final request = ++epoch;
    setState(() {
      loading = true;
      failed = false;
    });
    if (statistics == null) _publish(null);
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
      dismissDetails();
      setState(() {
        statistics = result;
        loading = false;
      });
      // The list moved on while this was being read: its answer is older than
      // what is on screen, so it is not published. One new page, one reread.
      if (!identical(widget.firstPage, started) &&
          _inventoryChanged(widget.firstPage)) {
        unawaited(_load());
        return;
      }
      _publish(result);
    } catch (_) {
      if (mounted && epoch == request) {
        // The held answer is known to be old by now: say so, with the retry.
        dismissDetails();
        setState(() {
          statistics = null;
          failed = true;
          loading = false;
        });
        _publish(null);
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

  Future<void> _openDetails(CommunityShipStatistics stats) async {
    if (detailsRoute != null) return;
    StarBridgeDialogRoute<void>? opened;
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: false,
      builder: (_) => CommunityFleetStatisticsDialog(statistics: stats),
      onRouteCreated: (route) => detailsRoute = opened = route,
    );
    if (detailsRoute == opened) detailsRoute = null;
  }

  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    return CommunityShipsSummaryStrip(
      statistics: stats,
      loading: loading,
      failed: failed,
      onRetry: _load,
      onDetails: stats == null ? null : () => _openDetails(stats),
      avatarOf: widget.avatarOf,
      decoder: widget.decoder,
    );
  }
}
