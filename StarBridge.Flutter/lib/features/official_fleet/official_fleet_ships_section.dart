import 'package:flutter/material.dart';

import '../../shared/ships/ship_catalog_display.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_ships_models.dart';
import 'official_fleet_ships_module.dart';
import 'official_fleet_ships_summary.dart';
import 'official_fleet_ships_toolbar.dart';
import 'official_fleet_support_views.dart';

class OfficialFleetShipsSection extends StatefulWidget {
  const OfficialFleetShipsSection({
    required this.sourceRef,
    required this.module,
    super.key,
  });

  final String sourceRef;
  final OfficialFleetShipsModule module;

  @override
  State<OfficialFleetShipsSection> createState() =>
      _OfficialFleetShipsSectionState();
}

class _OfficialFleetShipsSectionState extends State<OfficialFleetShipsSection> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.module.open(widget.sourceRef);
    });
  }

  @override
  void didUpdateWidget(covariant OfficialFleetShipsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceRef != widget.sourceRef ||
        oldWidget.module != widget.module) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.module.open(widget.sourceRef);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfficialFleetShipsProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        return switch (projection.availability) {
          OfficialFleetShipsAvailability.idle ||
          OfficialFleetShipsAvailability.loading => const _ShipsLoading(),
          OfficialFleetShipsAvailability.unavailable => OfficialFleetStatePanel(
            key: const Key('official-fleet-ships-unavailable'),
            icon: StarBridgeIconSemantic.warning,
            color: context.tokens.colors.warning,
            titleKey: 'officialFleet.ships.unavailable.title',
            bodyKey:
                projection.failureKey ??
                'officialFleet.ships.error.unavailable',
            actionKey: 'officialFleet.action.retry',
            onAction: widget.module.refresh,
          ),
          OfficialFleetShipsAvailability.available => _ShipsContent(
            projection: projection,
            module: widget.module,
            searchController: _searchController,
          ),
        };
      },
    );
  }
}

class _ShipsLoading extends StatelessWidget {
  const _ShipsLoading();

  @override
  Widget build(BuildContext context) {
    return StarBridgeSurface(
      key: const Key('official-fleet-ships-loading'),
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: context.tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: context.tokens.space.md),
          Text(AppStrings.of(context).text('officialFleet.ships.loading')),
        ],
      ),
    );
  }
}

class _ShipsContent extends StatelessWidget {
  const _ShipsContent({
    required this.projection,
    required this.module,
    required this.searchController,
  });

  final OfficialFleetShipsProjection projection;
  final OfficialFleetShipsModule module;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      key: const Key('official-fleet-ships'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.text('officialFleet.ships.title'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: tokens.space.xxs),
        Text(
          strings.text('officialFleet.ships.body'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.md),
        OfficialFleetShipSummary(projection: projection),
        SizedBox(height: tokens.space.md),
        OfficialFleetShipsToolbar(
          projection: projection,
          module: module,
          searchController: searchController,
        ),
        SizedBox(height: tokens.space.md),
        if (projection.ships.isEmpty)
          OfficialFleetStatePanel(
            key: const Key('official-fleet-ships-empty'),
            icon: StarBridgeIconSemantic.hangar,
            color: tokens.domainColors.ship.foreground,
            titleKey: 'officialFleet.ships.empty.title',
            bodyKey: 'officialFleet.ships.empty.body',
          )
        else
          _ShipsList(ships: projection.ships),
        SizedBox(height: tokens.space.md),
        _ShipsPagination(projection: projection, module: module),
      ],
    );
  }
}

class _ShipsList extends StatelessWidget {
  const _ShipsList({required this.ships});

  final List<OfficialFleetSharedShip> ships;

  @override
  Widget build(BuildContext context) {
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dense = constraints.maxWidth >= 760;
          final availableHeight = MediaQuery.sizeOf(context).height - 470;
          final height = availableHeight
              .clamp(dense ? 390.0 : 344.0, dense ? 760.0 : 560.0)
              .toDouble();
          return SizedBox(
            height: height,
            child: ListView.separated(
              key: const Key('official-fleet-ships-virtual-list'),
              itemCount: ships.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: context.tokens.surfaces.panel.border,
              ),
              itemBuilder: (context, index) =>
                  _ShipRow(ship: ships[index], number: index + 1),
            ),
          );
        },
      ),
    );
  }
}

class _ShipRow extends StatelessWidget {
  const _ShipRow({required this.ship, required this.number});

  final OfficialFleetSharedShip ship;
  final int number;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      key: Key('official-fleet-ship-${ship.shipRef}'),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return KeyedSubtree(
              key: Key('official-fleet-ship-layout-compact-${ship.shipRef}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ShipNumber(number: number),
                      SizedBox(width: tokens.space.xs),
                      _ShipImage(ship: ship),
                      SizedBox(width: tokens.space.sm),
                      Expanded(child: _ShipIdentity(ship: ship)),
                      SizedBox(width: tokens.space.sm),
                      SizedBox(width: 64, child: _PriceValue(ship.priceUsd)),
                      SizedBox(width: tokens.space.sm),
                      _RequestState(ship.requestState),
                    ],
                  ),
                  SizedBox(height: tokens.space.xs),
                  Wrap(
                    spacing: tokens.space.sm,
                    runSpacing: tokens.space.xs,
                    children: [
                      _ShipSizeBadge(ship.size),
                      _CatalogStatus(ship.catalogStatus),
                      _RoleBadge(ship.roleLabel),
                      _OwnerBadge(ship: ship),
                    ],
                  ),
                ],
              ),
            );
          }
          return KeyedSubtree(
            key: Key('official-fleet-ship-layout-dense-${ship.shipRef}'),
            child: Row(
              children: [
                _ShipNumber(number: number),
                SizedBox(width: tokens.space.xs),
                _ShipImage(ship: ship),
                SizedBox(width: tokens.space.sm),
                Expanded(flex: 3, child: _ShipIdentity(ship: ship)),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  flex: 6,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _ShipSizeBadge(ship.size),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _CatalogStatus(ship.catalogStatus),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _RoleBadge(ship.roleLabel),
                        ),
                      ),
                      Expanded(flex: 2, child: _OwnerBadge(ship: ship)),
                    ],
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                SizedBox(width: 64, child: _PriceValue(ship.priceUsd)),
                SizedBox(width: tokens.space.sm),
                _RequestState(ship.requestState),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShipNumber extends StatelessWidget {
  const _ShipNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        number.toString().padLeft(2, '0'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: context.tokens.colors.textSecondary),
      ),
    );
  }
}

class _ShipImage extends StatelessWidget {
  const _ShipImage({required this.ship});

  final OfficialFleetSharedShip ship;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = ColoredBox(
      color: tokens.domainColors.ship.soft,
      child: Center(
        child: StarBridgeIcon(
          StarBridgeIconSemantic.hangar,
          color: tokens.domainColors.ship.foreground,
        ),
      ),
    );
    return Container(
      width: 60,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.surfaces.panel.border),
        borderRadius: tokens.shape.small,
      ),
      child: ShipCatalogDisplay.image(ship.catalogImageAsset) == null
          ? fallback
          : Image.asset(
              ShipCatalogDisplay.image(ship.catalogImageAsset)!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _ShipIdentity extends StatelessWidget {
  const _ShipIdentity({required this.ship});

  final OfficialFleetSharedShip ship;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ship.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tokens.space.xxs),
        Text(
          ship.modelCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
  }
}

class _ShipSizeBadge extends StatelessWidget {
  const _ShipSizeBadge(this.size);

  final OfficialFleetShipSize size;

  @override
  Widget build(BuildContext context) {
    final color = _sizeColor(context, size);
    return _OutlinedLabel(
      label: AppStrings.of(context).text(_sizeLabelKey(size)),
      color: color,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return _OutlinedLabel(
      label: label,
      color: context.tokens.domainColors.logistics.foreground,
    );
  }
}

class _OutlinedLabel extends StatelessWidget {
  const _OutlinedLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.72)),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus(this.status);

  final OfficialFleetShipCatalogStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (status) {
      OfficialFleetShipCatalogStatus.flightReady => tokens.colors.success,
      OfficialFleetShipCatalogStatus.concept => tokens.colors.warning,
      OfficialFleetShipCatalogStatus.unknown => tokens.colors.textSecondary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: tokens.space.xs),
        Text(
          AppStrings.of(context).text(_catalogStatusKey(status)),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge({required this.ship});

  final OfficialFleetSharedShip ship;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.domainColors.command.soft,
            border: Border.all(color: tokens.surfaces.panel.border),
            borderRadius: tokens.shape.small,
          ),
          child: Text(
            ship.ownerDisplay.characters.first.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.domainColors.command.foreground),
          ),
        ),
        SizedBox(width: tokens.space.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ship.ownerDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(
                ship.ownerCallsign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceValue extends StatelessWidget {
  const _PriceValue(this.priceUsd);

  final int priceUsd;

  @override
  Widget build(BuildContext context) {
    return Text(
      '\$$priceUsd',
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.tokens.colors.info,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _RequestState extends StatelessWidget {
  const _RequestState(this.state);

  final OfficialFleetShipRequestState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (state) {
      OfficialFleetShipRequestState.requestable => tokens.colors.success,
      OfficialFleetShipRequestState.unavailable => tokens.colors.warning,
      OfficialFleetShipRequestState.ownedByViewer => tokens.colors.accent,
    };
    return _OutlinedLabel(
      label: AppStrings.of(context).text(_requestStateKey(state)),
      color: color,
    );
  }
}

class _ShipsPagination extends StatefulWidget {
  const _ShipsPagination({required this.projection, required this.module});

  final OfficialFleetShipsProjection projection;
  final OfficialFleetShipsModule module;

  @override
  State<_ShipsPagination> createState() => _ShipsPaginationState();
}

class _ShipsPaginationState extends State<_ShipsPagination> {
  final TextEditingController _pageController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.projection.query!;
    final totalPages = widget.projection.totalPages ?? 1;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      children: [
        OutlinedButton(
          key: const Key('official-fleet-ships-previous-page'),
          onPressed: query.pageNumber > 1
              ? () => widget.module.goToPage(query.pageNumber - 1)
              : null,
          child: Text(strings.text('officialFleet.ships.previousPage')),
        ),
        Text(
          strings
              .text('officialFleet.ships.pageStatus')
              .replaceAll('{page}', query.pageNumber.toString())
              .replaceAll('{total}', totalPages.toString()),
        ),
        OutlinedButton(
          key: const Key('official-fleet-ships-next-page'),
          onPressed: query.pageNumber < totalPages
              ? () => widget.module.goToPage(query.pageNumber + 1)
              : null,
          child: Text(strings.text('officialFleet.ships.nextPage')),
        ),
        SizedBox(
          width: 72,
          child: TextField(
            key: const Key('official-fleet-ships-jump-input'),
            controller: _pageController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: strings.text('officialFleet.ships.pageNumber'),
            ),
            onSubmitted: (_) => _jump(),
          ),
        ),
        OutlinedButton(
          key: const Key('official-fleet-ships-jump'),
          onPressed: _jump,
          child: Text(strings.text('officialFleet.ships.jump')),
        ),
      ],
    );
  }

  void _jump() {
    final value = int.tryParse(_pageController.text);
    if (value != null) {
      widget.module.goToPage(value);
    }
  }
}

Color _sizeColor(BuildContext context, OfficialFleetShipSize size) {
  final tokens = context.tokens;
  return switch (size) {
    OfficialFleetShipSize.capital => tokens.domainColors.command.foreground,
    OfficialFleetShipSize.large => tokens.domainColors.airCombat.foreground,
    OfficialFleetShipSize.medium => tokens.domainColors.ship.foreground,
    OfficialFleetShipSize.small => tokens.domainColors.logistics.foreground,
    OfficialFleetShipSize.unknown => tokens.colors.textSecondary,
  };
}

String _sizeLabelKey(OfficialFleetShipSize size) => switch (size) {
  OfficialFleetShipSize.capital => 'officialFleet.ships.size.capital',
  OfficialFleetShipSize.large => 'officialFleet.ships.size.large',
  OfficialFleetShipSize.medium => 'officialFleet.ships.size.medium',
  OfficialFleetShipSize.small => 'officialFleet.ships.size.small',
  OfficialFleetShipSize.unknown => 'officialFleet.ships.size.unknown',
};

String _catalogStatusKey(OfficialFleetShipCatalogStatus status) =>
    switch (status) {
      OfficialFleetShipCatalogStatus.flightReady =>
        'officialFleet.ships.catalog.flightReady',
      OfficialFleetShipCatalogStatus.concept =>
        'officialFleet.ships.catalog.concept',
      OfficialFleetShipCatalogStatus.unknown =>
        'officialFleet.ships.catalog.unknown',
    };

String _requestStateKey(OfficialFleetShipRequestState state) => switch (state) {
  OfficialFleetShipRequestState.requestable =>
    'officialFleet.ships.request.requestable',
  OfficialFleetShipRequestState.unavailable =>
    'officialFleet.ships.request.unavailable',
  OfficialFleetShipRequestState.ownedByViewer =>
    'officialFleet.ships.request.mine',
};
