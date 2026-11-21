import 'local_hangar_copy.dart';
import 'local_hangar_manufacturers.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';

/// One titled run of ships on the wall. Keys are stable across rebuilds, so
/// the page can return to a section after a change of density.
final class LocalHangarWallSection {
  const LocalHangarWallSection({
    required this.key,
    required this.title,
    required this.ships,
    this.favorite = false,
    this.maker,
  });
  final String key, title;
  final List<LocalHangarShip> ships;
  final bool favorite;
  final LocalHangarManufacturer? maker;
}

abstract final class LocalHangarWallSections {
  static const _sizes = [
    'capital',
    'large',
    'medium',
    'small',
    'ground-large',
    'ground-medium',
    'ground-small',
  ];

  /// Favorites first and only there; the rest by size or by maker, biggest
  /// maker first. Same-model instances stay separate.
  static List<LocalHangarWallSection> build(
    List<LocalHangarShip> ships, {
    required bool byMaker,
    required LocalHangarCopy copy,
    required String sort,
  }) {
    final ordered = sort == 'saved' ? _byPrice(ships) : ships;
    final favorites = ordered.where((ship) => ship.isFavorite).toList();
    final rest = ordered.where((ship) => !ship.isFavorite);
    return [
      if (favorites.isNotEmpty)
        LocalHangarWallSection(
          key: 'favorites',
          title: copy.favorites,
          ships: favorites,
          favorite: true,
        ),
      ...byMaker ? _byMaker(rest, copy) : _bySize(rest, copy),
    ];
  }

  /// A wall section reads from the most valuable ship down; ties keep the
  /// saved order. An explicit sort choice replaces this.
  static List<LocalHangarShip> _byPrice(List<LocalHangarShip> ships) {
    int cents(LocalHangarShip ship) =>
        LocalHangarPresentation.fromSaved(ship).priceCents ?? -1;
    final indexed = ships.indexed.toList()
      ..sort((a, b) {
        final price = cents(b.$2).compareTo(cents(a.$2));
        return price != 0 ? price : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  static String? _size(LocalHangarShip ship) =>
      LocalHangarPresentation.fromSaved(ship).sizeClass ?? ship.size;

  static List<LocalHangarWallSection> _bySize(
    Iterable<LocalHangarShip> ships,
    LocalHangarCopy copy,
  ) {
    final groups = <String, List<LocalHangarShip>>{};
    for (final ship in ships) {
      final size = _size(ship);
      (groups[_sizes.contains(size) ? size! : 'other'] ??= []).add(ship);
    }
    return [
      for (final key in [..._sizes, 'other'])
        if (groups[key] case final group?)
          LocalHangarWallSection(
            key: 'size-$key',
            title: copy.combatSize(key) ?? copy.otherSection,
            ships: group,
          ),
    ];
  }

  static List<LocalHangarWallSection> _byMaker(
    Iterable<LocalHangarShip> ships,
    LocalHangarCopy copy,
  ) {
    final groups = <String, List<LocalHangarShip>>{};
    final makers = <String, LocalHangarManufacturer>{};
    for (final ship in ships) {
      final maker = LocalHangarManufacturers.of(ship);
      if (maker != null) makers[maker.key] = maker;
      final raw = LocalHangarManufacturers.unknownName(ship);
      final key = maker?.key ?? (raw == null ? 'other' : 'raw:$raw');
      (groups[key] ??= []).add(ship);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        // "Other" closes the wall however many ships it holds.
        if (a == 'other' || b == 'other') {
          return a == b ? 0 : (a == 'other' ? 1 : -1);
        }
        final size = groups[b]!.length.compareTo(groups[a]!.length);
        return size != 0 ? size : a.compareTo(b);
      });
    return [
      for (final key in keys)
        LocalHangarWallSection(
          key: 'maker-$key',
          title:
              makers[key]?.name(copy) ??
              (key.startsWith('raw:') ? key.substring(4) : copy.otherSection),
          ships: groups[key]!,
          maker: makers[key],
        ),
    ];
  }
}
