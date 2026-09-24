import '../../shared/ships/catalog_vehicle_icon.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';
import 'personal_profile_ship_names.dart';
import '../hangar/local_hangar_copy.dart';

class PersonalProfileFavoriteShips extends StatelessWidget {
  const PersonalProfileFavoriteShips({
    required this.ships,
    required this.span,
    this.hangarAvailable = true,
    this.unresolvedCount = 0,
    this.headerTrailing,
    super.key,
  });

  final List<PersonalProfileShipSummary> ships;
  final int span;
  final bool hangarAvailable;
  final int unresolvedCount;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
              child: Text(
                AppStrings.of(context)
                    .text(
                      unresolvedCount > 0
                          ? 'profile.ships.pendingDetails'
                          : hangarAvailable
                          ? 'profile.ships.empty'
                          : 'profile.ships.notConnected',
                    )
                    .replaceAll('{count}', '$unresolvedCount'),
                key: const Key('profile-favorites-empty-state'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
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
                      Expanded(child: _ShipCard(ship: ships[index])),
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
}

class _ShipCard extends StatelessWidget {
  const _ShipCard({required this.ship});

  final PersonalProfileShipSummary ship;

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
        child: InkWell(
          key: Key('profile-favorite-ship-${ship.identity.runtimeId}'),
          borderRadius: tokens.shape.small,
          onTap: () => _showShipData(context, ship),
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
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (secondaryLabel.isNotEmpty)
                        Text(
                          secondaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: tokens.colors.textSecondary,
                                    ),
                              ),
                            ),
                            if (ship.catalogIconKey case final String key) ...[
                              const SizedBox(width: 6),
                              CatalogVehicleIcon.byKey(iconKey: key, size: 24),
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

Future<void> _showShipData(
  BuildContext context,
  PersonalProfileShipSummary ship,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ShipDataDialog(ship: ship),
  );
}

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
                    IconButton(
                      key: const Key('profile-ship-data-close'),
                      tooltip: strings.text('profile.shipData.close'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.windowClose,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.space.md),
                AspectRatio(
                  key: const Key('profile-ship-data-hero'),
                  aspectRatio: 1200 / 420,
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
