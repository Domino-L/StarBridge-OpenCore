import '../../shared/ships/ship_art_ratio.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_vehicle_icon.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_favorite_maker.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';
import 'personal_profile_ship_names.dart';
import 'personal_profile_showcase_frame.dart';
import 'personal_profile_visitor_favorites.dart';
import '../hangar/local_hangar_copy.dart';
import '../../platform/window/native_viewport_visibility.dart';

class PersonalProfileFavoriteShips extends StatelessWidget {
  const PersonalProfileFavoriteShips({
    required this.ships,
    required this.span,
    this.hangarAvailable = true,
    this.unresolvedCount = 0,
    this.showPartialPending = false,
    this.headerTrailing,
    this.onViewShipData,
    super.key,
  });

  final List<PersonalProfileShipSummary> ships;
  final int span;
  final bool hangarAvailable;
  final int unresolvedCount;
  final bool showPartialPending;
  final Widget? headerTrailing;

  /// A stable parent may own the dialog when this view is rebuilt by responsive
  /// grid reflow. It receives only the already-projected ship, not an ID lookup
  /// or a write capability. Without it, the source card owns its own dialog.
  final Future<void> Function(
    BuildContext,
    PersonalProfileShipSummary,
    InteractionSource,
  )?
  onViewShipData;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (ProfileShowcaseScope.of(context) && ships.isNotEmpty) {
      // The single column has no cell size: every chosen ship shows.
      return PersonalProfileModuleSurface(
        icon: StarBridgeIconSemantic.hangar,
        titleKey: 'profile.ships.title',
        accentRole: DomainColorRole.ship,
        headerTrailing: headerTrailing,
        showcasePadding: EdgeInsets.zero,
        child: _FavoriteShowcase(
          ships: ships,
          onViewShipData: onViewShipData,
          pending: showPartialPending && unresolvedCount > 0
              ? _pendingText(context)
              : null,
        ),
      );
    }
    final visibleCount = ships.length < span ? ships.length : span;
    final hiddenCount = ships.length - visibleCount;
    final resolvedTrailing = hiddenCount > 0 || headerTrailing != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hiddenCount > 0)
                Text(
                  '+$hiddenCount',
                  key: const Key('profile-favorite-ships-hidden-count'),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
              if (hiddenCount > 0 && headerTrailing != null)
                SizedBox(width: tokens.space.sm),
              ?headerTrailing,
            ],
          )
        : null;
    return PersonalProfileModuleSurface(
      icon: StarBridgeIconSemantic.hangar,
      titleKey: 'profile.ships.title',
      accentRole: DomainColorRole.ship,
      headerTrailing: resolvedTrailing,
      child: ships.isEmpty
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: _pendingText(context),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final vertical =
                    visibleCount > 1 &&
                    constraints.maxHeight > 220 &&
                    constraints.maxWidth / visibleCount < 260;
                return Flex(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < visibleCount; index++) ...[
                      Expanded(
                        key: ValueKey(ships[index].identity.runtimeId),
                        child: _ShipCard(
                          ship: ships[index],
                          onViewShipData: onViewShipData,
                        ),
                      ),
                      if (index != ships.length - 1 && index != span - 1)
                        SizedBox(
                          width: vertical ? 0 : tokens.space.sm,
                          height: vertical ? tokens.space.sm : 0,
                        ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _pendingText(BuildContext context) =>
      profileFavoritesStateText(context, unresolvedCount, hangarAvailable);
}

/// Single-column showcase: the first favourite large with its maker mark,
/// up to 3 more as cards (1 + 3, the 4th from `favoriteShowcaseExtra`).
class _FavoriteShowcase extends StatefulWidget {
  const _FavoriteShowcase({
    required this.ships,
    this.onViewShipData,
    this.pending,
  });
  final Widget? pending;

  final List<PersonalProfileShipSummary> ships;
  final Future<void> Function(
    BuildContext,
    PersonalProfileShipSummary,
    InteractionSource,
  )?
  onViewShipData;

  @override
  State<_FavoriteShowcase> createState() => _FavoriteShowcaseState();
}

class _FavoriteShowcaseState extends State<_FavoriteShowcase> {
  @override
  void initState() {
    super.initState();
    ProfileFavoriteMaker.load(this, () => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final ships = widget.ships;
    final onViewShipData = widget.onViewShipData;
    final gap = context.tokens.space.sm;
    final rest = ships.skip(1).take(3).toList();
    return Column(
      key: const Key('profile-favorite-showcase'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShipCard(
          key: ValueKey(ships.first.identity.runtimeId),
          ship: ships.first,
          onViewShipData: onViewShipData,
          style: _ShipCardStyle.hero,
        ),
        if (rest.isNotEmpty)
          Padding(
            padding: EdgeInsets.all(gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < 3; index++) ...[
                  if (index > 0) SizedBox(width: gap),
                  Expanded(
                    child: index < rest.length
                        ? _ShipCard(
                            key: ValueKey(rest[index].identity.runtimeId),
                            ship: rest[index],
                            onViewShipData: onViewShipData,
                            style: _ShipCardStyle.card,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ProfileFavoriteMakerNotice(
          manufacturer: ships.first.manufacturer,
          gap: gap,
        ),
        ?widget.pending,
      ],
    );
  }
}

enum _ShipCardStyle { row, hero, card }

class _ShipCard extends StatefulWidget {
  const _ShipCard({
    required this.ship,
    this.onViewShipData,
    this.style = _ShipCardStyle.row,
    super.key,
  });

  final _ShipCardStyle style;
  final PersonalProfileShipSummary ship;
  final Future<void> Function(
    BuildContext,
    PersonalProfileShipSummary,
    InteractionSource,
  )?
  onViewShipData;

  @override
  State<_ShipCard> createState() => _ShipCardState();
}

class _ShipCardState extends State<_ShipCard> {
  StarBridgeDialogRoute<void>? _details;
  PersonalProfileShipSummary get ship => widget.ship;

  void _retireDetails() {
    final route = _details;
    _details = null;
    retireStarBridgeDialog(route);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!NativeViewportScope.isActive(context)) _retireDetails();
  }

  @override
  void didUpdateWidget(_ShipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ship, ship) ||
        (oldWidget.onViewShipData == null) != (widget.onViewShipData == null)) {
      _retireDetails();
    }
  }

  @override
  void dispose() {
    _retireDetails();
    super.dispose();
  }

  Future<void> _openDetails(
    BuildContext context,
    InteractionSource source,
  ) async {
    if (_details?.isActive == true || !NativeViewportScope.isActive(context)) {
      return;
    }
    final parent = widget.onViewShipData;
    if (parent != null) return parent(context, ship, source);
    final selected = ship;
    late StarBridgeDialogRoute<void> route;
    await showProfileShipDataDialog(
      context,
      selected,
      source: source,
      onRouteCreated: (created) => _details = route = created,
    );
    if (identical(_details, route)) _details = null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final shipColors = tokens.domainColors.ship;
    final thumbnail = ship.thumbnailAsset ?? ship.imageAsset;
    final primaryName = PersonalProfileShipNames.primary(
      context,
      ship.identity,
    );
    final secondaryName = PersonalProfileShipNames.secondary(
      context,
      ship.identity,
    );
    final secondaryLabel = secondaryName ?? ship.manufacturer;
    final metadata = <String>[
      if (ship.sizeKey.isNotEmpty) strings.text(ship.sizeKey),
      if (ship.roleKey.isNotEmpty) strings.text(ship.roleKey),
    ];
    if (widget.style != _ShipCardStyle.row) {
      return _buildPicture(
        context,
        primaryName,
        [
          if (secondaryLabel.isNotEmpty) secondaryLabel,
          ...metadata.reversed,
        ].join(' · '),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaces.status.fill,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.status.border,
          width: tokens.stroke.hairline,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: StarBridgeActionRow(
          controlKey: Key('profile-favorite-ship-${ship.identity.runtimeId}'),
          baseRadius: tokens.shape.radiusSmall,
          semanticLabel:
              '${strings.text('profile.shipData.title')} · $primaryName',
          onActivate: NativeViewportScope.isActive(context)
              ? _openDetails
              : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space.sm,
              vertical: tokens.space.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: tokens.density.controlHeight + tokens.space.md,
                  height: tokens.density.controlHeight + tokens.space.md,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: shipColors.soft,
                    borderRadius: tokens.shape.small,
                  ),
                  child: thumbnail.isEmpty
                      ? const _ShipImageFallback()
                      : Image.asset(
                          thumbnail,
                          cacheWidth: 128,
                          key: Key(
                            'profile-favorite-ship-image-'
                            '${ship.identity.runtimeId}',
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const _ShipImageFallback(),
                        ),
                ),
                SizedBox(width: tokens.space.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryName,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (secondaryLabel.isNotEmpty)
                        Text(
                          secondaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      if (metadata.isNotEmpty)
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                metadata.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: tokens.colors.textSecondary,
                                    ),
                              ),
                            ),
                            if (ship.catalogIconKey case final String key) ...[
                              const SizedBox(width: 6),
                              ShipVehicleIcon(
                                names: [
                                  ship.identity.catalogId,
                                  ship.identity.englishName,
                                  ship.identity.runtimeId,
                                ],
                                size: 24,
                                fallback: CatalogVehicleIcon.byKey(
                                  iconKey: key,
                                  size: 24,
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                if (ship.valueLabel.isNotEmpty || ship.formerlyOwned) ...[
                  SizedBox(width: tokens.space.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (ship.formerlyOwned)
                        Container(
                          key: Key('profile-former-${ship.identity.runtimeId}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.colors.warning.withValues(alpha: .12),
                            borderRadius: tokens.shape.small,
                          ),
                          child: Text(
                            LocalHangarCopy(context).formerlyOwned,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tokens.colors.warning),
                          ),
                        ),
                      if (ship.valueLabel.isNotEmpty)
                        Text(
                          ship.valueLabel,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: tokens.colors.info,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on _ShipCardState {
  Widget _buildPicture(BuildContext context, String name, String detail) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final hero = widget.style == _ShipCardStyle.hero;
    final asset = ship.imageAsset.isNotEmpty
        ? ship.imageAsset
        : ship.thumbnailAsset ?? '';
    final picture = AspectRatio(
      // Every ship card, the leading favourite included, is 2:1 and centre-cropped.
      aspectRatio: shipArtCardAspectRatio,
      child: ColoredBox(
        color: tokens.domainColors.ship.soft,
        child: asset.isEmpty
            ? const _ShipImageFallback()
            : Image.asset(
                asset,
                cacheWidth: hero ? 1400 : 480,
                key: Key(
                  'profile-favorite-ship-image-${ship.identity.runtimeId}',
                ),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ShipImageFallback(),
              ),
      ),
    );
    final Widget body;
    if (hero) {
      body = Stack(
        children: [
          picture,
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: const [0, 0.46],
                  colors: [
                    Colors.black.withValues(alpha: 0.86),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: tokens.space.md,
            end: tokens.space.md,
            bottom: tokens.space.sm,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 23,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                ProfileFavoriteMakerMark(
                  manufacturer: ship.manufacturer,
                  runtimeId: ship.identity.runtimeId,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          picture,
          SizedBox(height: tokens.space.xs),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.colors.textPrimary,
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: tokens.colors.textSecondary,
              ),
            ),
        ],
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: StarBridgeActionRow(
        controlKey: Key('profile-favorite-ship-${ship.identity.runtimeId}'),
        baseRadius: 0,
        semanticLabel: '${strings.text('profile.shipData.title')} · $name',
        onActivate: NativeViewportScope.isActive(context) ? _openDetails : null,
        child: body,
      ),
    );
  }
}

class _ShipImageFallback extends StatelessWidget {
  const _ShipImageFallback();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: StarBridgeIcon(
        StarBridgeIconSemantic.hangar,
        color: tokens.domainColors.ship.foreground,
        size: tokens.icons.medium,
      ),
    );
  }
}

/// Read-only facts from the caller's authorized projection. Lifecycle remains
/// with the source card or its stable parent; no network/read/write is added.
Future<void> showProfileShipDataDialog(
  BuildContext context,
  PersonalProfileShipSummary ship, {
  required InteractionSource source,
  ValueChanged<StarBridgeDialogRoute<void>>? onRouteCreated,
}) => showStarBridgeDialog<void>(
  context,
  source: source,
  onRouteCreated: onRouteCreated,
  builder: (_) => _ShipDataDialog(ship: ship),
);

class _ShipDataDialog extends StatelessWidget {
  const _ShipDataDialog({required this.ship});

  final PersonalProfileShipSummary ship;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final primaryName = PersonalProfileShipNames.primary(
      context,
      ship.identity,
    );
    final secondaryName = PersonalProfileShipNames.secondary(
      context,
      ship.identity,
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: StarBridgeSurface(
        role: SurfaceRole.floating,
        child: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.text('profile.shipData.title'),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: tokens.colors.textSecondary),
                          ),
                          Text(
                            primaryName,
                            key: const Key('profile-ship-data-name'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (ship.formerlyOwned)
                            Text(LocalHangarCopy(context).formerlyOwned),
                          if (secondaryName != null)
                            Text(
                              secondaryName,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: tokens.colors.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    StarBridgeIconAction(
                      controlKey: const Key('profile-ship-data-close'),
                      label: strings.text('profile.shipData.close'),
                      onActivate: (source) =>
                          dismissStarBridgeDialog(context, source: source),
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.windowClose,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.space.md),
                AspectRatio(
                  key: const Key('profile-ship-data-hero'),
                  aspectRatio: shipArtCardAspectRatio,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: tokens.surfaces.ground.fill,
                      borderRadius: tokens.shape.medium,
                    ),
                    child: ship.imageAsset.isEmpty
                        ? const _ShipImageFallback()
                        : Image.asset(
                            ship.imageAsset,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            errorBuilder: (context, error, stackTrace) =>
                                const _ShipImageFallback(),
                          ),
                  ),
                ),
                SizedBox(height: tokens.space.lg),
                Wrap(
                  key: const Key('profile-ship-data-facts'),
                  spacing: tokens.space.xl,
                  runSpacing: tokens.space.md,
                  children: [
                    if (ship.manufacturer.isNotEmpty)
                      _ShipDataFact(
                        labelKey: 'profile.ship.manufacturer',
                        value: ship.manufacturer,
                      ),
                    if (ship.roleKey.isNotEmpty)
                      _ShipDataFact(
                        labelKey: 'profile.shipData.role',
                        value: strings.text(ship.roleKey),
                      ),
                    if (ship.sizeKey.isNotEmpty)
                      _ShipDataFact(
                        labelKey: 'profile.ship.size',
                        value: strings.text(ship.sizeKey),
                      ),
                    if (ship.valueLabel.isNotEmpty)
                      _ShipDataFact(
                        labelKey: ship.valueLabelKey,
                        value: ship.valueLabel,
                        valueColor: tokens.colors.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShipDataFact extends StatelessWidget {
  const _ShipDataFact({
    required this.labelKey,
    required this.value,
    this.valueColor,
  });

  final String labelKey;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.of(context).text(labelKey),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: valueColor,
              fontWeight: valueColor == null ? null : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
