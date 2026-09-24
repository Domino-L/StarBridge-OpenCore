import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';

/// One selection owner per module. Ship IDs identify hangar instances, not models.
abstract final class ProfileFavoriteModules {
  static const addAction = 'add-favorite-module';

  static String nextId(Iterable<PersonalProfileModuleLayoutItem> source) {
    final ids = source.map((e) => e.moduleId).toSet();
    var index = 1;
    while (ids.contains('favorite-ships-$index')) {
      index++;
    }
    return 'favorite-ships-$index';
  }

  /// Projects older local selections without writing or truncating them.
  /// Extra entries get their own modules when the user next saves the page.
  static List<PersonalProfileModuleLayoutItem> materialize(
    Iterable<PersonalProfileModuleLayoutItem> source,
    List<String>? legacyIds,
  ) {
    final layout = PersonalProfileLayout.normalize(source);
    if (legacyIds == null || layout.any((e) => e.favoriteShipIds != null)) {
      return layout;
    }
    final first = layout.indexWhere(
      (e) => e.moduleId == PersonalProfileModuleIds.favoriteShips,
    );
    final original = layout[first];
    final remaining = legacyIds.toList();
    final count = remaining.length.clamp(0, original.size.span);
    layout[first] = original.copyWith(
      favoriteShipIds: List.unmodifiable(remaining.take(count)),
    );
    remaining.removeRange(0, count);
    while (remaining.isNotEmpty) {
      final take = remaining.length.clamp(1, 3);
      layout.add(
        PersonalProfileModuleLayoutItem(
          moduleId: nextId(layout),
          size: PersonalProfileModuleSize.values[take - 1],
          isVisible: original.isVisible,
          position: original.isVisible ? _nextRow(layout) : -1,
          favoriteShipIds: List.unmodifiable(remaining.take(take)),
        ),
      );
      remaining.removeRange(0, take);
    }
    return PersonalProfileLayout.normalize(layout);
  }

  static List<PersonalProfileModuleLayoutItem> add(
    Iterable<PersonalProfileModuleLayoutItem> source,
  ) {
    final layout = PersonalProfileLayout.normalize(source);
    // One repeatable menu item also restores hidden selections, rather than
    // making their ships permanently reserved by an unreachable module.
    for (final item in layout) {
      if (!item.isVisible &&
          PersonalProfileModuleIds.isFavorite(item.moduleId)) {
        return PersonalProfileLayout.show(layout, item.moduleId).layout;
      }
    }
    if (layout.length >= PersonalProfileLayout.maxModules) return layout;
    return PersonalProfileLayout.normalize([
      ...layout,
      PersonalProfileModuleLayoutItem(
        moduleId: nextId(layout),
        size: PersonalProfileModuleSize.three,
        isVisible: true,
        position: -1,
        favoriteShipIds: const [],
      ),
    ]);
  }

  static List<String> addMenuItems(Iterable<String> hiddenIds) {
    final ids = hiddenIds.toList();
    final repeatable = ids.contains(addAction);
    return [
      if (repeatable) addAction,
      for (final id in ids)
        if (id != addAction &&
            (!repeatable || !PersonalProfileModuleIds.isFavorite(id)))
          id,
    ];
  }

  static int _nextRow(List<PersonalProfileModuleLayoutItem> layout) {
    final end = layout
        .where((e) => e.isVisible)
        .fold<int>(
          0,
          (n, e) => n > e.position + e.size.span ? n : e.position + e.size.span,
        );
    return (end + 2) ~/ 3 * 3;
  }

  static Set<String> reserved(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    String except,
  ) => {
    for (final item in layout)
      if (item.moduleId != except) ...?item.favoriteShipIds,
  };

  static bool valid(Iterable<PersonalProfileModuleLayoutItem> layout) {
    final used = <String>{};
    for (final item in layout) {
      final ids = item.favoriteShipIds;
      if (ids == null) continue;
      if (!PersonalProfileModuleIds.isFavorite(item.moduleId) ||
          ids.length > item.size.span) {
        return false;
      }
      for (final id in ids) {
        if (!used.add(id)) return false;
      }
    }
    return true;
  }

  static List<String>? selections(
    Iterable<PersonalProfileModuleLayoutItem> layout,
  ) {
    if (!layout.any((e) => e.favoriteShipIds != null)) return null;
    return [for (final item in layout) ...?item.favoriteShipIds];
  }
}
