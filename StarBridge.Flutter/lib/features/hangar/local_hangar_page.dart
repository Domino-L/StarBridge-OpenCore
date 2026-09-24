import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../ships/ship_display_names.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_row.dart';
import 'local_hangar_summary.dart';
import 'cached_local_hangar.dart';

/// The caller mounts this only while signed in and recreates it per generation.
class LocalHangarPage extends StatefulWidget {
  const LocalHangarPage({
    required this.port,
    required this.onRead,
    this.extraAction,
    super.key,
  });

  final LocalHangarPort port;
  final VoidCallback onRead;
  final Widget? extraAction;

  @override
  State<LocalHangarPage> createState() => _LocalHangarPageState();
}

class _LocalHangarPageState extends State<LocalHangarPage> {
  LocalHangarSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  int _epoch = 0;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  bool _former = false;
  final _clock = Stopwatch()..start();
  final _arrivals = <String, Duration>{};
  DialogRoute<void>? _detailsRoute;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant LocalHangarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.port, widget.port)) {
      _closeDetails();
      _snapshot = null;
      _search.clear();
      _query = '';
      _former = false;
      _arrivals.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _restore();
    }
  }

  void _restore() {
    final port = widget.port;
    _snapshot = port is CachedLocalHangar ? port.snapshot : null;
    _loading = _snapshot == null;
    _failed = false;
    if (_snapshot case final snapshot?) {
      for (final ship in [...snapshot.ships, ...snapshot.formerShips]) {
        // A cached arrival is finished regardless of its category's duration.
        _arrivals[ship.id] = const Duration(days: -1);
      }
    }
    if (_loading) unawaited(_refresh());
  }

  @override
  void dispose() {
    _epoch++;
    _closeDetails();
    _clock.stop();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final snapshot = await widget.port.read();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _snapshot = snapshot;
        final ids = [
          ...snapshot.ships,
          ...snapshot.formerShips,
        ].map((ship) => ship.id).toSet();
        _arrivals.removeWhere((id, _) => !ids.contains(id));
        for (final id in ids) {
          _arrivals.putIfAbsent(id, () => _clock.elapsed);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _name(LocalHangarShip ship) => ShipDisplayNames.primary(
    Localizations.localeOf(context),
    original: ship.title,
    simplifiedChinese: ship.cn,
    traditionalChinese: ship.tw,
  );

  void _closeDetails() {
    final route = _detailsRoute;
    _detailsRoute = null;
    if (route == null) return;
    // Updates/disposal may run while Navigator is locked. Remove this route,
    // never the caller's top route, once the current frame has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) navigator.removeRoute(route);
    });
  }

  void _details(LocalHangarShip ship) {
    if (_detailsRoute != null) return;
    final c = LocalHangarCopy(context);
    final title = _name(ship);
    final item = LocalHangarPresentation.fromSaved(ship);
    final navigator = Navigator.of(context, rootNavigator: true);
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        context.tokens.motion.surfaceEnter == Duration.zero;
    final route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: context.tokens.colors.scrim,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      animationStyle: reduced ? AnimationStyle.noAnimation : null,
      builder: (context) {
        Widget field(String label, String value, {bool price = false}) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  SelectableText(
                    value,
                    style: price
                        ? TextStyle(color: context.tokens.colors.info)
                        : null,
                  ),
                ],
              ),
            );
        return AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_former) Text(c.formerlyOwned),
              if (_former && ship.removedAt != null)
                field(c.removedAt, c.dateTime(context, ship.removedAt!)),
              if (item.bundledImage != null) ...[
                LocalHangarShipImage(
                  item: item,
                  width: 300,
                  height: 105,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 12),
              ],
              field(c.original, ship.title),
              if (ship.liner?.trim().isNotEmpty == true)
                field(c.manufacturer, ship.liner!.trim()),
              if (ship.addedAt case final addedAt?)
                field(c.addedAt, c.dateTime(context, addedAt)),
              if (item.role != 'unknown')
                field(c.categoryLabel, c.category(item.role)),
              if (item.status != 'unknown')
                field(c.delivery, c.status(item.status)),
              if (item.priceCents case final cents?)
                field(c.priceLabel, '${c.usd(cents / 100)} USD', price: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(c.close),
            ),
          ],
        );
      },
    );
    _detailsRoute = route;
    unawaited(
      navigator.push(route).whenComplete(() {
        if (identical(_detailsRoute, route)) _detailsRoute = null;
      }),
    );
  }

  Widget _shipRow(LocalHangarShip ship) {
    final row = LocalHangarShipRow(
      key: ValueKey('local-hangar-ship-${ship.id}'),
      item: LocalHangarPresentation.fromSaved(ship),
      elapsed: _clock.elapsed - _arrivals[ship.id]!,
      onTap: () => _details(ship),
    );
    if (!_former || ship.removedAt == null) return row;
    final c = LocalHangarCopy(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${c.removedAt} · ${c.dateTime(context, ship.removedAt!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    final source =
        (_former ? _snapshot?.formerModels : _snapshot?.ships) ??
        const <LocalHangarShip>[];
    final ships = source
        .where(
          (ship) => [ship.title, ship.cn, ship.tw, ship.liner]
              .whereType<String>()
              .any((name) => name.toLowerCase().contains(_query)),
        )
        .toList();
    final saved =
        _snapshot != null &&
        (_snapshot!.revision > 0 ||
            _snapshot!.savedAt != null ||
            _snapshot!.ships.isNotEmpty);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.all(tokens.space.lg),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      c.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const Key('local-hangar-read'),
                          onPressed: widget.onRead,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.hangar,
                          ),
                          label: Text(c.read),
                        ),
                        OutlinedButton.icon(
                          key: const Key('local-hangar-refresh'),
                          onPressed: _loading ? null : _refresh,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.refresh,
                          ),
                          label: Text(c.refresh),
                        ),
                        if (widget.extraAction != null) widget.extraAction!,
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('hangar-current'),
                          label: Text(c.currentOwned),
                          selected: !_former,
                          onSelected: (_) => setState(() {
                            _former = false;
                            _closeDetails();
                          }),
                        ),
                        ChoiceChip(
                          key: const Key('hangar-former'),
                          label: Text(c.formerlyOwned),
                          selected: _former,
                          onSelected: (_) => setState(() {
                            _former = true;
                            _closeDetails();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_former)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(c.formerHint),
                      ),
                    if (saved && !_former) ...[
                      LocalHangarSummary(
                        ships: _snapshot!.ships
                            .map(LocalHangarPresentation.fromSaved)
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (saved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Tooltip(
                          message: _snapshot!.partial ? c.partial : '',
                          child: Text(
                            _snapshot!.fromLegacyProfile
                                ? c.legacySource
                                : c.savedOn(context, _snapshot!.savedAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    if (_loading && _snapshot == null)
                      Semantics(liveRegion: true, child: Text(c.loading)),
                    if (_failed)
                      Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.readFailure,
                              style: TextStyle(color: tokens.colors.warning),
                            ),
                            TextButton(
                              key: const Key('local-hangar-retry'),
                              onPressed: _refresh,
                              child: Text(c.retry),
                            ),
                          ],
                        ),
                      ),
                    if ((!_loading || _snapshot != null) &&
                        !_failed &&
                        source.isEmpty) ...[
                      Text(
                        _former
                            ? c.formerEmpty
                            : saved
                            ? c.emptySaved
                            : c.noSaved,
                      ),
                      const SizedBox(height: 6),
                      if (!_former) Text(c.emptyHint),
                    ],
                    if (source.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('local-hangar-search'),
                        controller: _search,
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                        decoration: InputDecoration(
                          labelText: c.search,
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  key: const Key('local-hangar-clear-search'),
                                  tooltip: c.clearSearch,
                                  icon: const StarBridgeIcon(
                                    StarBridgeIconSemantic.windowClose,
                                  ),
                                  onPressed: () => setState(() {
                                    _search.clear();
                                    _query = '';
                                  }),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        c.count(ships.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (ships.isEmpty) ...[
                        const SizedBox(height: 20),
                        Text(c.noMatches),
                        const SizedBox(height: 6),
                        Text(c.searchHint),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                tokens.space.lg,
                0,
                tokens.space.lg,
                tokens.space.lg,
              ),
              sliver: SliverList.separated(
                itemCount: ships.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _shipRow(ships[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
