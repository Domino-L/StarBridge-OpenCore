import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'community_ship_vehicle_icon.dart';
import '../common/user_avatar_menu.dart';
import 'community_ships_controller.dart';
import 'community_avatar_cache.dart';
import 'community_ship_detail_dialog.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';
import 'community_workspace_port.dart';
import 'community_workspace_image.dart';
import 'community_catalog_ship_image.dart';
import 'community_ship_banner.dart';
import 'community_ship_row_surface.dart';
import 'community_ship_statistics_panel.dart';
import 'community_ship_loaners.dart';
import 'community_visible_refresh.dart';
import 'community_hangar_sharing_port.dart';
import 'community_hangar_sharing_dialog.dart';

class CommunityShipsPanel extends StatefulWidget {
  const CommunityShipsPanel({
    required this.port,
    required this.targetRef,
    required this.name,
    required this.onBack,
    this.onRefreshMembership,
    this.avatars,
    this.controller,
    super.key,
  });
  final CommunityShipsPort port;
  final String targetRef, name;
  final VoidCallback onBack;
  final Future<void> Function()? onRefreshMembership;
  final CommunityAvatarCache? avatars;
  final CommunityShipsController? controller;
  @override
  State<CommunityShipsPanel> createState() => _CommunityShipsPanelState();
}

class _CommunityShipsPanelState extends State<CommunityShipsPanel>
    with CommunityVisibleRefresh<CommunityShipsPanel> {
  late CommunityShipsController model;
  StreamSubscription<void>? _shipRefreshes;
  DialogRoute<bool>? _detailRoute;
  final _search = TextEditingController();
  String _filter = 'all', _sort = 'spec';
  bool _descending = true;
  int _statisticsRefresh = 0;
  String? _statisticsRevision;
  double? _statisticsHeight;
  String t(String key) => communityShipsText(context, key);
  @override
  Future<void> refreshVisibleCommunity() => model.refreshVisible();
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
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
          avatars: widget.avatars,
          mediaPort: port is CommunityWorkspacePort
              ? port as CommunityWorkspacePort
              : null,
        );
    model.addListener(_changed);
    _search.text = model.query.text;
    _filter = model.query.filter;
    _sort = model.query.sort;
    _descending = model.query.descending;
    _statisticsRevision = model.page?.revision;
    unawaited(model.enter());
  }

  void _changed() {
    if (model.page != null) _statisticsRevision = model.page!.revision;
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
        oldWidget.controller != widget.controller) {
      _dismissDetail();
      model.removeListener(_changed);
      if (oldWidget.controller == null) model.dispose();
      _search.clear();
      _filter = 'all';
      _sort = 'spec';
      _descending = true;
      _statisticsRevision = null;
      _statisticsHeight = null;
      _start();
      unawaited(_apply());
    }
  }

  @override
  void dispose() {
    _dismissDetail();
    model.removeListener(_changed);
    if (widget.controller == null) model.dispose();
    _search.dispose();
    unawaited(_shipRefreshes?.cancel());
    super.dispose();
  }

  void _dismissDetail() {
    final route = _detailRoute;
    _detailRoute = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  Future<void> _openDetail(CommunitySharedShip ship) async {
    final page = model.page;
    if (_detailRoute != null || page == null || model.invalidated) return;
    final owner = model;
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => CommunityShipDetailDialog(
        port: widget.port,
        page: page,
        shipRef: ship.shipRef,
        avatar: owner.avatar(ship.ownerMemberRef),
      ),
    );
    _detailRoute = route;
    final refresh = await Navigator.of(context).push(route);
    if (_detailRoute == route) _detailRoute = null;
    if (mounted && model == owner && refresh == true) await model.load();
  }

  Future<void> _openSharing() async {
    final port = widget.port;
    if (port is! CommunityHangarSharingPort || _detailRoute != null) return;
    final owner = model;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommunityHangarSharingDialog(
        port: port as CommunityHangarSharingPort,
      ),
    );
    _detailRoute = route;
    final saved = await Navigator.of(context).push(route);
    if (_detailRoute == route) _detailRoute = null;
    if (mounted && model == owner && saved == true) {
      _statisticsRefresh++;
      await model.refreshVisible();
    }
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

  Widget _choice(
    String label,
    String value,
    List<String> choices,
    void Function(String) select,
    double width,
  ) => SizedBox(
    width: width,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: t(label),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          onChanged: model.invalidated
              ? null
              : (next) {
                  if (next != null) select(next);
                },
          items: choices
              .map(
                (key) => DropdownMenuItem(
                  value: key,
                  child: Text(
                    t(key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final page = model.page;
    return LayoutBuilder(
      builder: (context, available) {
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const StandardIcon(StandardIconSemantic.arrowBack, size: 18),
                  label: Text(t('back')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.name} · ${t('title')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.port is CommunityHangarSharingPort &&
                    (widget.port as CommunityHangarSharingPort)
                        .hangarSharingAvailable)
                  MediaQuery.sizeOf(context).width >= 800
                      ? OutlinedButton.icon(
                          onPressed: model.invalidated ? null : _openSharing,
                          icon: const StandardIcon(StandardIconSemantic.share, size: 18),
                          label: Text(t('sharingTitle')),
                        )
                      : IconButton(
                          onPressed: model.invalidated ? null : _openSharing,
                          tooltip: t('sharingTitle'),
                          icon: const StandardIcon(StandardIconSemantic.share),
                        ),
                IconButton(
                  onPressed:
                      model.error == 'refreshRequired' &&
                          widget.onRefreshMembership != null
                      ? widget.onRefreshMembership
                      : model.busy || model.invalidated
                      ? null
                      : () {
                          _statisticsRefresh++;
                          unawaited(_apply());
                        },
                  tooltip: t('refresh'),
                  icon: const StandardIcon(StandardIconSemantic.refresh),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                t('scope'),
                style: TextStyle(color: context.tokens.colors.textSecondary),
              ),
            ),
            if (!model.invalidated && (model.error == null || page != null))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  type: MaterialType.transparency,
                  child: CommunityShipStatisticsPanel(
                    key: ValueKey(
                      'ship-statistics:${widget.targetRef}:${communityShipsCulture(context)}:$_statisticsRefresh:$_statisticsRevision',
                    ),
                    port: widget.port,
                    targetRef: widget.targetRef,
                    culture: communityShipsCulture(context),
                    firstPage: model.page,
                    loadingHeight: _statisticsHeight,
                    onHeightChanged: (height) => _statisticsHeight = height,
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 660
                        ? constraints.maxWidth
                        : 320,
                    child: TextField(
                      controller: _search,
                      maxLength: 128,
                      enabled: !model.invalidated,
                      decoration: InputDecoration(
                        labelText: t('search'),
                        counterText: '',
                        prefixIcon: const StandardIcon(StandardIconSemantic.search),
                      ),
                      onSubmitted: (_) => unawaited(_apply()),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: model.invalidated
                        ? null
                        : () => unawaited(_apply()),
                    child: Text(t('searchButton')),
                  ),
                  _choice(
                    'sort',
                    _sort,
                    const ['name', 'spec', 'status', 'price', 'role', 'owner'],
                    (value) {
                      _sort = value;
                      _descending = const {
                        'spec',
                        'status',
                        'price',
                      }.contains(value);
                      unawaited(_apply());
                    },
                    175,
                  ),
                  IconButton(
                    onPressed: model.invalidated
                        ? null
                        : () {
                            _descending = !_descending;
                            unawaited(_apply());
                          },
                    tooltip: t(_descending ? 'descending' : 'ascending'),
                    icon: StandardIcon(_descending ? StandardIconSemantic.south : StandardIconSemantic.north),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView(
                key: const ValueKey('community-ship-filters'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in const [
                    'all',
                    'capital',
                    'large',
                    'medium',
                    'small',
                    'flyable',
                    'concept',
                    'unknown',
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        key: ValueKey('community-ship-filter-$filter'),
                        showCheckmark: false,
                        labelStyle: Theme.of(context).textTheme.labelLarge,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                        pressElevation: 0,
                        chipAnimationStyle: ChipAnimationStyle(
                          enableAnimation: AnimationStyle.noAnimation,
                          selectAnimation: AnimationStyle.noAnimation,
                          avatarDrawerAnimation: AnimationStyle.noAnimation,
                          deleteDrawerAnimation: AnimationStyle.noAnimation,
                        ),
                        label: Text(t(filter)),
                        selected: _filter == filter,
                        onSelected: model.invalidated
                            ? null
                            : (_) {
                                _filter = filter;
                                unawaited(_apply());
                              },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (model.mediaFailed)
              Text(
                t('mediaFailed'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            const CommunityShipColumnHeader(),
            SizedBox(
              height: 2,
              child: page != null && model.busy
                  ? const LinearProgressIndicator()
                  : null,
            ),
            if (page != null && model.error != null)
              Row(
                children: [
                  Expanded(child: Text(t('refreshFailed'))),
                  TextButton(
                    onPressed: model.busy ? null : _apply,
                    child: Text(t('refresh')),
                  ),
                ],
              ),
            Expanded(
              child: model.busy && page == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(t('loading')),
                        ],
                      ),
                    )
                  : model.error != null && page == null
                  ? _state(t(model.error!))
                  : page == null
                  ? const SizedBox.shrink()
                  : page.ships.isEmpty
                  ? _state(
                      t(page.totalCount == 0 ? 'empty' : 'noMatches'),
                      clear: page.totalCount > 0,
                    )
                  : ListView.separated(
                      padding: const EdgeInsetsDirectional.only(end: 16),
                      key: ValueKey((
                        widget.targetRef,
                        page.query,
                        page.offset,
                      )),
                      itemCount: page.ships.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ship(page.ships[index]),
                          CommunityShipLoaners(ship: page.ships[index]),
                        ],
                      ),
                    ),
            ),
            if (page != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${page.matchedCount == 0 ? 0 : page.offset + 1}–${page.offset + page.ships.length} / ${page.matchedCount}',
                    ),
                    OutlinedButton(
                      onPressed: page.offset == 0 || model.busy
                          ? null
                          : () => unawaited(model.previous()),
                      child: Text(t('previous')),
                    ),
                    OutlinedButton(
                      onPressed: page.next == null || model.busy
                          ? null
                          : () => unawaited(model.next()),
                      child: Text(t('next')),
                    ),
                  ],
                ),
              ),
          ],
        );
        // Keep all controls reachable when an expanded organization header
        // leaves too little room for the ship tools and the first banner.
        final minimumHeight = available.maxWidth < 760 ? 1050.0 : 740.0;
        if (available.maxHeight < minimumHeight) {
          return SingleChildScrollView(
            child: SizedBox(height: minimumHeight, child: body),
          );
        }
        return body;
      },
    );
  }

  Widget _state(String message, {bool clear = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          if (clear)
            TextButton(onPressed: _clear, child: Text(t('clear')))
          else if (!model.invalidated)
            TextButton(
              onPressed: () => unawaited(_apply()),
              child: Text(t('refresh')),
            ),
        ],
      ),
    ),
  );
  Widget _ship(CommunitySharedShip ship) {
    final colors = context.tokens.colors;
    final owner = ship.ownerCallsign.isNotEmpty
        ? ship.ownerCallsign
        : ship.ownerGameName.isNotEmpty
        ? ship.ownerGameName
        : t('owner');
    final presenceKey = !ship.ownerOnline
        ? 'presence.offline'
        : ship.ownerLiveStatus.toLowerCase() == 'ingame'
        ? 'presence.inGame'
        : ship.ownerLiveStatus.toLowerCase() == 'away'
        ? 'presence.away'
        : 'presence.online';
    final presence = presenceColor(colors, presenceKey);
    final status = ship.catalogStatus?.toLowerCase() ?? '';
    final statusColor = const {'flyable', '可飞', '可飛'}.contains(status)
        ? colors.success
        : status.contains('concept') || status.contains('概念')
        ? colors.warning
        : colors.textSecondary;
    final roleColor = shipCategoryColor(
      context,
      ship.displayCategory?.toLowerCase() ?? 'unknown',
    );
    final specColor = shipSizeColor(context, ship.displaySpec);
    String value(String? text, [String fallback = 'unknown']) =>
        text == null || text.isEmpty ? t(fallback) : text;
    Widget line(
      String text, {
      Color? color,
      bool bold = false,
      bool title = false,
    }) => Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color ?? colors.textPrimary,
          fontWeight: bold ? FontWeight.w600 : null,
          fontSize: title ? 14 : null,
        ),
      ),
    );
    Widget badge(String text, Color color) =>
        ShipClassificationTag(label: text, color: color);
    final ownerRow = Row(
      children: [
        Tooltip(
          message: AppStrings.of(context).text(presenceKey),
          child: UserAvatarMenu(
            name: owner,
            avatarBytes: model.avatar(ship.ownerMemberRef),
            isSelf: ship.ownerIsSelf,
            target: UserTarget.community(widget.targetRef, ship.ownerMemberRef, query: ship.ownerGameName),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: presence, width: 2)),
              ),
              child: CommunityWorkspaceImage(
                bytes: model.avatar(ship.ownerMemberRef),
                decoder: model.avatars.images.decode,
                maxWidth: 96,
                loading: model.avatarLoading(ship.ownerMemberRef),
                icon: StandardIconSemantic.person,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(
                '$owner${ship.ownerIsSelf ? ' · ${t('self')}' : ''}',
                bold: true,
              ),
              line(
                ship.ownerGameName.isNotEmpty && ship.ownerGameName != owner
                    ? ship.ownerGameName
                    : AppStrings.of(context).text(presenceKey),
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
    final imported = ship.hangarImportedAt?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = imported == null
        ? t('notRecorded')
        : '${imported.year}-${two(imported.month)}-${two(imported.day)}';
    return CommunityShipRowSurface(
      child: CommunityShipBanner(
        key: ValueKey('community-ship-banner-${ship.shipRef}'),
        identity: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CommunityCatalogShipImage(
                asset: ship.catalogThumbnailAsset ?? ship.catalogImageAsset,
                compact: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(
                    ship.displayName.isEmpty ? ship.code : ship.displayName,
                    bold: true,
                    title: true,
                  ),
                  if (ship.subtitleFor(
                        Localizations.localeOf(context).languageCode,
                      )
                      case final subtitle?)
                    line(subtitle, color: colors.textSecondary),
                ],
              ),
            ),
          ],
        ),
        spec: badge(
          communityShipDisplayText(context, ship.displaySpec),
          specColor,
        ),
        status: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: line(value(ship.catalogStatus), color: statusColor),
            ),
          ],
        ),
        price: line(
          ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ?? t('unpublished'),
          color: ShipCatalogDisplay.usdCents(ship.catalogPriceUsd) == null
              ? colors.textSecondary
              : colors.info,
        ),
        role: badge(
          communityShipDisplayText(context, ship.displayRole),
          roleColor,
        ),
        vehicleIcon: CommunityShipVehicleIcon(ship: ship),
        owner: ownerRow,
        importedAt: Tooltip(
          message: t('importedAt'),
          child: line(date, color: colors.textSecondary),
        ),
        action: OutlinedButton(
          key: ValueKey('community-ship-details-${ship.shipRef}'),
          onPressed: () => unawaited(_openDetail(ship)),
          child: Text(t('view')),
        ),
      ),
    );
  }
}
