import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/styles/hangar_wall_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_art_ratio.dart';
import '../../shared/ships/ship_category_colors.dart';
import '../../shared/ships/ship_vehicle_icon.dart';
import 'hangar_combat_icon.dart';
import 'hangar_combat_motion.dart';
import 'local_hangar_card_image.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_manufacturers.dart';
import 'local_hangar_names.dart';
import 'local_hangar_presentation.dart';

const localHangarArtAspect = 1 / shipArtCardAspectRatio;

/// Fixed geometry of one wall, so a section's height is known without building
/// its cards and scrolling a large hangar never measures anything.
final class LocalHangarWallMetrics {
  LocalHangarWallMetrics._({
    required this.compact,
    required this.columns,
    required this.cellWidth,
    required this.imageHeight,
    required this.extent,
    required this.gapX,
    required this.gapY,
  });

  factory LocalHangarWallMetrics.of(
    BuildContext context, {
    required double width,
    required bool compact,
  }) {
    final gapX = compact ? 8.0 : 12.0, gapY = compact ? 9.0 : 12.0;
    final columns = ((width + gapX) / ((compact ? 130.0 : 210.0) + gapX))
        .floor()
        .clamp(compact ? 2 : 1, 16);
    final cell = (width - gapX * (columns - 1)) / columns;
    final image = cell * localHangarArtAspect;
    final scaler = MediaQuery.textScalerOf(context);
    double line(double size, double height) => scaler.scale(size) * height;
    final text = compact
        ? 3 + line(12.5, 1.3) + line(11, 1.3)
        : 5 + line(14, 1.3) + line(12, 1.35);
    return LocalHangarWallMetrics._(
      compact: compact,
      columns: columns,
      cellWidth: cell,
      imageHeight: image,
      extent: image + text + 2,
      gapX: gapX,
      gapY: gapY,
    );
  }

  final bool compact;
  final int columns;
  final double cellWidth, imageHeight, extent, gapX, gapY;
}

/// The small silhouette beside a ship's name, or its category mark at the same
/// size when the optional pack does not know it. Never animated on the wall.
class LocalHangarWallIcon extends StatelessWidget {
  const LocalHangarWallIcon({
    required this.item,
    required this.size,
    super.key,
  });
  final LocalHangarPresentation item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ship = item.ship, key = ship.display?.iconKey;
    final legacy = ship.display == null
        ? HangarCombatSize.parse(ship.size)
        : null;
    return ExcludeSemantics(
      child: ShipVehicleIcon(
        names: [ship.catalogId, ship.title],
        size: size,
        fallback: key != null
            ? CatalogVehicleIcon.byKey(iconKey: key, size: size)
            : legacy != null
            ? HangarCombatIcon(
                sizeClass: legacy,
                elapsed: const Duration(days: 1),
                active: false,
                dimension: size,
              )
            : SizedBox.square(dimension: size),
      ),
    );
  }
}

/// A maker's official mark. Absent from public source, where nothing is shown
/// and the maker's name beside it carries the meaning.
class LocalHangarMakerMark extends StatelessWidget {
  const LocalHangarMakerMark({
    required this.maker,
    required this.height,
    required this.maxWidth,
    this.onArt = false,
    super.key,
  });
  final LocalHangarManufacturer? maker;
  final double height, maxWidth;

  /// On artwork the mark is always the light one, whatever the appearance.
  final bool onArt;

  @override
  Widget build(BuildContext context) {
    final mark = maker;
    final dark = onArt || HangarWallPalette.of(context).isDark;
    if (mark == null || !LocalHangarMakerLogos.instance.has(mark, dark: dark)) {
      return const SizedBox.shrink();
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // Shown as supplied: no recolor, outline, shadow or effect on the mark.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: height),
      child: Image.asset(
        LocalHangarMakerLogos.asset(mark.key, dark: dark),
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        cacheHeight: (height * ratio).ceil(),
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// The notice the Fan Kit requires wherever its material shows. A host without
/// the app's strings shows no game material either.
class LocalHangarNotice extends StatelessWidget {
  const LocalHangarNotice({super.key});

  @override
  Widget build(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) == null
      ? const SizedBox.shrink()
      : const CigFankitNoticeButton();
}

/// Everything a card used to spell out, for hover and for screen readers.
String localHangarShipSummary(
  BuildContext context,
  LocalHangarCopy c,
  LocalHangarPresentation item, {
  required int instanceIndex,
  required int instanceCount,
  required bool former,
}) {
  final ship = item.ship, locale = Localizations.localeOf(context);
  final maker = LocalHangarManufacturers.of(ship);
  final model = LocalHangarNames.model(locale, ship);
  final name = LocalHangarNames.primary(locale, ship);
  return [
    name,
    if (model != name) model,
    if (ship.title != model) ship.title,
    maker?.name(c) ?? LocalHangarManufacturers.unknownName(ship),
    if (LocalHangarManufacturers.find(ship.liner) == null) ship.liner,
    if (item.role != 'unknown') c.category(item.role),
    c.combatSize(item.sizeClass ?? ship.size),
    if (item.status != 'unknown') c.status(item.status),
    if (item.priceCents != null)
      '${c.usd(item.priceCents! / 100)} ${c.priceBasis}',
    if (instanceCount > 1) c.instance(instanceIndex, instanceCount),
    if (former && ship.removedAt != null)
      '${c.removedAt} ${c.dateTime(context, ship.removedAt!)}',
  ].whereType<String>().join(' · ');
}

/// One saved inventory instance on the wall; no model/name-based identity.
class LocalHangarWallCard extends StatefulWidget {
  const LocalHangarWallCard({
    required this.item,
    required this.metrics,
    required this.showMaker,
    required this.markOnImage,
    required this.instanceIndex,
    required this.instanceCount,
    required this.former,
    required this.cacheKey,
    required this.onOpen,
    this.imagePort,
    this.imageCache,
    this.onFavorite,
    super.key,
  });
  final LocalHangarPresentation item;
  final LocalHangarWallMetrics metrics;

  /// Grouped by size the line names the maker; grouped by maker, the size.
  final bool showMaker;
  final bool markOnImage;
  final int instanceIndex, instanceCount;
  final bool former;
  final String cacheKey;
  final VoidCallback onOpen;
  final VoidCallback? onFavorite;
  final LocalHangarImagePort? imagePort;
  final LocalHangarImageCache? imageCache;

  @override
  State<LocalHangarWallCard> createState() => _LocalHangarWallCardState();
}

class _LocalHangarWallCardState extends State<LocalHangarWallCard> {
  bool _hover = false;

  void _setHover(bool value) {
    if (_hover != value) setState(() => _hover = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final palette = HangarWallPalette.of(context);
    final metrics = widget.metrics, compact = metrics.compact;
    final item = widget.item, ship = item.ship;
    final locale = Localizations.localeOf(context);
    final name = LocalHangarNames.primary(locale, ship);
    final maker = LocalHangarManufacturers.of(ship);
    final summary = localHangarShipSummary(
      context,
      c,
      item,
      instanceIndex: widget.instanceIndex,
      instanceCount: widget.instanceCount,
      former: widget.former,
    );
    final other = widget.showMaker
        ? maker?.short(c) ?? LocalHangarManufacturers.unknownName(ship)
        : c.combatSize(item.sizeClass ?? ship.size);
    final lead = compact
        ? null
        : [
            if (widget.instanceCount > 1) c.instanceShort(widget.instanceIndex),
            if (name != LocalHangarNames.model(locale, ship))
              LocalHangarNames.model(locale, ship),
          ].join(' · ');
    final price = item.priceCents == null
        ? null
        : c.usd(item.priceCents! / 100);
    final base = Theme.of(context).textTheme.bodySmall;
    final nameStyle = base?.copyWith(
      fontSize: compact ? 12.5 : 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: t.colors.textPrimary,
    );
    final lineStyle = base?.copyWith(
      fontSize: compact ? 11 : 12,
      height: compact ? 1.3 : 1.35,
      color: t.colors.textSecondary,
    );
    final markHere = widget.markOnImage && !compact;
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Stack(
        children: [
          Positioned.fill(
            child: StarBridgeActionRow(
              controlKey: ValueKey('hangar-open-${ship.id}'),
              hoverFace: false,
              baseRadius: t.shape.radiusSmall,
              semanticLabel: summary,
              onActivate: (_, _) => widget.onOpen(),
              child: StarBridgeTooltip(
                message: summary,
                excludeFromSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: metrics.cellWidth,
                      height: metrics.imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LocalHangarCardImage(
                            key: ValueKey(
                              'hangar-card-image-${widget.cacheKey}',
                            ),
                            item: item,
                            width: metrics.cellWidth,
                            height: metrics.imageHeight,
                            fit: BoxFit.cover,
                            sharp: true,
                            tint: _hover
                                ? HangarWallPalette.imageDimHover
                                : palette.imageDim,
                            imagePort: widget.imagePort,
                            cache: widget.imageCache,
                            cacheKey: widget.cacheKey,
                          ),
                          if (compact && price != null)
                            const _CornerScrim(toRight: true),
                          if (markHere && maker?.logo == true)
                            const _CornerScrim(toRight: false),
                          if (compact && price != null)
                            Positioned(
                              right: 4,
                              bottom: 2,
                              child: Text(
                                price,
                                maxLines: 1,
                                style: base?.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: HangarWallPalette.onArt,
                                ),
                              ),
                            ),
                          if (markHere)
                            Positioned(
                              left: 5,
                              bottom: 4,
                              child: LocalHangarMakerMark(
                                maker: maker,
                                height: 22,
                                maxWidth: 70,
                                onArt: true,
                              ),
                            ),
                          if (_hover)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: t.colors.accent),
                                borderRadius: t.shape.small,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        LocalHangarWallIcon(
                          item: item,
                          size: compact ? 20 : 28,
                        ),
                        SizedBox(width: compact ? 4 : 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          if (item.role != 'unknown')
                                            TextSpan(
                                              text: '${c.category(item.role)} ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: palette.roleText(
                                                  shipCategoryColor(
                                                    context,
                                                    item.role,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (lead?.isNotEmpty == true)
                                            TextSpan(text: '$lead · '),
                                          TextSpan(text: other ?? ''),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: lineStyle,
                                    ),
                                  ),
                                  if (!compact && price != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      price,
                                      maxLines: 1,
                                      style: lineStyle?.copyWith(
                                        color: t.colors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _FavoriteMark(
              shipId: ship.id,
              favorite: ship.isFavorite,
              compact: compact,
              onFavorite: widget.onFavorite,
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat gradient behind text or a mark on the artwork. It paints no layer,
/// and starts from the corner so that the ship stays clear.
class _CornerScrim extends StatelessWidget {
  const _CornerScrim({required this.toRight});
  final bool toRight;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: toRight ? Alignment.bottomRight : Alignment.bottomLeft,
        end: toRight ? Alignment.topLeft : Alignment.topRight,
        stops: const [0, .3, .52],
        colors: const [
          HangarWallPalette.artScrim,
          HangarWallPalette.artScrimClear,
          HangarWallPalette.artScrimClear,
        ],
      ),
    ),
  );
}

class _FavoriteMark extends StatelessWidget {
  const _FavoriteMark({
    required this.shipId,
    required this.favorite,
    required this.compact,
    required this.onFavorite,
  });
  final String shipId;
  final bool favorite, compact;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context);
    final size = compact ? 24.0 : 28.0;
    return StarBridgeIconAction(
      controlKey: ValueKey('hangar-favorite-$shipId'),
      label: favorite ? c.unfavorite : c.favorite,
      selected: favorite,
      quiet: true,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      onActivate: onFavorite == null ? null : (_) => onFavorite!(),
      icon: DecoratedBox(
        decoration: const BoxDecoration(
          color: HangarWallPalette.markBack,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: StandardIcon(
            favorite
                ? StandardIconSemantic.bookmarked
                : StandardIconSemantic.bookmark,
            color: favorite
                ? HangarWallPalette.onArtFavorite
                : HangarWallPalette.onArt,
            size: compact ? 13 : 15,
          ),
        ),
      ),
    );
  }
}
