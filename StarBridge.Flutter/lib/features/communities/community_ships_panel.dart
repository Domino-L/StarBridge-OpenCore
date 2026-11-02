import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_hangar_sharing.dart';
import '../common/organization_holo.dart';
import '../common/organization_ship_owner.dart';
import 'community_avatar_cache.dart';
import 'community_fleet_summary.dart';
import 'community_hangar_sharing_dialog.dart';
import 'community_hangar_sharing_port.dart';
import 'community_ship_avatar_access.dart';
import 'community_ship_banner.dart';
import 'community_ship_card.dart';
import 'community_ship_detail_dialog.dart';
import 'community_ship_statistics.dart';
import 'community_ship_statistics_panel.dart';
import 'community_ships_controller.dart';
import 'community_ships_copy.dart';
import 'community_ships_selection.dart';
import 'community_ships_empty_state.dart';
import 'community_ships_filters.dart';
import 'community_ships_header.dart';
import 'community_ships_list_views.dart';
import 'community_ships_owner_groups.dart';
import 'community_ships_port.dart';
import 'community_ships_prefetch.dart';
import 'community_ships_side_column.dart';
import 'community_ships_toolbar.dart';
import 'community_visible_refresh.dart';
import 'community_workspace_port.dart';

/// The organization ships page, shared by communities and the main fleet.
/// Redone 2026-10-29 (user decision, option D): a one-line summary, three
/// views (按舰船 / 按持有人 / 列表) that the organization remembers, pages
/// that accumulate as the reader scrolls, and on wide windows a persistent
/// right column with the selected ship's details or the dispatch block.
/// Nothing here computes availability; that stays with the operation
/// service once it exists.
class CommunityShipsPanel extends StatefulWidget {
  const CommunityShipsPanel({
    required this.port,
    required this.targetRef,
    required this.name,
    required this.onBack,
    this.onRefreshMembership,
    this.retryInvalidatedScope = false,
    this.avatars,
    this.controller,
    this.ownerTargetFactory = communityShipOwnerTarget,
    this.avatarAccess,
    this.includeSocialActions = true,
    this.hangarSharingPort,
    this.hangarSharingSourceRef,
    super.key,
  });
  final CommunityShipsPort port;
  final String targetRef, name;
  final VoidCallback onBack;
  final Future<void> Function()? onRefreshMembership;
  final bool retryInvalidatedScope;
  final CommunityAvatarCache? avatars;
  final CommunityShipsController? controller;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final CommunityShipAvatarAccess? avatarAccess;
  final bool includeSocialActions;
  final OrganizationHangarSharingPort? hangarSharingPort;
  final String? hangarSharingSourceRef;

  /// Below this the details open in the dialog and the dispatch block is
  /// not shown. 1280 keeps three card columns beside the column and leaves
  /// the 1200-wide dialog regressions as they are.
  static const sideColumnMinimumWidth = 1280.0;
  @override
  State<CommunityShipsPanel> createState() => _CommunityShipsPanelState();
}

class _CommunityShipsPanelState extends State<CommunityShipsPanel>
    with CommunityVisibleRefresh<CommunityShipsPanel> {
  late CommunityShipsController model;
  StreamSubscription<void>? _shipRefreshes;
  StarBridgeDialogRoute<bool>? _detailRoute;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  // Takes focus when a ship is selected, so the arrow keys walk the list.
  final _focus = FocusNode(debugLabel: 'community-ships');
  String _filter = 'all', _sort = 'spec';
  bool _descending = true;
  int _statisticsRefresh = 0;

  /// Every page read for the current query, held by the controller.
  List<CommunityShipsPage> get _pages => model.pages;
  CommunityShipStatistics? _statistics;

  /// The page that holds the selected ship, for the side column.
  late final _selection = CommunityShipsSelection(
    model: () => model,
    port: () => widget.port,
    targetRef: () => widget.targetRef,
    pageHolding: _pageHolding,
    update: setState,
    alive: () => mounted,
  );
  bool _wide = false, _selectionScheduled = false;
  bool get _onScreen => mounted && TickerMode.valuesOf(context).enabled;
  String t(String key) => communityShipsText(context, key);
  @override
  Future<void> refreshVisibleCommunity() => model.refreshVisible();
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start({CommunityShipQuery? initialQuery, bool enter = true}) {
    final port = widget.port;
    unawaited(_shipRefreshes?.cancel());
    _shipRefreshes = port is CommunityShipsRefreshPort
        ? (port as CommunityShipsRefreshPort).shipRefreshes.listen(
            (_) => refreshCommunityIfVisible(),
          )
        : null;
    model =
        widget.controller ??
        CommunityShipsController(
          port,
          widget.targetRef,
          initialQuery: initialQuery,
          avatars: widget.avatars,
          avatarAccess: widget.avatarAccess,
          mediaPort: port is CommunityWorkspacePort
              ? port as CommunityWorkspacePort
              : null,
        );
    if (widget.avatarAccess != null &&
        !identical(model.avatarAccess, widget.avatarAccess)) {
      throw ArgumentError(
        'An externally owned ship controller must use the same avatar access.',
      );
    }
    model.addListener(_changed);
    _search.text = model.query.text;
    _filter = model.query.filter;
    _sort = model.query.sort;
    _descending = model.query.descending;
    _selection.page = model.selectedShipRef == null
        ? null
        : _pageHolding(model.selectedShipRef!);
    if (enter) unawaited(model.enter());
  }

  Future<void> _retryInvalidatedScope() async {
    final previous = model;
    final port = widget.port,
        target = widget.targetRef,
        source = widget.hangarSharingSourceRef;
    final scopeRevision = previous.readScopeRevision;
    final verify = widget.onRefreshMembership;
    if (!widget.retryInvalidatedScope ||
        widget.controller != null ||
        !previous.invalidated ||
        widget.onRefreshMembership == null) {
      return;
    }
    try {
      await verify!();
    } on Object {
      return; // The former hard failure remains visible; no new authority was established.
    }
    if (!mounted ||
        !identical(model, previous) ||
        !identical(widget.port, port) ||
        widget.onRefreshMembership != verify ||
        widget.targetRef != target ||
        widget.hangarSharingSourceRef != source ||
        previous.readScopeRevision != scopeRevision ||
        !previous.invalidated) {
      return;
    }
    final selection = previous.query;
    _dismissDetail();
    previous.removeListener(_changed);
    previous.avatars.clear();
    previous.dispose();
    _start(initialQuery: selection, enter: false);
    await model.load();
  }

  void _changed() {
    if (model.invalidated) {
      _dismissDetail();
      _selection.clear();
      _statistics = null;
    }
    final page = model.page;
    if (page != null) _selection.afterPage(page);
    if (model.selectedShipRef != null &&
        _selection.page == null &&
        !_selection.lookingUp) {
      _selection.page = _pageHolding(model.selectedShipRef!);
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statistics ??= model.statisticsFor(communityShipsCulture(context));
    if (!model.busy &&
        model.error == null &&
        (model.page == null ||
            model.query.culture != communityShipsCulture(context))) {
      unawaited(_apply());
    }
  }

  @override
  void didUpdateWidget(covariant CommunityShipsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.avatars != widget.avatars ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.controller != widget.controller ||
        oldWidget.ownerTargetFactory != widget.ownerTargetFactory ||
        oldWidget.avatarAccess != widget.avatarAccess ||
        oldWidget.includeSocialActions != widget.includeSocialActions ||
        oldWidget.hangarSharingPort != widget.hangarSharingPort ||
        oldWidget.hangarSharingSourceRef != widget.hangarSharingSourceRef) {
      _dismissDetail();
      model.removeListener(_changed);
      if (oldWidget.controller == null) model.dispose();
      _search.clear();
      _filter = 'all';
      _sort = 'spec';
      _descending = true;
      _statistics = null;
      _selection.reset();
      _start();
      _statistics = model.statisticsFor(communityShipsCulture(context));
      unawaited(_apply());
    }
  }

  @override
  void dispose() {
    _dismissDetail();
    model.removeListener(_changed);
    if (widget.controller == null) model.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    unawaited(_shipRefreshes?.cancel());
    super.dispose();
  }

  /// Wide: open in the side column.
  Future<void> _select(CommunitySharedShip ship, {bool focus = true}) async {
    if (!_wide) return _openDetail(ship);
    await _selection.pick(
      ship,
      communityShipsCulture(context),
      byUser: focus,
      onPicked: focus ? _focus.requestFocus : null,
    );
  }

  /// The right column always shows a ship: the last one picked, otherwise the
  /// first of the list. Only when it can show one, never as a narrow dialog.
  /// A ship kept selected whose page is no longer held is located again.
  bool get _needsSelection =>
      _wide &&
      _onScreen &&
      (model.selectedShipRef == null || _selection.page == null) &&
      !_selection.lookingUp &&
      !model.invalidated &&
      _ships.isNotEmpty;

  void _selectFirstSoon() {
    if (_selectionScheduled || !_needsSelection) return;
    _selectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      if (mounted && _needsSelection) {
        final held = [
          ..._statistics?.ships ?? const <CommunitySharedShip>[],
          ..._ships,
        ].where((s) => s.shipRef == model.selectedShipRef).firstOrNull;
        unawaited(_select(held ?? _ships.first, focus: false));
      }
    });
  }

  /// Left and right arrows walk the visible order.
  void _step(int delta) {
    final selected = model.selectedShipRef;
    if (!_wide || selected == null) return;
    final order = model.viewMode == 'owners'
        ? [
            for (final group in CommunityShipsOwnerGroups.group(
              _ownerShips ?? const [],
            ))
              ...group,
          ]
        : _ships;
    final at = order.indexWhere((s) => s.shipRef == selected);
    if (at < 0) return;
    final next = (at + delta).clamp(0, order.length - 1);
    if (next != at) unawaited(_select(order[next]));
  }

  void _dismissDetail() {
    final route = _detailRoute;
    _detailRoute = null;
    retireStarBridgeDialog(route);
  }

  Future<void> _openDetail(CommunitySharedShip ship) async {
    final page = _pageHolding(ship.shipRef) ?? model.page;
    if (_detailRoute != null || page == null || model.invalidated) return;
    final owner = model;
    StarBridgeDialogRoute<bool>? opened;
    final refresh = await showStarBridgeDialog<bool>(
      context,
      useRootNavigator: false,
      builder: (_) => CommunityShipDetailDialog(
        port: widget.port,
        page: page,
        shipRef: ship.shipRef,
        avatar: owner.avatar(ship.ownerMemberRef),
        ownerTargetFactory: widget.ownerTargetFactory,
        includeSocialActions: widget.includeSocialActions,
        imageDecoder: owner.avatars.images.decode,
      ),
      onRouteCreated: (route) => _detailRoute = opened = route,
    );
    if (_detailRoute == opened) _detailRoute = null;
    if (mounted && model == owner && refresh == true) await model.load();
  }

  CommunityShipsPage? _pageHolding(String shipRef) {
    for (final page in _pages) {
      if (page.ships.any((s) => s.shipRef == shipRef)) return page;
    }
    return null;
  }

  Future<void> _openSharing() async {
    final port = widget.port;
    final editor = widget.hangarSharingPort;
    if ((editor == null && port is! CommunityHangarSharingPort) ||
        _detailRoute != null) {
      return;
    }
    final owner = model;
    StarBridgeDialogRoute<bool>? opened;
    final saved = await showStarBridgeDialog<bool>(
      context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => editor == null
          ? CommunityHangarSharingDialog(
              port: port as CommunityHangarSharingPort,
            )
          : CommunityHangarSharingDialog.editor(
              editor: editor,
              sourceRef: widget.hangarSharingSourceRef,
            ),
      onRouteCreated: (route) => _detailRoute = opened = route,
    );
    if (_detailRoute == opened) _detailRoute = null;
    if (mounted && model == owner && saved == true) {
      _rereadStatistics();
      await model.refreshVisible();
    }
  }

  /// An explicit refresh or a saved change: the held inventory is not enough.
  void _rereadStatistics() {
    model.holdStatistics(null, communityShipsCulture(context));
    _statisticsRefresh++;
  }

  Future<void> _apply() => model.load(
    selection: CommunityShipQuery(
      text: _search.text,
      filter: _filter,
      sort: _sort,
      descending: _descending,
      culture: communityShipsCulture(context),
    ),
  );
  void _clear() {
    _search.clear();
    _filter = 'all';
    _sort = 'spec';
    _descending = true;
    unawaited(_apply());
  }

  bool get _hasNext => _pages.isNotEmpty && _pages.last.next != null;

  void _loadMore() {
    if (_pages.isEmpty ||
        model.busy ||
        model.invalidated ||
        _pages.last.next == null) {
      return;
    }
    unawaited(model.next());
  }

  List<CommunitySharedShip> get _ships {
    final seen = <String>{};
    return [
      for (final page in _pages)
        for (final ship in page.ships)
          if (seen.add(ship.shipRef)) ship,
    ];
  }

  /// The owner view filters the full inventory on the client.
  List<CommunitySharedShip>? get _ownerShips => _statistics == null
      ? null
      : communityShipsFiltered(_statistics!, _filter, _search.text);

  Map<String, int>? get _counts =>
      _statistics == null ? null : communityShipFilterCounts(_statistics!);

  bool get _sharingAvailable =>
      widget.hangarSharingPort?.available == true ||
      widget.port is CommunityHangarSharingPort &&
          (widget.port as CommunityHangarSharingPort).hangarSharingAvailable;

  Widget _ship(CommunitySharedShip ship, {required bool card}) => card
      ? CommunityShipCard(
          ship: ship,
          targetRef: widget.targetRef,
          avatarBytes: model.avatar(ship.ownerMemberRef),
          avatarLoading: model.avatarLoading(ship.ownerMemberRef),
          imageDecoder: model.avatars.images.decode,
          onDetails: () => unawaited(_select(ship)),
          ownerTargetFactory: widget.ownerTargetFactory,
          includeSocialActions: widget.includeSocialActions,
          selected: _wide && ship.shipRef == model.selectedShipRef,
        )
      : CommunitySharedShipRow(
          card: card,
          ship: ship,
          targetRef: widget.targetRef,
          avatarBytes: model.avatar(ship.ownerMemberRef),
          avatarLoading: model.avatarLoading(ship.ownerMemberRef),
          imageDecoder: model.avatars.images.decode,
          onDetails: () => unawaited(_select(ship)),
          ownerTargetFactory: widget.ownerTargetFactory,
          includeSocialActions: widget.includeSocialActions,
          selected: _wide && ship.shipRef == model.selectedShipRef,
        );

  Widget _trailing(int shown, int total) => CommunityShipsLoadMoreRow(
    shown: shown,
    total: total,
    // Pages load by themselves; the action only remains to retry a failed one.
    hasMore: _hasNext && model.error != null,
    onMore: model.busy ? null : _loadMore,
  );

  Widget _content() {
    final ships = _ships;
    if (model.busy && _pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(t('loading')),
          ],
        ),
      );
    }
    if (model.error != null && _pages.isEmpty) return _state(t(model.error!));
    if (_pages.isEmpty) return const SizedBox.shrink();
    if (model.viewMode == 'owners') {
      final owned = _ownerShips;
      if (owned == null) {
        return _state(
          t(
            _pages.last.totalCount > CommunityFleetSummary.maximumShips
                ? 'ownersTooMany'
                : 'statisticsLoading',
          ),
        );
      }
      if (owned.isEmpty) {
        return _state(
          t(_pages.last.totalCount == 0 ? 'empty' : 'ownersNoMatches'),
          clear:
              _pages.last.totalCount > 0 && _filter != 'all' ||
              _search.text.isNotEmpty,
        );
      }
      return CommunityShipsOwnerGroups(
        ships: owned,
        selectedRef: _wide ? model.selectedShipRef : null,
        onSelect: (ship) => unawaited(_select(ship)),
        decoder: model.avatars.images.decode,
        avatarOf: model.avatar,
        avatarLoading: model.avatarLoading,
        controller: _scroll,
      );
    }
    if (ships.isEmpty) {
      return _state(
        t(_pages.last.totalCount == 0 ? 'empty' : 'noMatches'),
        clear: _pages.last.totalCount > 0,
      );
    }
    final listKey = ValueKey((
      widget.targetRef,
      _pages.first.query,
      model.viewMode,
    ));
    return CommunityShipsPrefetch(
      key: const Key('community-ships-list'),
      canLoad: _hasNext && !model.busy && !model.invalidated && model.error == null,
      load: _loadMore,
      child: model.viewMode == 'list'
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CommunityShipColumnHeader(),
                Expanded(
                  child: CommunityShipsListRows(
                    ships: ships,
                    row: _ship,
                    listKey: listKey,
                    controller: _scroll,
                  ),
                ),
              ],
            )
          : CommunityShipsCardGrid(
              ships: ships,
              row: _ship,
              listKey: listKey,
              controller: _scroll,
              minColumnWidth: 280,
            ),
    );
  }

  Widget _side() {
    final selected = model.selectedShipRef;
    final ship = [
      ..._selection.page?.ships ?? const <CommunitySharedShip>[],
      ..._statistics?.ships ?? const <CommunitySharedShip>[],
      ..._ships,
    ].where((candidate) => candidate.shipRef == selected).firstOrNull;
    return CommunityShipsSideColumn(
      port: widget.port,
      imageDecoder: model.avatars.images.decode,
      detailPage: _selection.page,
      selectedRef: selected,
      lookingUp: _selection.lookingUp,
      pageIsCurrent: model.selectionIsDefault,
      reconcile: _selection.page?.query != model.query,
      avatar: ship == null ? null : model.avatar(ship.ownerMemberRef),
      ownerTargetFactory: widget.ownerTargetFactory,
      includeSocialActions: widget.includeSocialActions,
      onRefreshLibrary: () => unawaited(model.load()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = model.page;
    final content = LayoutBuilder(
      builder: (context, available) {
        _wide =
            available.maxWidth >= CommunityShipsPanel.sideColumnMinimumWidth;
        _selectFirstSoon();
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommunityShipsHeader(
              name: widget.name,
              onBack: widget.onBack,
              // Only a completed read of the whole library can say so.
              sharingHint:
                  _sharingAvailable &&
                      !model.invalidated &&
                      _statistics?.ships.any((s) => s.ownerIsSelf) == false
                  ? 'notSharedHint'
                  : null,
              sharingLabel: !_sharingAvailable
                  ? null
                  : widget.hangarSharingPort == null
                  ? 'sharingTitle'
                  : 'ownSharingTitle',
              onSharing: model.invalidated && widget.hangarSharingPort == null
                  ? null
                  : _openSharing,
              onRefresh:
                  model.error == 'refreshRequired' &&
                      widget.onRefreshMembership != null
                  ? widget.onRefreshMembership
                  : widget.retryInvalidatedScope &&
                        widget.controller == null &&
                        model.invalidated &&
                        widget.onRefreshMembership != null
                  ? _retryInvalidatedScope
                  : model.busy || model.invalidated
                  ? null
                  : () {
                      _rereadStatistics();
                      unawaited(_apply());
                    },
            ),
            if (!model.invalidated && (model.error == null || page != null))
              Material(
                type: MaterialType.transparency,
                child: CommunityShipStatisticsPanel(
                  key: ValueKey(
                    'ship-statistics:${widget.targetRef}:${communityShipsCulture(context)}:$_statisticsRefresh',
                  ),
                  port: widget.port,
                  targetRef: widget.targetRef,
                  culture: communityShipsCulture(context),
                  // Only the first page can say the inventory changed.
                  firstPage: _pages.firstOrNull,
                  initial: model.statisticsFor(communityShipsCulture(context)),
                  onStatistics: (stats) {
                    if (!mounted) return;
                    model.holdStatistics(
                      stats,
                      communityShipsCulture(context),
                    );
                    if (stats != null) model.showOwners(stats.ships);
                    setState(() {
                      _statistics = stats;
                      // Another filter may hide it; the whole library cannot.
                      final held = model.selectedShipRef;
                      if (stats != null &&
                          held != null &&
                          !stats.ships.any((s) => s.shipRef == held)) {
                        _selection.clear();
                      }
                    });
                  },
                  avatarOf: model.avatar,
                  decoder: model.avatars.images.decode,
                ),
              ),
            const SizedBox(height: 10),
            CommunityShipsToolbar(
              search: _search,
              filter: _filter,
              sort: _sort,
              descending: _descending,
              viewMode: model.viewMode,
              enabled: !model.invalidated,
              counts: _counts,
              onSearch: () => unawaited(_apply()),
              onFilter: (key) {
                _filter = key;
                unawaited(_apply());
              },
              onSort: (key) {
                _sort = key;
                // Size, status and price read best largest first.
                _descending = const {'spec', 'status', 'price'}.contains(key);
                unawaited(_apply());
              },
              onDirection: () {
                _descending = !_descending;
                unawaited(_apply());
              },
              onView: (view) => setState(() => model.viewMode = view),
            ),
            const SizedBox(height: 8),
            if (model.mediaFailed)
              Text(
                t('mediaFailed'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            SizedBox(
              height: 2,
              child: _pages.isNotEmpty && model.busy
                  ? const LinearProgressIndicator()
                  : null,
            ),
            if (_pages.isNotEmpty && model.error != null)
              Row(
                children: [
                  Expanded(child: Text(t('refreshFailed'))),
                  StarBridgeActionButton(
                    controlKey: const Key('community-ships-refresh-failed'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: model.busy ? null : (_) => _apply(),
                    child: Text(t('refresh')),
                  ),
                ],
              ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _step(1),
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _step(-1),
                },
                child: Focus(
                  focusNode: _focus,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _content()),
                            if (_pages.isNotEmpty &&
                                model.viewMode != 'owners' &&
                                _ships.isNotEmpty)
                              _trailing(
                                _ships.length,
                                _pages.last.matchedCount,
                              ),
                          ],
                        ),
                      ),
                      if (_wide && !model.invalidated && _pages.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        _side(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        // Keep all controls reachable when an expanded organization header
        // leaves too little room for the ship tools and the first row.
        final minimumHeight = available.maxWidth < 760 ? 1050.0 : 700.0;
        if (available.maxHeight < minimumHeight) {
          return SingleChildScrollView(
            child: SizedBox(height: minimumHeight, child: body),
          );
        }
        return body;
      },
    );
    // No control on this page follows the interaction suite (user 2026-10-30).
    return OrganizationHoloFace(child: content);
  }

  Widget _state(String message, {bool clear = false}) =>
      CommunityShipsEmptyState(
        message: message,
        onClear: clear ? _clear : null,
        onRetry:
            widget.retryInvalidatedScope &&
                widget.controller == null &&
                model.invalidated &&
                widget.onRefreshMembership != null
            ? _retryInvalidatedScope
            : !model.invalidated
            ? () => unawaited(_apply())
            : null,
      );
}
