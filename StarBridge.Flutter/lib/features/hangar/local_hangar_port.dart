import '../../shared/ships/ship_reviewed_display.dart';

class LocalHangarShip {
  const LocalHangarShip({
    required this.id,
    required this.title,
    this.liner,
    this.cn,
    this.tw,
    this.size,
    this.addedAt,
    this.removedAt,
    this.catalogId,
    this.category,
    this.sizeClass,
    this.deliveryStatus,
    this.priceUsd,
    this.imageAsset,
    this.thumbnailAsset,
    this.display,
  });
  final String id, title;
  final String? liner, cn, tw, size;
  final DateTime? addedAt;
  final DateTime? removedAt;
  String get modelKey => catalogId?.trim().isNotEmpty == true
      ? 'catalog:${catalogId!.trim().toLowerCase()}'
      : 'name:${title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';
  // Optional display facts from the same catalog, not persisted ownership.
  final String? catalogId, category, sizeClass, deliveryStatus, imageAsset;
  final String? thumbnailAsset;
  final num? priceUsd;
  final ShipReviewedDisplay? display;
}

class LocalHangarSnapshot {
  const LocalHangarSnapshot({
    required this.revision,
    required this.ships,
    this.savedAt,
    this.operationId,
    this.partial = false,
    this.fromLegacyProfile = false,
    this.formerShips = const [],
  });
  final int revision;
  final List<LocalHangarShip> ships;
  final List<LocalHangarShip> formerShips;
  final DateTime? savedAt;
  final String? operationId;
  final bool partial;
  final bool fromLegacyProfile;

  /// Display history is model-based; current inventory remains instance-based.
  /// Keep raw IDs separately so existing favorites remain resolvable.
  List<LocalHangarShip> get formerModels {
    final owned = ships.map((s) => s.modelKey).toSet();
    final byModel = <String, LocalHangarShip>{};
    for (final ship in formerShips) {
      if (owned.contains(ship.modelKey)) continue;
      final previous = byModel[ship.modelKey];
      if (previous == null ||
          (ship.removedAt ?? ship.addedAt ?? DateTime(1970)).isAfter(
            previous.removedAt ?? previous.addedAt ?? DateTime(1970),
          )) {
        byModel[ship.modelKey] = ship;
      }
    }
    return byModel.values.toList()..sort(
      (a, b) => (b.removedAt ?? DateTime(1970)).compareTo(
        a.removedAt ?? DateTime(1970),
      ),
    );
  }
}

class LocalHangarFailure implements Exception {
  const LocalHangarFailure(this.code);
  final String code;
}

/// The current authenticated owner's local inventory. No identity or ship list
/// is accepted from the caller when saving; the Host retains the verified scan.
abstract interface class LocalHangarPort {
  Future<LocalHangarSnapshot> read();
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  });
}
