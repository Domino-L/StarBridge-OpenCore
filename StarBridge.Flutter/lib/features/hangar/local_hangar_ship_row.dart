import 'package:flutter/material.dart';

export 'local_hangar_ship_image.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_names.dart';
import 'hangar_ship_icon.dart';
import 'hangar_combat_motion.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_images.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_card_image.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../shared/ships/ship_category_colors.dart';

class LocalHangarShipRow extends StatelessWidget {
  const LocalHangarShipRow({
    required this.item,
    required this.elapsed,
    required this.onTap,
    this.onFavorite,
    this.showFavorite = false,
    this.imagePort,
    this.imageCache,
    this.imageCacheKey = '',
    this.instanceIndex = 1,
    this.instanceCount = 1,
    super.key,
  });
  final LocalHangarPresentation item;
  final Duration elapsed;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool showFavorite;
  final LocalHangarImagePort? imagePort;
  final LocalHangarImageCache? imageCache;
  final String imageCacheKey;
  final int instanceIndex, instanceCount;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    final ship = item.ship;
    final title = LocalHangarNames.primary(Localizations.localeOf(context), ship);
    final subtitle = [
      if (title != ship.title) ship.title,
      if (ship.liner?.trim().isNotEmpty == true) ship.liner!.trim(),
    ].join(' · ');
    final combat = HangarCombatSize.parse(ship.size);
    final size = c.combatSize(item.sizeClass ?? ship.size);
    Widget identity() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (instanceCount > 1)
          Text(
            c.instance(instanceIndex, instanceCount),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
    Widget metadata() => Row(
      key: ValueKey('local-hangar-classification-${ship.id}'),
      children: [
        SizedBox(
          key: ValueKey('local-hangar-icon-column-${ship.id}'),
          width: 32,
          child: Center(
            child: HangarShipIcon(
              key: ValueKey('local-hangar-combat-${ship.id}'),
              display: ship.display,
              legacyCombatSize: combat,
              elapsed: elapsed,
            ),
          ),
        ),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (size != null)
                ShipClassificationTag(
                  label: size,
                  color: shipSizeColor(context, item.sizeClass ?? ship.size),
                ),
              if (item.role != 'unknown')
                ShipClassificationTag(
                  label: c.category(item.role),
                  color: shipCategoryColor(context, item.role),
                ),
              if (item.status != 'unknown')
                Text(
                  c.status(item.status),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: item.status == 'flyable'
                        ? tokens.colors.success
                        : tokens.colors.warning,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    Widget price() => StarBridgeTooltip(
      message: c.priceBasis,
      child: Text(
        item.priceCents == null
            ? c.noPrice
            : '${c.usd(item.priceCents! / 100)} USD',
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: item.priceCents == null
              ? tokens.colors.textSecondary
              : tokens.colors.info,
        ),
      ),
    );

    return Material(
      color: tokens.surfaces.panel.fill,
      child: StarBridgeActionRow(
        controlKey: ValueKey('hangar-open-${ship.id}'),
        baseRadius: tokens.shape.radiusSmall,
        onActivate: (_, _) => onTap(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 760 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18;
              return Row(
                children: [
                  LocalHangarCardImage(
                    item: item,
                    imagePort: imagePort,
                    cache: imageCache,
                    cacheKey: imageCacheKey,
                    width: wide ? 160 : 96,
                    height: wide ? 56 : 40,
                  ),
                  SizedBox(width: tokens.space.md),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              Expanded(flex: 5, child: identity()),
                              SizedBox(width: tokens.space.md),
                              Expanded(flex: 4, child: metadata()),
                              SizedBox(width: tokens.space.md),
                              SizedBox(width: 126, child: price()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              identity(),
                              SizedBox(height: tokens.space.xs),
                              metadata(),
                              SizedBox(height: tokens.space.xs),
                              price(),
                            ],
                          ),
                  ),
                  if (showFavorite)
                    StarBridgeIconAction(
                      controlKey: ValueKey('hangar-favorite-${ship.id}'),
                      label: ship.isFavorite ? c.unfavorite : c.favorite,
                      selected: ship.isFavorite,
                      onActivate: onFavorite == null
                          ? null
                          : (_) => onFavorite!(),
                      icon: StandardIcon(
                        ship.isFavorite
                            ? StandardIconSemantic.bookmarked
                            : StandardIconSemantic.bookmark,
                        color: ship.isFavorite
                            ? tokens.colors.warning
                            : tokens.colors.textSecondary,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
