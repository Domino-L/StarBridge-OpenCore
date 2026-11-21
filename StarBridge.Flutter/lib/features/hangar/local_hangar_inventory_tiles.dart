import 'package:flutter/material.dart';

import 'local_hangar_copy.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_inventory_projection.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_row.dart';
import 'local_hangar_wall_card.dart';
import 'local_hangar_wall_sections.dart';

/// Card and list row of the same inventory instances and image cache. Actions
/// remain with the page, which owns authentication and write lifetimes.
class LocalHangarInventoryTiles {
  const LocalHangarInventoryTiles({
    required this.inventory,
    required this.former,
    required this.byMaker,
    required this.images,
    required this.revision,
    required this.ownerGeneration,
    required this.imageGeneration,
    required this.imageCache,
    required this.elapsed,
    required this.onOpen,
    required this.onFavorite,
  });
  final LocalHangarInventoryProjection inventory;
  final bool former, byMaker;
  final LocalHangarImageProvider? images;
  final int revision, ownerGeneration, imageGeneration;
  final LocalHangarImageCache imageCache;
  final Duration Function(LocalHangarShip) elapsed;
  final ValueChanged<LocalHangarShip> onOpen;
  final ValueChanged<LocalHangarShip>? onFavorite;

  LocalHangarImagePort? image(LocalHangarShip ship) =>
      images?.imageFor(ship.id, revision);

  String cacheKey(LocalHangarShip ship) =>
      '$ownerGeneration:${ship.id}:$imageGeneration';

  Widget row(BuildContext context, LocalHangarShip ship) {
    final peers = inventory.peers(ship);
    final row = LocalHangarShipRow(
      key: ValueKey('local-hangar-ship-${ship.id}'),
      item: LocalHangarPresentation.fromSaved(ship),
      elapsed: elapsed(ship),
      onTap: () => onOpen(ship),
      showFavorite: true,
      imageCache: imageCache,
      imageCacheKey: cacheKey(ship),
      imagePort: image(ship),
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

  Widget card(
    BuildContext context,
    LocalHangarWallSection section,
    LocalHangarShip ship,
    LocalHangarWallMetrics metrics,
  ) {
    final peers = inventory.peers(ship);
    return LocalHangarWallCard(
      key: ValueKey('local-hangar-ship-${ship.id}'),
      item: LocalHangarPresentation.fromSaved(ship),
      metrics: metrics,
      showMaker: !byMaker,
      markOnImage: !byMaker,
      former: former,
      instanceIndex: peers.indexWhere((s) => s.id == ship.id) + 1,
      instanceCount: peers.length,
      cacheKey: cacheKey(ship),
      imageCache: imageCache,
      imagePort: image(ship),
      onOpen: () => onOpen(ship),
      onFavorite: onFavorite == null ? null : () => onFavorite!(ship),
    );
  }
}
