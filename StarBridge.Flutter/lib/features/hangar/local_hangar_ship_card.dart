import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'local_hangar_names.dart';
import 'hangar_combat_motion.dart';
import 'hangar_ship_icon.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_card_image.dart';
import 'local_hangar_images.dart';
import 'local_hangar_image_cache.dart';

/// One saved inventory instance per card. No model/name-based identity.
class LocalHangarShipCard extends StatelessWidget {
  const LocalHangarShipCard({
    required this.item,
    required this.elapsed,
    required this.onTap,
    this.onFavorite,
    this.sameModel = false,
    this.imagePort,
    this.imageRevision = 0,
    this.ownerGeneration = 0,
    this.instanceIndex = 1,
    this.instanceCount = 1,
    this.imageCache,
    super.key,
  });
  final LocalHangarPresentation item;
  final Duration elapsed;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool sameModel;
  final LocalHangarImagePort? imagePort;
  final int imageRevision;
  final int ownerGeneration;
  final int instanceIndex, instanceCount;
  final LocalHangarImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens, ship = item.ship;
    final title = LocalHangarNames.primary(
      Localizations.localeOf(context),
      ship,
    );
    final size = c.combatSize(item.sizeClass ?? ship.size);
    return Material(
      color: t.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: t.shape.small,
        side: BorderSide(color: t.surfaces.panel.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: StarBridgeActionRow(
        controlKey: ValueKey('hangar-open-${ship.id}'),
        baseRadius: t.shape.radiusSmall,
        onActivate: (_, _) => onTap(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, bounds) => LocalHangarCardImage(
                  key: ValueKey(
                    'hangar-card-image-$ownerGeneration:${ship.id}:$imageRevision',
                  ),
                  item: item,
                  width: bounds.maxWidth,
                  imagePort: imagePort,
                  cache: imageCache,
                  cacheKey: '$ownerGeneration:${ship.id}:$imageRevision',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StarBridgeTooltip(
                      message: title,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  StarBridgeIconAction(
                    controlKey: ValueKey('hangar-favorite-${ship.id}'),
                    label: ship.isFavorite ? c.unfavorite : c.favorite,
                    selected: ship.isFavorite,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    padding: EdgeInsets.zero,
                    onActivate: onFavorite == null
                        ? null
                        : (_) => onFavorite!(),
                    icon: StandardIcon(
                      ship.isFavorite
                          ? StandardIconSemantic.bookmarked
                          : StandardIconSemantic.bookmark,
                      color: ship.isFavorite
                          ? t.colors.warning
                          : t.colors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              Text(
                ship.nickname?.trim().isNotEmpty == true
                    ? LocalHangarNames.model(
                        Localizations.localeOf(context),
                        ship,
                      )
                    : ship.liner ?? '',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (size != null)
                    ShipClassificationTag(
                      label: size,
                      color: shipSizeColor(
                        context,
                        item.sizeClass ?? ship.size,
                      ),
                    ),
                  if (item.role != 'unknown')
                    ShipClassificationTag(
                      label: c.category(item.role),
                      color: shipCategoryColor(context, item.role),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  HangarShipIcon(
                    display: ship.display,
                    legacyCombatSize: HangarCombatSize.parse(ship.size),
                    elapsed: elapsed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.status == 'unknown' ? '' : c.status(item.status),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: item.status == 'flyable'
                            ? t.colors.success
                            : t.colors.warning,
                      ),
                    ),
                  ),
                  if (item.priceCents != null)
                    Expanded(
                      child: StarBridgeTooltip(
                        message: c.priceBasis,
                        child: Text(
                          c.usd(item.priceCents! / 100),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
              if (sameModel)
                StarBridgeTooltip(
                  message: c.sameModel,
                  child: Text(
                    c.instance(instanceIndex, instanceCount),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
