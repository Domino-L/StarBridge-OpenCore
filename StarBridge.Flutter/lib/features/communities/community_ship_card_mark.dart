import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../../shared/ships/ship_silhouette_store.dart';
import '../../shared/ships/ship_vehicle_icon.dart';
import '../hangar/local_hangar_manufacturers.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';

/// The maker's Fan Kit logo in the art's lower-right corner, at the end of the
/// name strip (user 11-05 option C; 11-14 "我是说图片的右下角"). The strip gives
/// the logo its own slot beside the name, so the two never overlap, and the art
/// keeps its fixed height, so the card's height never changes. The strip fades
/// into the panel colour, so the logo follows the appearance like the name.
/// Sized by height so thin word marks stay legible (user 10-29 "不要小图标").
/// Fan Kit original only: contain, no tint, outline or effect. An unknown maker
/// or an absent logo takes no space.
class CommunityShipMakerLogo extends StatefulWidget {
  const CommunityShipMakerLogo({
    required this.ship,
    this.height = 28,
    this.maxWidth = 88,
    this.gap = 8,
    super.key,
  });

  final CommunitySharedShip ship;
  final double height, maxWidth, gap;

  @override
  State<CommunityShipMakerLogo> createState() => _CommunityShipMakerLogoState();
}

class _CommunityShipMakerLogoState extends State<CommunityShipMakerLogo> {
  @override
  void initState() {
    super.initState();
    LocalHangarMakerLogos.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final maker = LocalHangarManufacturers.find(widget.ship.manufacturer);
    final dark = context.tokens.isDark;
    if (maker == null ||
        !LocalHangarMakerLogos.instance.has(maker, dark: dark)) {
      return const SizedBox.shrink();
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: widget.gap),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ConstrainedBox(
            key: ValueKey('community-ship-maker-${widget.ship.shipRef}'),
            constraints: BoxConstraints(
              maxWidth: widget.maxWidth,
              maxHeight: widget.height,
            ),
            child: Image.asset(
              LocalHangarMakerLogos.asset(maker.key, dark: dark),
              height: widget.height,
              fit: BoxFit.contain,
              alignment: AlignmentDirectional.bottomEnd,
              cacheHeight: (widget.height * ratio).ceil(),
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ship's own top-down silhouette in the card's lower-right corner, beside
/// the owner and price (user 11-05 option C). No taller than those two rows,
/// so it never changes the card's height. Ships without one fall back to the
/// reviewed catalog glyph, or nothing. Price and loaner count keep priority:
/// when large text leaves no room, the card stays as it was.
class CommunityShipSilhouetteFooter extends StatelessWidget {
  const CommunityShipSilhouetteFooter({
    required this.ship,
    required this.child,
    super.key,
  });

  static const double size = 46;

  final CommunitySharedShip ship;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final store = ShipSilhouetteStore.instance..ensureLoaded();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final names = [ship.code, ship.englishName, ship.displayName];
        final iconKey = ship.displayIcon;
        final shown =
            store.pack?.find(names) != null ||
            iconKey != null && CatalogVehicleIcon.supportsKey(iconKey);
        if (!shown) return child;
        return LayoutBuilder(
          builder: (context, available) {
            if (available.maxWidth < _priceWidth(context) + size + 8) {
              return child;
            }
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: size + 8),
                  child: child,
                ),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: SizedBox.square(
                        key: ValueKey(
                          'community-ship-silhouette-${ship.shipRef}',
                        ),
                        dimension: size,
                        child: ShipVehicleIcon(
                          names: names,
                          size: size,
                          fallback: iconKey == null
                              ? const SizedBox.shrink()
                              : CatalogVehicleIcon.byKey(
                                  iconKey: iconKey,
                                  size: size,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _priceWidth(BuildContext context) {
    double width(String value) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final measured = painter.width.ceilToDouble();
      painter.dispose();
      return measured;
    }

    final price = width(
      ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ??
          communityShipsText(context, 'unpublished'),
    );
    final count = ship.loaners?.length ?? 0;
    return price +
        (count == 0
            ? 0
            : 10 + width('${communityShipsText(context, 'loaners')} $count'));
  }
}
