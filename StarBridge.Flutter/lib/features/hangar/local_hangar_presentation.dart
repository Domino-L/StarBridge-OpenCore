import 'local_hangar_port.dart';
import '../../shared/ships/ship_catalog_display.dart';

/// Read-only display metadata. It never changes the saved scan or ownership.
class LocalHangarPresentation {
  const LocalHangarPresentation({
    required this.ship,
    this.catalogId,
    this.category,
    this.sizeClass,
    this.deliveryStatus,
    this.priceUsd,
    this.imageAsset,
  });

  factory LocalHangarPresentation.fromSaved(LocalHangarShip ship) =>
      LocalHangarPresentation(
        ship: ship,
        catalogId: ship.catalogId,
        category: ship.display?.role ?? ship.category,
        sizeClass: ship.display?.spec ?? ship.sizeClass,
        deliveryStatus: ship.deliveryStatus,
        priceUsd: ship.priceUsd,
        imageAsset: ship.imageAsset,
      );

  final LocalHangarShip ship;
  final String? catalogId, category, sizeClass, deliveryStatus, imageAsset;
  final num? priceUsd;

  static const categories = ShipCatalogDisplay.categories;
  String get role => categories.contains(category) ? category! : 'unknown';
  String get status => const ['flyable', 'concept'].contains(deliveryStatus)
      ? deliveryStatus!
      : 'unknown';

  // Integer cents avoid floating point drift when adding multiple instances.
  int? get priceCents {
    return ShipCatalogDisplay.cents(priceUsd);
  }

  String? get bundledImage {
    return ShipCatalogDisplay.image(imageAsset);
  }
}

class LocalHangarTotals {
  LocalHangarTotals(Iterable<LocalHangarPresentation> ships) {
    for (final item in ships) {
      count++;
      roles.update(item.role, (n) => n + 1, ifAbsent: () => 1);
      statuses.update(item.status, (n) => n + 1, ifAbsent: () => 1);
      final cents = item.priceCents;
      if (cents != null) {
        knownValueCents += cents;
        pricedCount++;
      }
    }
  }

  int count = 0, pricedCount = 0, knownValueCents = 0;
  final roles = <String, int>{};
  final statuses = <String, int>{};
  int get unpricedCount => count - pricedCount;
  num get knownValueUsd => knownValueCents / 100;
}
