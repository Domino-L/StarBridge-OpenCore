import '../../shared/guide/guide_empty_state.dart';
import 'hangar_guide.dart';
import '../../shared/guide/guide_scope.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_names.dart';
import 'local_hangar_personal_data_editor.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_port.dart';
import 'local_hangar_images.dart';
import 'local_hangar_ship_details.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_overview.dart';
import 'local_hangar_inventory_projection.dart';
import 'local_hangar_inventory_tiles.dart';
import 'local_hangar_detail.dart';
import 'ship_specifications_port.dart';
import 'cached_local_hangar.dart';
import 'local_hangar_controls.dart';
import 'local_hangar_read_status.dart';
import 'hangar_display_session.dart';
import 'hangar_read_diagnostics.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

/// The caller mounts this only while signed in and recreates it per generation.
class LocalHangarPage extends StatefulWidget {
  const LocalHangarPage({
    required this.port,
    required this.onRead,
    this.extraAction,
    super.key,
  });

  final LocalHangarPort port;
  final VoidCallback? onRead;
  final Widget? extraAction;

  @override
  State<LocalHangarPage> createState() => _LocalHangarPageState();
}

class _LocalHangarPageState extends State<LocalHangarPage> {
  LocalHangarSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  int _epoch = 0;
  int _ownerEpoch = 0;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  bool _former = false;
  bool _grid = true;
  bool _favoritesOnly = false;
  bool _favoriteBusy = false;
  bool _favoriteFailed = false;
  InteractionSource _readSource = InteractionSource.programmatic;
  InteractionSource _favoriteSource = InteractionSource.programmatic;
  int _readPhase = 0, _favoritePhase = 0;
  bool _readInheritsOpening = true;
  Object? _readFeedbackRequest;
  int _favoriteEpoch = 0;
  final _imageCache = LocalHangarImageCache();
  int _imageGeneration = 0;
  String? _size;
  String? _category;
  String? _status;
  String _sort = 'saved';
  final _clock = Stopwatch()..start();
  final _arrivals = <String, Duration>{};
  StarBridgeDialogRoute<void>? _detailsRoute;
  StarBridgeDialogRoute<LocalHangarSnapshot>? _personalDataRoute;
  final _detailChanges = ValueNotifier<int>(0);
  String? _detailShipId;
  HangarDisplaySession? get _display => widget.port is HangarDisplaySession
      ? widget.port as HangarDisplaySession
      : null;
  LocalHangarViewState? _view;
  int _displayViewEpoch = -1, _contentEpoch = -1;
  bool _restoringView = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_rememberView);
    _display?.addListener(_displayChanged);
    _restore();
  }

  @override
  void didUpdateWidget(covariant LocalHangarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.port, widget.port)) {
      _rememberView();
      _view = null;
      if (oldWidget.port case HangarDisplaySession previous) {
        previous.removeListener(_displayChanged);
      }
      _display?.addListener(_displayChanged);
      _displayViewEpoch = -1;
      ++_epoch;
      ++_ownerEpoch;
      ++_favoriteEpoch;
      _imageCache.clear();
      _size = null;
      _closeDetails();
      _snapshot = null;
      _search.clear();
      _query = '';
      _former = false;
      _favoritesOnly = false;
      _favoriteBusy = false;
      _favoriteFailed = false;
      _readFeedbackRequest = null;
      _readSource = InteractionSource.programmatic;
      _readInheritsOpening = false;
      ++_readPhase;
      _category = null;
      _status = null;
      _sort = 'saved';
      _arrivals.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _restore();
    }
  }

  void _restore() {
    final port = widget.port;
    if (port is LocalHangarViewSource) {
      _restoreView(port as LocalHangarViewSource);
    }
    if (_display != null) {
      _displayChanged();
      if (_snapshot == null) unawaited(_refresh(initial: true));
      return;
    }
    _snapshot = port is CachedLocalHangar ? port.snapshot : null;
    _loading = _snapshot == null;
    _failed = false;
    if (_snapshot case final snapshot?) {
      for (final ship in [...snapshot.ships, ...snapshot.formerShips]) {
        // A cached arrival is finished regardless of its category's duration.
        _arrivals[ship.id] = const Duration(days: -1);
      }
    }
    if (_loading) unawaited(_refresh(initial: true));
  }

  void _rememberView() {
    final view = _view;
    if (view == null) return;
    view
      ..query = _search.text
      ..sort = _sort
      ..size = _size
      ..category = _category
      ..status = _status
      ..former = _former
      ..favoritesOnly = _favoritesOnly
      ..grid = _grid;
    if (_scroll.hasClients && !_restoringView) {
      view.scrollOffset = _scroll.offset;
    }
  }

  void _restoreView(LocalHangarViewSource display) {
    if (_displayViewEpoch != display.viewEpoch) {
      _rememberView();
      _view = display.view;
      _restoringView = true;
      _displayViewEpoch = display.viewEpoch;
      _query = _view!.query.trim().toLowerCase();
      _search.text = _view!.query;
      _sort = _view!.sort;
      _size = _view!.size;
      _category = _view!.category;
      _status = _view!.status;
      _former = _view!.former;
      _favoritesOnly = _view!.favoritesOnly;
      _grid = _view!.grid;
      ++_ownerEpoch;
      ++_favoriteEpoch;
      _favoriteBusy = false;
      _favoriteFailed = false;
      _readFeedbackRequest = null;
      _readSource = InteractionSource.programmatic;
      _readInheritsOpening = false;
      ++_readPhase;
      _closeDetails();
      final epoch = _displayViewEpoch;
      final offset = _view!.scrollOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _displayViewEpoch && _scroll.hasClients) {
          _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
          _restoringView = false;
          _rememberView();
        }
      });
    }
  }

  void _displayChanged() {
    final display = _display;
    if (!mounted || display == null) return;
    setState(() {
      _restoreView(display);
      if (_contentEpoch != display.contentEpoch) {
        _contentEpoch = display.contentEpoch;
        _imageCache.clear();
        ++_imageGeneration;
      }
      _snapshot = display.snapshot;
      final loading =
          display.refreshing || _snapshot == null && !display.failed;
      // An owner-driven background read is a new passive phase, not a replay
      // of the previous refresh button's input source.
      if (loading && !_loading && _readFeedbackRequest == null) {
        _readSource = InteractionSource.programmatic;
        _readInheritsOpening = false;
        ++_readPhase;
      }
      _loading = loading;
      _failed = display.failed;
      final ships = [...?_snapshot?.ships, ...?_snapshot?.formerShips];
      for (final ship in ships) {
        _arrivals.putIfAbsent(ship.id, () => const Duration(days: -1));
      }
      if (_detailShipId != null &&
          !ships.any((ship) => ship.id == _detailShipId)) {
        _closeDetails();
      }
    });
  }

  @override
  void dispose() {
    _rememberView();
    _display?.removeListener(_displayChanged);
    _epoch++;
    _closeDetails();
    _detailChanges.dispose();
    _clock.stop();
    ++_favoriteEpoch;
    _imageCache.clear();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh({
    bool refreshImages = false,
    InteractionSource source = InteractionSource.programmatic,
    bool initial = false,
  }) async {
    _readSource = source;
    _readInheritsOpening = initial;
    ++_readPhase;
    final display = _display;
    if (display != null) {
      final feedbackRequest = Object();
      _readFeedbackRequest = feedbackRequest;
      if (refreshImages) {
        _imageCache.clear();
        ++_imageGeneration;
      }
      try {
        await display.read();
      } on Object {
        /* The display owner publishes the classified failure. */
      } finally {
        if (identical(_readFeedbackRequest, feedbackRequest)) {
          _readFeedbackRequest = null;
        }
      }
      return;
    }
    final epoch = ++_epoch;
    setState(() {
      if (refreshImages) {
        _imageCache.clear();
        ++_imageGeneration;
      }
      _loading = true;
      _failed = false;
    });
    try {
      final snapshot = await HangarReadDiagnostics.capture(
        HangarReadStage.pageRead,
        () async => widget.port.read(),
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        if (_snapshot == null || snapshot.revision >= _snapshot!.revision) {
          _snapshot = snapshot;
        }
        final ids = [
          ..._snapshot!.ships,
          ..._snapshot!.formerShips,
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

  String _name(LocalHangarShip ship, {BuildContext? displayContext}) =>
      LocalHangarNames.primary(
        Localizations.localeOf(displayContext ?? context),
        ship,
      );

  Future<void> _setFavorite(LocalHangarShip ship) async {
    final port = widget.port, snapshot = _snapshot;
    if (_favoriteBusy ||
        _loading ||
        snapshot == null ||
        snapshot.fromLegacyProfile ||
        port is! LocalHangarFavoritesPort ||
        !(port as LocalHangarFavoritesPort).favoritesAvailable) {
      return;
    }
    final epoch = ++_favoriteEpoch;
    setState(() {
      _favoriteBusy = true;
      _favoriteFailed = false;
      _favoriteSource = currentStarBridgeActivationSource;
      ++_favoritePhase;
    });
    try {
      final result = await (port as LocalHangarFavoritesPort).setFavorite(
        ship.id,
        !ship.isFavorite,
        snapshot.revision,
      );
      if (!mounted ||
          epoch != _favoriteEpoch ||
          !identical(port, widget.port)) {
        return;
      }
      setState(() {
        if (_snapshot == null || result.revision >= _snapshot!.revision) {
          _snapshot = result;
        }
      });
    } catch (_) {
      if (mounted && epoch == _favoriteEpoch) {
        setState(() => _favoriteFailed = true);
      }
    } finally {
      if (mounted && epoch == _favoriteEpoch) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  void _closeDetails() {
    final editor = _personalDataRoute;
    _personalDataRoute = null;
    retireStarBridgeDialog(editor, includeClosing: true);
    final route = _detailsRoute;
    _detailsRoute = null;
    _detailShipId = null;
    retireStarBridgeDialog(route, includeClosing: true);
  }

  Future<LocalHangarShip?> _editPersonalData(String shipId) async {
    final source = widget.port, snapshot = _snapshot, ownerEpoch = _ownerEpoch;
    if (_personalDataRoute != null ||
        _loading ||
        _favoriteBusy ||
        snapshot == null ||
        snapshot.fromLegacyProfile ||
        source is! LocalHangarPersonalDataPort ||
        !(source as LocalHangarPersonalDataPort).personalDataAvailable) {
      return null;
    }
    final ship = [
      ...snapshot.ships,
      ...snapshot.formerShips,
    ].where((s) => s.id == shipId).firstOrNull;
    if (ship == null) return null;
    bool current() =>
        mounted && identical(widget.port, source) && ownerEpoch == _ownerEpoch;
    StarBridgeDialogRoute<LocalHangarSnapshot>? opened;
    final result = await showStarBridgeDialog<LocalHangarSnapshot>(
      context,
      source: currentStarBridgeActivationSource,
      barrierDismissible: false,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      onRouteCreated: (route) => _personalDataRoute = opened = route,
      builder: (_) => StarBridgeDialogOwnerGuard(
        isCurrent: current,
        child: LocalHangarPersonalDataEditor(
          port: source,
          snapshot: snapshot,
          ship: ship,
          isCurrent: current,
        ),
      ),
    );
    if (identical(_personalDataRoute, opened)) _personalDataRoute = null;
    if (!current() || result == null) return null;
    setState(() {
      if (_snapshot == null || result.revision >= _snapshot!.revision) {
        _snapshot = result;
      }
    });
    _detailChanges.value++;
    return [
      ...?_snapshot?.ships,
      ...?_snapshot?.formerShips,
    ].where((s) => s.id == shipId).firstOrNull;
  }

  void _details(LocalHangarShip ship) {
    if (_detailsRoute != null) return;
    final source = widget.port;
    final ownerEpoch = _ownerEpoch;
    bool current() =>
        mounted &&
        identical(widget.port, source) &&
        _ownerEpoch == ownerEpoch &&
        [
          ...?_snapshot?.ships,
          ...?_snapshot?.formerShips,
        ].any((candidate) => candidate.id == ship.id);
    Widget buildDetails(BuildContext context, [Widget? child]) {
      // A live scope can rebuild the route in the same frame as owner
      // replacement, before Navigator is allowed to retire it.
      if (!current()) return const SizedBox.shrink();
      final currentShip =
          [
            ...?_snapshot?.ships,
            ...?_snapshot?.formerShips,
          ].where((candidate) => candidate.id == ship.id).firstOrNull ??
          ship;
      final images =
          source is LocalHangarImageProvider &&
              _snapshot?.fromLegacyProfile != true
          ? (source as LocalHangarImageProvider).imageFor(
              ship.id,
              _snapshot!.revision,
            )
          : null;
      final peers = _peers(currentShip);
      return LocalHangarDetail(
        title: _name(currentShip, displayContext: context),
        body: LocalHangarShipDetails(
          key: ValueKey((_display?.contentEpoch, _ownerEpoch, ship.id)),
          ship: currentShip,
          former: _former,
          images: images,
          instanceIndex: peers.indexWhere((s) => s.id == ship.id) + 1,
          instanceCount: peers.length,
          onEditPersonalData:
              source is LocalHangarPersonalDataPort &&
                  (source as LocalHangarPersonalDataPort)
                      .personalDataAvailable &&
                  _snapshot?.fromLegacyProfile != true
              ? () => _editPersonalData(ship.id)
              : null,
          refreshImages:
              source is LocalHangarImageProvider &&
                  _snapshot?.fromLegacyProfile != true
              ? () => (source as LocalHangarImageProvider).imageFor(
                  ship.id,
                  _snapshot!.revision,
                )
              : null,
          specifications: source is ShipSpecificationsProvider
              ? source as ShipSpecificationsProvider
              : null,
          onFavorite:
              source is LocalHangarFavoritesPort &&
                  (source as LocalHangarFavoritesPort).favoritesAvailable &&
                  _snapshot?.fromLegacyProfile != true
              ? () async {
                  final current = [
                    ...?_snapshot?.ships,
                    ...?_snapshot?.formerShips,
                  ].where((s) => s.id == ship.id).firstOrNull;
                  if (current == null) return null;
                  await _setFavorite(current);
                  return [
                    ...?_snapshot?.ships,
                    ...?_snapshot?.formerShips,
                  ].where((s) => s.id == ship.id).firstOrNull;
                }
              : null,
          onImageSaved: () {
            if (!mounted) return;
            if (source is CachedLocalHangar) {
              source.invalidateAfterImageSave();
            }
            if (source is HangarDisplaySession) {
              source.invalidateAfterImageSave();
            }
            unawaited(
              _refresh(
                refreshImages: true,
                source: currentStarBridgeActivationSource,
              ),
            );
          },
        ),
      );
    }

    _detailShipId = ship.id;
    unawaited(
      showStarBridgeDialog<void>(
        context,
        source: currentStarBridgeActivationSource,
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        onRouteCreated: (route) {
          _detailsRoute = route;
          // Keep exact ownership through reverse; invalidation during this
          // tail retires this surface, never an unrelated top route.
          unawaited(
            route.completed.then((_) {
              if (identical(_detailsRoute, route)) {
                _detailsRoute = null;
                _detailShipId = null;
              }
            }),
          );
        },
        builder: (context) => StarBridgeDialogOwnerGuard(
          isCurrent: current,
          child: ListenableBuilder(
            listenable: Listenable.merge([_detailChanges, ?_display]),
            builder: buildDetails,
          ),
        ),
      ),
    );
  }

  List<LocalHangarShip> _peers(LocalHangarShip ship) =>
      (_former ? _snapshot?.formerInstances : _snapshot?.ships)
          ?.where((s) => s.modelKey == ship.modelKey)
          .toList() ??
      [ship];

  void _clearFilters() => setState(() {
    _query = '';
    _search.clear();
    _category = null;
    _status = null;
    _size = null;
    _favoritesOnly = false;
  });

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    final source =
        (_former ? _snapshot?.formerInstances : _snapshot?.ships) ??
        const <LocalHangarShip>[];
    final inventory = LocalHangarInventoryProjection(
      source: source,
      copy: c,
      query: _query,
      favoritesOnly: _favoritesOnly,
      category: _category,
      size: _size,
      status: _status,
      sort: _sort,
    );
    final ships = inventory.ships;
    final favoritesAvailable =
        widget.port is LocalHangarFavoritesPort &&
        (widget.port as LocalHangarFavoritesPort).favoritesAvailable &&
        _snapshot?.fromLegacyProfile != true;
    final saved =
        _snapshot != null &&
        (_snapshot!.revision > 0 ||
            _snapshot!.savedAt != null ||
            _snapshot!.ships.isNotEmpty);
    final guided =
        (!_loading || _snapshot != null) &&
        !_failed &&
        source.isEmpty &&
        !saved &&
        !_former &&
        widget.onRead != null &&
        GuideEmptyState.active(context);
    final content = Align(
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
                    LocalHangarToolbar(
                      showRead: widget.onRead != null,
                      onRead: _favoriteBusy ? null : widget.onRead,
                      onRefresh: _loading || _favoriteBusy
                          ? null
                          : () => _refresh(
                              refreshImages: true,
                              source: currentStarBridgeActivationSource,
                            ),
                      extraAction: widget.extraAction,
                      showSearch: source.isNotEmpty,
                      search: LocalHangarSearchField(
                        controller: _search,
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                        onClear: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                      former: _former,
                      favoritesOnly: _favoritesOnly,
                      grid: _grid,
                      sort: _sort,
                      onFormer: (value) => setState(() {
                        _former = value;
                        _closeDetails();
                      }),
                      onFavorites: (value) =>
                          setState(() => _favoritesOnly = value),
                      onSort: (value) => setState(() => _sort = value),
                      onGrid: (value) => setState(() => _grid = value),
                    ),
                    const SizedBox(height: 12),
                    if (_former)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _favoritesOnly ? c.formerBookmarksHint : c.formerHint,
                        ),
                      ),
                    if (saved && !_former) ...[
                      LocalHangarOverview(
                        ships: _snapshot!.ships
                            .map(LocalHangarPresentation.fromSaved)
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    LocalHangarReadStatus(
                      snapshot: _snapshot,
                      saved: saved,
                      loading: _loading,
                      favoriteBusy: _favoriteBusy,
                      favoriteFailed: _favoriteFailed,
                      failed: _failed,
                      readSource: _readSource,
                      readPhase: _readPhase,
                      inheritReadOpeningSource: _readInheritsOpening,
                      favoriteSource: _favoriteSource,
                      favoritePhase: _favoritePhase,
                      onRetry: () => _refresh(
                        refreshImages: true,
                        source: currentStarBridgeActivationSource,
                      ),
                    ),
                    if (guided)
                      hangarGuideEmpty(_favoriteBusy ? null : widget.onRead)
                    else if ((!_loading || _snapshot != null) &&
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
                      LocalHangarFilters(
                        roles: inventory.roles,
                        sizes: inventory.sizes,
                        category: _category,
                        status: _status,
                        size: _size,
                        hasFilters:
                            _query.isNotEmpty ||
                            _category != null ||
                            _status != null ||
                            _size != null ||
                            _favoritesOnly,
                        onCategory: (value) =>
                            setState(() => _category = value),
                        onStatus: (value) => setState(() => _status = value),
                        onSize: (value) => setState(() => _size = value),
                        onClear: _clearFilters,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.count(ships.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (ships.isEmpty) ...[
                        const SizedBox(height: 20),
                        Text(c.noMatches),
                        const SizedBox(height: 6),
                        Text(c.searchHint),
                        StarBridgeActionButton(
                          controlKey: const Key('hangar-clear-filters'),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: (_) => _clearFilters(),
                          child: Text(c.clearFilters),
                        ),
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
              sliver: LocalHangarInventoryTiles(
                inventory: inventory,
                grid: _grid,
                former: _former,
                images:
                    widget.port is LocalHangarImageProvider &&
                        _snapshot?.fromLegacyProfile != true
                    ? widget.port as LocalHangarImageProvider
                    : null,
                revision: _snapshot?.revision ?? 0,
                ownerGeneration: _ownerEpoch,
                imageGeneration: _imageGeneration,
                imageCache: _imageCache,
                elapsed: (ship) =>
                    _clock.elapsed -
                    (_grid
                        ? (_arrivals[ship.id] ?? Duration.zero)
                        : _arrivals[ship.id]!),
                onOpen: _details,
                onFavorite: favoritesAvailable && !_loading && !_favoriteBusy
                    ? (ship) => unawaited(_setFavorite(ship))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
    return LoadingContentProbe(
      route: '/hangar',
      status: _failed
          ? (_snapshot == null
                ? LoadingContentStatus.failed
                : LoadingContentStatus.partial)
          : _loading
          ? (_snapshot == null
                ? LoadingContentStatus.waiting
                : LoadingContentStatus.partial)
          : ships.isEmpty
          ? LoadingContentStatus.empty
          : LoadingContentStatus.data,
      items: ships.length,
      child: GuideSignal(id: 'hangar', when: saved, child: content),
    );
  }
}
