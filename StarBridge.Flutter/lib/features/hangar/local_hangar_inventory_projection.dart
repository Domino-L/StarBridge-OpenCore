import 'local_hangar_copy.dart';
import 'local_hangar_names.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';

/// One presentation of the selected current/history inventory. It never changes
/// instances, persistence or account ownership; filters only choose visible rows.
class LocalHangarInventoryProjection {
  LocalHangarInventoryProjection({
    required this.source,
    required LocalHangarCopy copy,
    required String query,
    required bool favoritesOnly,
    required String? category,
    required String? size,
    required String? status,
    required String sort,
  }) {
    ships = source
        .where(
          (ship) =>
              LocalHangarNames.matches(ship, query) &&
              (!favoritesOnly || ship.isFavorite) &&
              (category == null ||
                  LocalHangarPresentation.fromSaved(ship).role == category) &&
              (size == null ||
                  (LocalHangarPresentation.fromSaved(ship).sizeClass ??
                          ship.size) ==
                      size) &&
              (status == null ||
                  LocalHangarPresentation.fromSaved(ship).status == status),
        )
        .toList();
    if (sort != 'saved') {
      ships.sort((a, b) {
        final comparison = switch (sort) {
          'name' => LocalHangarNames.primary(
            copy.locale,
            a,
          ).compareTo(LocalHangarNames.primary(copy.locale, b)),
          'added' => (b.addedAt ?? DateTime(1970)).compareTo(
            a.addedAt ?? DateTime(1970),
          ),
          'value' =>
            (LocalHangarPresentation.fromSaved(b).priceCents ?? -1).compareTo(
              LocalHangarPresentation.fromSaved(a).priceCents ?? -1,
            ),
          _ => 0,
        };
        return comparison != 0 ? comparison : a.id.compareTo(b.id);
      });
    }
    roles = source
        .map((s) => LocalHangarPresentation.fromSaved(s).role)
        .toSet();
    sizes = source
        .map((s) => LocalHangarPresentation.fromSaved(s).sizeClass ?? s.size)
        .whereType<String>()
        .where((size) => copy.combatSize(size) != null)
        .toSet();
  }
  final List<LocalHangarShip> source;
  late final List<LocalHangarShip> ships;
  late final Set<String> roles, sizes;

  /// Numbering always uses the full selected inventory, never filtered results.
  List<LocalHangarShip> peers(LocalHangarShip ship) =>
      source.where((candidate) => candidate.modelKey == ship.modelKey).toList();
}
