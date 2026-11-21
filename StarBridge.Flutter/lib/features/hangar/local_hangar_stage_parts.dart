import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/styles/hangar_wall_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'local_hangar_card_image.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_manufacturers.dart';
import 'local_hangar_names.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_wall_card.dart';

class LocalHangarStageTopBar extends StatelessWidget {
  const LocalHangarStageTopBar({
    required this.ship,
    required this.position,
    required this.onBack,
    required this.onFavorite,
    required this.favoritesAvailable,
    required this.favoriteBusy,
    required this.favoriteFailed,
    super.key,
  });
  final LocalHangarShip ship;
  final String position;
  final VoidCallback onBack;
  final ValueChanged<LocalHangarShip>? onFavorite;
  final bool favoritesAvailable, favoriteBusy, favoriteFailed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, 0),
      child: LayoutBuilder(
        builder: (context, bounds) => _bar(
          context,
          // A narrow bar keeps the icons and says the words to readers only.
          words:
              bounds.maxWidth >=
              520 * MediaQuery.textScalerOf(context).scale(14) / 14,
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, {required bool words}) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        _shareOfBar(
          child: _ArtAction(
            controlKey: const Key('hangar-stage-back'),
            onTap: onBack,
            showLabel: words,
            icon: const StandardIcon(
              StandardIconSemantic.chevronLeft,
              color: HangarWallPalette.onArt,
              size: 20,
            ),
            label: c.backToWall,
          ),
        ),
        SizedBox(width: t.space.md),
        Expanded(
          child: Text(
            position,
            key: const Key('hangar-stage-position'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(
              color: HangarWallPalette.onArtFaint,
            ),
          ),
        ),
        if (favoriteBusy || favoriteFailed)
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  favoriteFailed ? c.favoriteFailure : c.updatingFavorite,
                  key: const Key('hangar-stage-favorite-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.bodySmall?.copyWith(
                    color: favoriteFailed
                        ? HangarWallPalette.onArtFavorite
                        : HangarWallPalette.onArtFaint,
                  ),
                ),
              ),
            ),
          ),
        if (favoritesAvailable)
          _shareOfBar(
            child: _ArtAction(
              controlKey: const Key('hangar-stage-favorite'),
              onTap: onFavorite == null ? null : () => onFavorite!(ship),
              showLabel: words,
              color: ship.isFavorite
                  ? HangarWallPalette.onArtFavorite
                  : HangarWallPalette.onArt,
              icon: StandardIcon(
                ship.isFavorite
                    ? StandardIconSemantic.bookmarked
                    : StandardIconSemantic.bookmark,
                color: ship.isFavorite
                    ? HangarWallPalette.onArtFavorite
                    : HangarWallPalette.onArt,
                size: 16,
              ),
              label: ship.isFavorite ? c.bookmarked : c.favorite,
            ),
          ),
      ],
    );
  }
}

/// Keeps a control at its own width, never more than a third of the bar, so
/// the words between take the rest instead of a fixed share.
Widget _shareOfBar({required Widget child}) => Builder(
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width / 3),
    // A pressable fills what it is given; this keeps it to its own content.
    child: IntrinsicWidth(child: child),
  ),
);

/// Words over the artwork, light in both appearances.
class _ArtAction extends StatelessWidget {
  const _ArtAction({
    required this.controlKey,
    required this.onTap,
    required this.icon,
    required this.label,
    this.showLabel = true,
    this.color = HangarWallPalette.onArt,
  });
  final Key controlKey;
  final VoidCallback? onTap;
  final Widget icon;
  final String label;
  final bool showLabel;
  final Color color;

  @override
  Widget build(BuildContext context) => StarBridgeActionRow(
    controlKey: controlKey,
    semanticLabel: label,
    baseRadius: context.tokens.shape.radiusSmall,
    onActivate: onTap == null ? null : (_, _) => onTap!(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          if (showLabel) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class LocalHangarStageArrow extends StatelessWidget {
  const LocalHangarStageArrow({
    required this.controlKey,
    required this.label,
    required this.back,
    required this.onTap,
    super.key,
  });
  final Key controlKey;
  final String label;
  final bool back;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: StarBridgeIconAction(
      controlKey: controlKey,
      label: label,
      quiet: true,
      constraints: const BoxConstraints.tightFor(width: 44, height: 70),
      padding: EdgeInsets.zero,
      onActivate: onTap == null ? null : (_) => onTap!(),
      icon: StandardIcon(
        back
            ? StandardIconSemantic.chevronLeft
            : StandardIconSemantic.chevronRight,
        color: HangarWallPalette.onArt,
        size: 30,
      ),
    ),
  );
}

class LocalHangarStageFacts extends StatelessWidget {
  const LocalHangarStageFacts({
    required this.item,
    required this.former,
    required this.peers,
    required this.narrow,
    required this.detailsFocus,
    required this.onDetails,
    super.key,
  });
  final LocalHangarPresentation item;
  final bool former, narrow;
  final List<LocalHangarShip> peers;
  final FocusNode detailsFocus;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final palette = HangarWallPalette.of(context);
    final theme = Theme.of(context).textTheme;
    final ship = item.ship, locale = Localizations.localeOf(context);
    final name = LocalHangarNames.primary(locale, ship);
    final model = LocalHangarNames.model(locale, ship);
    final maker = LocalHangarManufacturers.of(ship);
    final index = peers.indexWhere((s) => s.id == ship.id) + 1;
    final origin = [
      if (name != model) model,
      if (ship.title != name && ship.title != model) ship.title,
      maker?.name(c) ?? LocalHangarManufacturers.unknownName(ship),
      if (LocalHangarManufacturers.find(ship.liner) == null) ship.liner,
      if (peers.length > 1) c.instance(index, peers.length),
    ].whereType<String>().join(' · ');
    final value = theme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final size = c.combatSize(item.sizeClass ?? ship.size);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (origin.isNotEmpty)
          Text(
            origin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodyMedium?.copyWith(color: t.colors.textSecondary),
          ),
        Text(
          name,
          key: const Key('hangar-stage-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.titleLarge?.copyWith(
            fontSize: narrow ? 30 : 54,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        SizedBox(height: narrow ? 4 : 10),
        Wrap(
          spacing: narrow ? 18 : 32,
          runSpacing: 6,
          children: [
            if (item.role != 'unknown')
              _Fact(
                label: c.roleFact,
                value: c.category(item.role),
                style: value?.copyWith(
                  color: palette.roleText(
                    shipCategoryColor(context, item.role),
                  ),
                ),
              ),
            if (size != null)
              _Fact(label: c.sizeLabel, value: size, style: value),
            if (item.priceCents != null)
              StarBridgeTooltip(
                message: c.priceBasis,
                child: _Fact(
                  label: c.priceLabel,
                  value: '${c.usd(item.priceCents! / 100)} USD',
                  style: value,
                ),
              ),
            if (item.status != 'unknown')
              _Fact(
                label: c.officialStatus,
                value: c.status(item.status),
                style: value,
              ),
            if (ship.acquiredOn != null)
              _Fact(
                label: c.acquiredOn,
                value: MaterialLocalizations.of(context)
                    .formatCompactDate(ship.acquiredOn!),
                style: value,
              ),
            if (former && ship.removedAt != null)
              _Fact(
                label: c.removedAt,
                value: MaterialLocalizations.of(context)
                    .formatCompactDate(ship.removedAt!.toLocal()),
                style: value,
              ),
          ],
        ),
      ],
    );
    final actions = [
      LocalHangarMakerMark(
        maker: maker,
        height: narrow ? 36 : 52,
        maxWidth: 150,
      ),
      LocalHangarWallIcon(item: item, size: narrow ? 52 : 76),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StarBridgeActionButton(
            controlKey: const Key('hangar-stage-details'),
            focusNode: detailsFocus,
            onActivate: (_) => onDetails(),
            child: Text(c.viewDetails),
          ),
          const SizedBox(height: 6),
          const LocalHangarNotice(),
        ],
      ),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (bounds.maxWidth < 760 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                identity,
                const SizedBox(height: 6),
                Wrap(
                  spacing: t.space.md,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: identity),
              for (final action in actions) ...[
                SizedBox(width: t.space.md),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.style});
  final String label, value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.tokens.colors.textSecondary),
      ),
      Text(value, maxLines: 1, style: style),
    ],
  );
}

class LocalHangarStageThumb extends StatelessWidget {
  const LocalHangarStageThumb({
    required this.item,
    required this.width,
    required this.selected,
    required this.line,
    required this.imagePort,
    required this.cache,
    required this.cacheKey,
    required this.onTap,
    super.key,
  });
  final LocalHangarPresentation item;
  final double width;
  final bool selected;
  final Color line;
  final LocalHangarImagePort? imagePort;
  final LocalHangarImageCache cache;
  final String cacheKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final palette = HangarWallPalette.of(context);
    final theme = Theme.of(context).textTheme;
    final ship = item.ship;
    final name = LocalHangarNames.primary(
      Localizations.localeOf(context),
      ship,
    );
    final imageHeight = width * localHangarArtAspect;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: StarBridgeActionRow(
          controlKey: ValueKey('hangar-stage-select-${ship.id}'),
          hoverFace: false,
          baseRadius: t.shape.radiusSmall,
          semanticLabel: name,
          semanticSelected: selected,
          onActivate: (_, _) => onTap(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: imageHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LocalHangarCardImage(
                      key: ValueKey('hangar-stage-thumb-image:$cacheKey'),
                      item: item,
                      width: width,
                      height: imageHeight,
                      fit: BoxFit.cover,
                      sharp: true,
                      tint: selected ? null : palette.imageDim,
                      imagePort: imagePort,
                      cache: cache,
                      cacheKey: cacheKey,
                    ),
                    if (selected)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: line),
                          borderRadius: t.shape.small,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodySmall?.copyWith(
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? t.colors.textPrimary
                      : t.colors.textSecondary,
                ),
              ),
              Row(
                children: [
                  if (item.role != 'unknown')
                    Flexible(
                      child: Text(
                        c.category(item.role),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          height: 1.3,
                          color: palette.roleText(
                            shipCategoryColor(context, item.role),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  const Spacer(),
                  if (item.priceCents != null)
                    Text(
                      c.usd(item.priceCents! / 100),
                      maxLines: 1,
                      style: theme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.3,
                        color: t.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
