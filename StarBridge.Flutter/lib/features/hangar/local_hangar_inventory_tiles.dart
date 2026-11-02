import 'package:flutter/material.dart';

import 'local_hangar_copy.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_inventory_projection.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_card.dart';
import 'local_hangar_ship_row.dart';

/// Grid/list presentation of the same inventory instances and image cache.
/// Actions remain with the page, which owns authentication and write lifetimes.
class LocalHangarInventoryTiles extends StatelessWidget {
  const LocalHangarInventoryTiles({
    required this.inventory,
    required this.grid,
    required this.former,
    required this.images,
    required this.revision,
    required this.ownerGeneration,
    required this.imageGeneration,
    required this.imageCache,
    required this.elapsed,
    required this.onOpen,
    required this.onFavorite,
    super.key,
  });
  final LocalHangarInventoryProjection inventory;
  final bool grid, former;
  final LocalHangarImageProvider? images;
  final int revision, ownerGeneration, imageGeneration;
  final LocalHangarImageCache imageCache;
  final Duration Function(LocalHangarShip) elapsed;
  final ValueChanged<LocalHangarShip> onOpen;
  final ValueChanged<LocalHangarShip>? onFavorite;

  LocalHangarImagePort? _image(LocalHangarShip ship) =>
      images?.imageFor(ship.id, revision);

  Widget _row(BuildContext context, LocalHangarShip ship) {
    final peers = inventory.peers(ship);
    final row = LocalHangarShipRow(
      key: ValueKey('local-hangar-ship-${ship.id}'),
      item: LocalHangarPresentation.fromSaved(ship),
      elapsed: elapsed(ship),
      onTap: () => onOpen(ship),
      showFavorite: true,
      imageCache: imageCache,
      imageCacheKey: '$ownerGeneration:${ship.id}:$imageGeneration',
      imagePort: _image(ship),
      instanceIndex: peers.indexWhere((s) => s.id == ship.id) + 1,
      instanceCount: peers.length,
      onFavorite: onFavorite == null ? null : () => onFavorite!(ship),
    );
    if (!former || ship.removedAt == null) return row;
    final c = LocalHangarCopy(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${c.removedAt} · ${c.dateTime(context, ship.removedAt!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ships = inventory.ships;
    if (!grid) {
      return SliverList.separated(
        itemCount: ships.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) => _row(context, ships[index]),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / 250).floor().clamp(1, 6);
        final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
        return SliverGrid.builder(
          itemCount: ships.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 310 + (scaled - 1).clamp(0, 3) * 170,
          ),
          itemBuilder: (context, index) {
            final ship = ships[index], peers = inventory.peers(ships[index]);
            return LocalHangarShipCard(
              key: ValueKey('local-hangar-ship-${ship.id}'),
              item: LocalHangarPresentation.fromSaved(ship),
              elapsed: elapsed(ship),
              sameModel: peers.length > 1,
              instanceIndex: peers.indexWhere((s) => s.id == ship.id) + 1,
              instanceCount: peers.length,
              imageCache: imageCache,
              ownerGeneration: ownerGeneration,
              imageRevision: imageGeneration,
              imagePort: _image(ship),
              onTap: () => onOpen(ship),
              onFavorite: onFavorite == null ? null : () => onFavorite!(ship),
            );
          },
        );
      },
    );
  }
}
