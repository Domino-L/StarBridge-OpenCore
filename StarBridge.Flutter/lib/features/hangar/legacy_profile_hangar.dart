import 'local_hangar_port.dart';
import '../../shared/ships/ship_reviewed_display.dart';

/// Read-only S2 display projection. These IDs are not confirmed local inventory
/// identities and are never submitted as an RSI scan or inventory save.
LocalHangarShip profileHangarShip(Map value, String id) {
  final p = value['presentation'] as Map? ?? const {};
  final title = (p['title'] ?? value['displayName'] ?? value['code']) as String;
  if (title.isEmpty) throw const LocalHangarFailure('hangar.invalid_inventory');
  return LocalHangarShip(
    id: id,
    title: title,
    catalogId: p['catalogId'] as String?,
    cn: p['cn'] as String?,
    tw: p['tw'] as String?,
    category: p['category'] as String? ?? value['roleCategory'] as String?,
    sizeClass: p['sizeClass'] as String?,
    deliveryStatus: p['deliveryStatus'] as String?,
    priceUsd: p['priceUsd'] as num?,
    imageAsset: p['imageAsset'] as String?,
    thumbnailAsset: p['thumbnailAsset'] as String?,
    display: ShipReviewedDisplay.parse(p['display']),
    addedAt: DateTime.tryParse(value['importedAt'] as String? ?? ''),
  );
}

/// A profile may omit its optional hangar display (also when the owner hides
/// those profile modules). Absence says nothing about inventory saved elsewhere.
LocalHangarSnapshot? legacyProfileHangar(Map<String, Object?> payload) {
  final profile = payload['profile'];
  if (profile is! Map) {
    throw const LocalHangarFailure('hangar.legacy_unavailable');
  }
  final hangar = profile['hangar'];
  if (hangar == null) return null;
  if (hangar is! Map) {
    throw const LocalHangarFailure('hangar.legacy_unavailable');
  }
  final rows = hangar['ships'];
  if (rows is! List || rows.length > 20000) {
    throw const LocalHangarFailure('hangar.legacy_unavailable');
  }
  return LocalHangarSnapshot(
    revision: 0,
    fromLegacyProfile: true,
    ships: List.unmodifiable([
      for (var i = 0; i < rows.length; i++)
        if ((rows[i] as Map)['isInventoryEntry'] != false)
          profileHangarShip(rows[i] as Map, 'legacy-display-$i'),
    ]),
  );
}
