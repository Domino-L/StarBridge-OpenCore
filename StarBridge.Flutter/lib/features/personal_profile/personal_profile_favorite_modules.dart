import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';

/// One selection owner per module. Ship IDs identify hangar instances; a
/// page still shows each model once (see [ProfileFavoriteModules.modelKey]).
abstract final class ProfileFavoriteModules {
  static const addAction = 'add-favorite-module';

  /// Menu row that only explains why no further favorite module can be added.
  static const limitNotice = 'favorite-module-limit';

  /// 11-06: at most three favorite-ship modules may be added. Layouts that
  /// already hold more (older clients, partitioned old selections) keep every
  /// module; they only cannot add another one.
  static const maxModules = 3;

  static String? firstVisibleId(List<PersonalProfileModuleLayoutItem> layout) =>
      PersonalProfileLayout.singleColumn(layout)
          .where(
            (item) =>
                item.isVisible &&
                PersonalProfileModuleIds.isFavorite(item.moduleId),
          )
          .firstOrNull
          ?.moduleId;

  static int count(Iterable<PersonalProfileModuleLayoutItem> layout) => layout
      .where((e) => PersonalProfileModuleIds.isFavorite(e.moduleId))
      .length;

  static bool canAdd(Iterable<PersonalProfileModuleLayoutItem> layout) =>
      count(layout) < maxModules &&
      layout.length < PersonalProfileLayout.maxModules;

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
    if (!canAdd(layout)) return layout;
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
      if (ids.contains(limitNotice)) limitNotice,
      for (final id in ids)
        if (id != addAction &&
            id != limitNotice &&
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

  /// The model a ship belongs to, by the hangar's own rule
  /// (LocalHangarShip.modelKey): the catalog ID, else the normalized English
  /// name. User 11-07: "不能重复，即使该用户有两艘一样的船也不行" — a page
  /// shows each model once, across modules, within a module and in 4th slots.
  static String modelKey(PersonalProfileShipIdentity ship) {
    final catalog = ship.catalogId?.trim() ?? '';
    return catalog.isNotEmpty
        ? 'catalog:${catalog.toLowerCase()}'
        : 'name:${ship.englishName.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';
  }

  /// Ship ID → model key. An ID without a known ship is its own key.
  static Map<String, String> modelsOf(
    Iterable<PersonalProfileShipSummary> ships,
  ) => {
    for (final ship in ships) ship.identity.runtimeId: modelKey(ship.identity),
  };

  static String _model(Map<String, String> models, String id) =>
      models[id] ?? id;

  /// The ships to show: each model's first ship in layout order (a module's
  /// ships, then its 4th). Later repeats, saved by an older client, are only
  /// hidden; the saved page keeps them until the user next saves the layout.
  static List<PersonalProfileModuleLayoutItem> firstOfEachModel(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    Map<String, String> models,
  ) {
    final seen = <String>{};
    List<String>? keep(List<String>? ids) => ids == null
        ? null
        : List.unmodifiable(ids.where((id) => seen.add(_model(models, id))));
    return [
      for (final item in layout)
        if (item.favoriteShipIds == null && item.showcaseExtra == null)
          item
        else
          PersonalProfileModuleLayoutItem(
            moduleId: item.moduleId,
            size: item.size,
            isVisible: item.isVisible,
            position: item.position,
            favoriteShipIds: keep(item.favoriteShipIds),
            showcaseExtra: keep(item.showcaseExtra),
          ),
    ];
  }

  /// A profile read's layout and favourite list, each model once. A visitor's
  /// grid finds ships only in [ships], so on a per-module page the list keeps
  /// exactly the ships the layout still shows (CX-FAV-MODEL-DEDUPE-073: the
  /// flat list puts 4th ships last, the layout right after their module).
  static ({
    List<PersonalProfileModuleLayoutItem> layout,
    List<PersonalProfileShipSummary> ships,
  })
  shownFavorites(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    List<PersonalProfileShipSummary> ships,
    PersonalProfileShipIdentity? Function(String id) lookup,
  ) {
    final models = <String, String>{
      for (final item in layout)
        for (final id in [...?item.favoriteShipIds, ...?item.showcaseExtra])
          if (lookup(id) case final ship?) id: modelKey(ship),
    };
    final shown = firstOfEachModel(layout, models);
    if (!shown.any((e) => e.favoriteShipIds != null)) {
      return (layout: shown, ships: firstShipOfEachModel(ships));
    }
    final ids = {
      for (final item in shown)
        for (final id in [...?item.favoriteShipIds, ...?item.showcaseExtra])
          id.toLowerCase(),
    };
    return (
      layout: shown,
      ships: [
        for (final ship in ships)
          if (ids.contains(ship.identity.runtimeId.toLowerCase())) ship,
      ],
    );
  }

  /// A flat favourite list (pages without per-module picks), first of each model.
  static List<PersonalProfileShipSummary> firstShipOfEachModel(
    Iterable<PersonalProfileShipSummary> ships,
  ) {
    final seen = <String>{};
    return [
      for (final ship in ships)
        if (seen.add(modelKey(ship.identity))) ship,
    ];
  }

  /// The models other modules hold (ships and 4th slots).
  static Set<String> reserved(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    String except, {
    Map<String, String> models = const {},
  }) => {
    for (final item in layout)
      if (item.moduleId != except)
        for (final id in [...?item.favoriteShipIds, ...?item.showcaseExtra])
          _model(models, id),
  };

  static bool valid(
    Iterable<PersonalProfileModuleLayoutItem> layout, {
    Map<String, String> models = const {},
  }) {
    final used = <String>{};
    for (final item in layout) {
      final ids = item.favoriteShipIds;
      if (ids == null) continue;
      if (!PersonalProfileModuleIds.isFavorite(item.moduleId) ||
          ids.length > item.size.span) {
        return false;
      }
      for (final id in [...ids, ...?item.showcaseExtra]) {
        if (!used.add(_model(models, id))) return false;
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
