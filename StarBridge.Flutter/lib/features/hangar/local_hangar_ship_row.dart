import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../ships/ship_display_names.dart';
import 'hangar_ship_icon.dart';
import 'hangar_combat_motion.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../shared/ships/ship_category_colors.dart';

class LocalHangarShipRow extends StatelessWidget {
  const LocalHangarShipRow({
    required this.item,
    required this.elapsed,
    required this.onTap,
    super.key,
  });
  final LocalHangarPresentation item;
  final Duration elapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    final ship = item.ship;
    final title = ShipDisplayNames.primary(
      Localizations.localeOf(context),
      original: ship.title,
      simplifiedChinese: ship.cn,
      traditionalChinese: ship.tw,
    );
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
    Widget price() => Tooltip(
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
      child: InkWell(
        onTap: onTap,
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
                  LocalHangarShipImage(
                    item: item,
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class LocalHangarShipImage extends StatelessWidget {
  const LocalHangarShipImage({
    required this.item,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    super.key,
  });
  final LocalHangarPresentation item;
  final double width, height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    Widget fallback() => Tooltip(
      message: c.imageUnavailable,
      child: Center(
        child: StarBridgeIcon(
          StarBridgeIconSemantic.hangar,
          color: tokens.colors.textSecondary,
          size: 24,
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: tokens.shape.small,
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: tokens.surfaces.ground.fill,
            child: item.bundledImage == null
                ? fallback()
                : Image.asset(
                    item.bundledImage!,
                    fit: fit,
                    excludeFromSemantics: true,
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    frameBuilder: (_, child, frame, synchronouslyLoaded) =>
                        frame != null || synchronouslyLoaded
                        ? child
                        : fallback(),
                    errorBuilder: (_, _, _) => fallback(),
                  ),
          ),
        ),
      ),
    );
  }
}
