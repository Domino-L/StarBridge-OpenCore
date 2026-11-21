import 'personal_profile_models.dart';
import 'personal_profile_public_header.dart';

/// Showcases that exist only in the single column (2026-11-02). They live in
/// the page's own `showcases` list, never in `modules`: released clients
/// reject a page whose `modules` carry an id they do not know.
abstract final class PersonalProfileShowcaseIds {
  static const achievements = 'achievements';

  /// User 11-11: playtime moved to the top of the side rail. The retired
  /// showcase is not a known id any more; a saved list holding it is read
  /// without it, as with the organizations below.
  static const gameplayTime = 'gameplay-time';
  static const tradeCard = 'trade-card';

  /// User 11-08: "我觉得组织不应该单独一个展柜，默认右侧显示就行了". The
  /// retired organization showcase is not a known id any more: a saved list
  /// that still holds it is read without it, and the side rail always shows
  /// the organizations.
  static const all = [achievements, tradeCard];

  /// Shown when the owner never saved a showcase list: the data was on the
  /// page before. Achievements start hidden.
  static const visibleByDefault = {tradeCard};

  static bool isShowcaseOnly(String id) => all.contains(id);
}

/// One entry of the stored `showcases` list: order and the on/off switch.
final class PersonalProfileShowcaseEntry {
  const PersonalProfileShowcaseEntry(this.id, {required this.isVisible});
  final String id;
  final bool isVisible;
}

abstract final class PersonalProfileShowcases {
  static const maximum = 64;
  static const maximumAchievements = 9;
  static final _achievementId = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

  static bool isKnownId(String id) =>
      PersonalProfileModuleIds.isFavorite(id) ||
      id == PersonalProfileModuleIds.hangarSummary ||
      id == PersonalProfileModuleIds.skilledRoles ||
      PersonalProfileShowcaseIds.isShowcaseOnly(id);

  /// Parses `content.showcases`. Null when the owner never saved one.
  static List<PersonalProfileShowcaseEntry>? parse(Object? raw) {
    if (raw is! List) return null;
    final seen = <String>{};
    return [
      for (final item in raw.take(maximum))
        if (item is Map &&
            item['id'] is String &&
            item['isVisible'] is bool &&
            isKnownId(item['id'] as String) &&
            seen.add(item['id'] as String))
          PersonalProfileShowcaseEntry(
            item['id'] as String,
            isVisible: item['isVisible'] as bool,
          ),
    ];
  }

  /// Parses `content.achievementShowcase`. Null when never saved.
  static List<String>? parseAchievements(Object? raw) {
    if (raw is! List) return null;
    final seen = <String>{};
    return [
      for (final id in raw)
        if (id is String && _achievementId.hasMatch(id) && seen.add(id)) id,
    ].take(maximumAchievements).toList(growable: false);
  }

  /// Folds the stored list into the module layout: showcase-only entries
  /// become layout items, and the stored order places every visible item.
  /// Module visibility stays with `modules`, which older clients also edit.
  static List<PersonalProfileModuleLayoutItem> merge(
    List<PersonalProfileModuleLayoutItem> modules,
    List<PersonalProfileShowcaseEntry>? showcases,
  ) {
    if (showcases == null) return modules;
    final byId = {for (final item in modules) item.moduleId: item};
    final ordered = <PersonalProfileModuleLayoutItem>[];
    for (final entry in showcases) {
      final module = byId.remove(entry.id);
      if (module != null) {
        ordered.add(module);
      } else if (PersonalProfileShowcaseIds.isShowcaseOnly(entry.id)) {
        ordered.add(
          PersonalProfileModuleLayoutItem(
            moduleId: entry.id,
            size: PersonalProfileModuleSize.three,
            isVisible: entry.isVisible,
            position: 0,
          ),
        );
      }
    }
    // Modules an older client added after the list was saved go last.
    final rest = byId.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    ordered.addAll(rest);
    var row = 0;
    return [
      for (final item in ordered)
        item.isVisible
            ? item.copyWith(
                position: PersonalProfileModuleSize.three.span * row++,
              )
            : item.copyWith(position: -1),
    ];
  }

  /// Only the layout items `modules` may carry.
  static List<PersonalProfileModuleLayoutItem> modulesOf(
    Iterable<PersonalProfileModuleLayoutItem> layout,
  ) => [
    for (final item in layout)
      if (!PersonalProfileShowcaseIds.isShowcaseOnly(item.moduleId)) item,
  ];

  /// The stored list for a single-column layout: every item, visible ones in
  /// display order first.
  static List<Map<String, Object?>> wire(
    Iterable<PersonalProfileModuleLayoutItem> layout,
  ) {
    final visible = layout.where((item) => item.isVisible).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final hidden = layout.where((item) => !item.isVisible);
    return [
      for (final item in [...visible, ...hidden])
        {'id': item.moduleId, 'isVisible': item.isVisible},
    ];
  }
}

/// The single-column favourite showcase is 1 large + 3 small (2026-11-05).
/// The `favorite-ships` module keeps its 3 (released clients reject a module
/// with 4), so the 4th ship is the page's `favoriteShowcaseExtra`. Only the
/// HK page presentation holds it; the local profile file keeps 3 and never
/// gains the field.
abstract final class PersonalProfileFavoriteExtra {
  static const maximum = 1;
  static final _id = RegExp(r'^[0-9a-fA-F]{32}$');

  /// Parses `content.favoriteShowcaseExtra`. Null when the server sent none.
  /// [attach] then drops module duplicates and keeps at most [maximum].
  static List<String>? parse(Object? raw) {
    if (raw is! List || raw.length > 64) return null;
    final seen = <String>{};
    return List.unmodifiable([
      for (final id in raw)
        if (id is String && _id.hasMatch(id) && seen.add(id.toLowerCase())) id,
    ]);
  }

  /// The module that holds the single extra: the first visible favourite
  /// module by position, else `favorite-ships` (11-06: an owner who hid or
  /// removed the original module could never reach the 4th ship). The
  /// server keeps one page-level value, so moving it changes nothing there.
  static String _holderId(Iterable<PersonalProfileModuleLayoutItem> layout) {
    final visible =
        layout
            .where(
              (e) =>
                  e.isVisible &&
                  PersonalProfileModuleIds.isFavorite(e.moduleId),
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return visible.firstOrNull?.moduleId ??
        PersonalProfileModuleIds.favoriteShips;
  }

  /// The HK server can store the extra: the field and `mainRole` arrive in
  /// the same (second) HK release, and `mainRole` is always returned while
  /// an unset extra is not. Before it, the page keeps 3 and never sends one.
  static bool serverHolds(Map<String, Object?>? content) =>
      content != null &&
      (content['mainRole'] is String ||
          content['favoriteShowcaseExtra'] is List);

  /// The extra the layout holds; null where the page cannot hold one.
  static List<String>? of(Iterable<PersonalProfileModuleLayoutItem> layout) =>
      layout.where((e) => e.showcaseExtra != null).firstOrNull?.showcaseExtra;

  /// After an edit changed the layout (moved, hid, added or removed a
  /// module): moves the slot to the module that holds it now (see
  /// [_holderId]), keeping its ship. A page without the slot stays without
  /// it (CX-FAV-PER-MODULE-073-R: the slot stayed on a module moved down or
  /// hidden until the page was saved and read again).
  ///
  /// [each]: the server holds a 4th per module, so every favourite module,
  /// including one added during this edit, gets its own slot.
  static List<PersonalProfileModuleLayoutItem> reattach(
    List<PersonalProfileModuleLayoutItem> layout, {
    bool each = false,
  }) {
    if (each) return attachEach(layout, eachOf(layout));
    final extra = of(layout);
    return extra == null ? layout : attach(layout, extra);
  }

  /// Puts [extra] on the holder module (see [_holderId]), minus any ship a
  /// module already shows (the server drops such a duplicate as well), and
  /// clears it everywhere else. Null removes the slot: the 4th ship is then
  /// neither shown nor offered.
  static List<PersonalProfileModuleLayoutItem> attach(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    List<String>? extra,
  ) {
    final shown = {
      for (final item in layout)
        for (final id in item.favoriteShipIds ?? const <String>[])
          id.toLowerCase(),
    };
    final holder = _holderId(layout);
    return [
      for (final item in layout)
        item.moduleId != holder
            ? (item.showcaseExtra == null
                  ? item
                  : _with(item, item.favoriteShipIds, null))
            : _with(
                item,
                item.favoriteShipIds,
                extra == null
                    ? null
                    : [
                        for (final id in extra)
                          if (!shown.contains(id.toLowerCase())) id,
                      ].take(maximum).toList(),
              ),
    ];
  }

  /// How many ships the picker of [item] may hold: 3 in the module, plus
  /// one more only where [attach] put the slot.
  static int capacity(PersonalProfileModuleLayoutItem item) =>
      PersonalProfileModuleSize.three.span +
      (item.showcaseExtra != null ? maximum : 0);

  /// The ships the picker starts from, in display order.
  static List<String> picked(PersonalProfileModuleLayoutItem item) => [
    ...?item.favoriteShipIds,
    ...?item.showcaseExtra,
  ];

  /// A picker result: the first 3 to the module, the rest to the extra. A
  /// removed or moved ship leaves the extra, so it never repeats a module.
  static PersonalProfileModuleLayoutItem apply(
    PersonalProfileModuleLayoutItem item,
    List<String> result,
  ) {
    final span = PersonalProfileModuleSize.three.span;
    final module = result.take(span).toList(growable: false);
    return _with(
      item,
      List.unmodifiable(module),
      item.showcaseExtra != null
          ? result.skip(span).take(maximum).toList(growable: false)
          : null,
      size: module.length > item.size.span
          ? PersonalProfileModuleSize.three
          : item.size,
    );
  }

  static PersonalProfileModuleLayoutItem _with(
    PersonalProfileModuleLayoutItem item,
    List<String>? favoriteShipIds,
    List<String>? extra, {
    PersonalProfileModuleSize? size,
  }) => PersonalProfileModuleLayoutItem(
    moduleId: item.moduleId,
    size: size ?? item.size,
    isVisible: item.isVisible,
    position: item.position,
    favoriteShipIds: favoriteShipIds,
    showcaseExtra: extra == null ? null : List.unmodifiable(extra),
  );

  // Per-module fourth ships (user 11-06 "every module", the third HK release):
  // `content.favoriteShowcaseExtras` maps each favourite module to its 4th
  // ship. Modules keep 3, so released clients never see a module with 4.

  /// The server holds a 4th ship per module: it always returns the map
  /// (`{}` when empty). Never inferred from a module id.
  static bool serverHoldsEach(Map<String, Object?>? content) =>
      content?['favoriteShowcaseExtras'] is Map;

  /// Parses `content.favoriteShowcaseExtras`; null when the server sent none.
  static Map<String, String>? parseEach(Object? raw) {
    if (raw is! Map || raw.length > 64) return null;
    return Map.unmodifiable({
      for (final entry in raw.entries)
        if (entry.key is String &&
            PersonalProfileModuleIds.isFavorite(entry.key as String) &&
            entry.value is String &&
            _id.hasMatch(entry.value as String))
          entry.key as String: entry.value as String,
    });
  }

  /// Every favourite module gets its own slot (capacity 4) holding its entry
  /// of [extras], minus ships a module shows or another entry already took.
  static List<PersonalProfileModuleLayoutItem> attachEach(
    Iterable<PersonalProfileModuleLayoutItem> layout,
    Map<String, String> extras,
  ) {
    final used = {
      for (final item in layout)
        for (final id in item.favoriteShipIds ?? const <String>[])
          id.toLowerCase(),
    };
    return [
      for (final item in layout)
        if (!PersonalProfileModuleIds.isFavorite(item.moduleId))
          item
        else
          _with(item, item.favoriteShipIds, [
            if (extras[item.moduleId] case final id?
                when used.add(id.toLowerCase()))
              id,
          ]),
    ];
  }

  /// The per-module map a layout holds (modules with a 4th ship only).
  static Map<String, String> eachOf(
    Iterable<PersonalProfileModuleLayoutItem> layout,
  ) => {
    for (final item in layout)
      if (PersonalProfileModuleIds.isFavorite(item.moduleId) &&
          (item.showcaseExtra?.isNotEmpty ?? false))
        item.moduleId: item.showcaseExtra!.first,
  };

  /// Every 4th ship the layout shows, in layout order (ship lookups).
  static List<String> allOf(Iterable<PersonalProfileModuleLayoutItem> layout) =>
      [for (final item in layout) ...?item.showcaseExtra];

  /// The per-module page edit value: null when unchanged, else the whole map
  /// (`{}` clears every entry).
  static Map<String, String>? editEach(
    Iterable<PersonalProfileModuleLayoutItem> displayed,
    Iterable<PersonalProfileModuleLayoutItem> edited,
  ) {
    final next = eachOf(attachEach(edited, eachOf(edited)));
    final before = eachOf(displayed);
    final same =
        next.length == before.length &&
        next.entries.every((e) => before[e.key] == e.value);
    return same ? null : next;
  }

  /// The page edit value: null when unchanged (the server keeps the saved
  /// value), the new list otherwise; `[]` is an explicit clear.
  static List<String>? edit(
    Iterable<PersonalProfileModuleLayoutItem> displayed,
    Iterable<PersonalProfileModuleLayoutItem> edited,
  ) {
    final next = of(attach(edited, of(edited)));
    if (next == null) return null;
    final before = of(displayed) ?? const <String>[];
    return next.join(',') == before.join(',') ? null : next;
  }
}

/// One achievement a visitor may see: only the id and when it was earned.
final class PersonalProfilePublicAchievement {
  const PersonalProfilePublicAchievement(this.id, this.earnedAt);
  final String id;
  final DateTime earnedAt;
}

/// Achievement showcase data carried with a profile read.
final class PersonalProfileShowcaseData {
  const PersonalProfileShowcaseData({
    this.achievementShowcase,
    this.publicAchievements,
    this.mainRoleEditable = false,
    this.favoriteExtrasEach = false,
    this.achievementCount,
  });

  /// Achievements HK recorded for this person (HK swap 5, user 11-11): the
  /// header shows the same number to the owner and a visitor; null from
  /// older servers.
  final int? achievementCount;

  /// The owner's server holds a 4th ship per favourite module (it returned
  /// `favoriteShowcaseExtras`): layout edits give every favourite module a
  /// slot, including modules added during the edit.
  final bool favoriteExtrasEach;

  /// The owner's page can save a main role: the local page, or an HK page
  /// whose server returned the field (after the second HK release).
  final bool mainRoleEditable;

  /// The owner's own picks (owner reads only; visitors never receive them).
  /// Null when never saved.
  final List<String>? achievementShowcase;

  /// What a visitor's server allowed: null when not shown to this viewer.
  final List<PersonalProfilePublicAchievement>? publicAchievements;

  static const none = PersonalProfileShowcaseData();

  static List<PersonalProfilePublicAchievement>? parsePublic(Object? raw) {
    if (raw is! List ||
        raw.length > PersonalProfileShowcases.maximumAchievements) {
      return null;
    }
    final result = <PersonalProfilePublicAchievement>[];
    for (final item in raw) {
      final id = item is Map ? item['id'] : null;
      final at = item is Map && item['earnedAt'] is String
          ? DateTime.tryParse(item['earnedAt'] as String)
          : null;
      if (id is! String ||
          PersonalProfileShowcases.parseAchievements([id])?.length != 1 ||
          at == null ||
          !at.isUtc) {
        return null; // Malformed: drop the whole field, never a partial list.
      }
      result.add(PersonalProfilePublicAchievement(id, at));
    }
    return List.unmodifiable(result);
  }
}

/// Reads the showcase fields of a profile read. An owner read carries the
/// picks; a visitor read only the server's public list.
({
  List<PersonalProfileModuleLayoutItem> layout,
  PersonalProfileShowcaseData data,
})
readPersonalProfileShowcases({
  required List<PersonalProfileModuleLayoutItem> modules,
  required Map<String, Object?> content,
  required Map<String, Object?> profile,
  required bool editable,
}) => (
  // Visitors get the extra exactly as the module favourites: same ship lookup.
  // A server with the per-module map gives every favourite module a 4th.
  layout: PersonalProfileFavoriteExtra.serverHoldsEach(content)
      ? PersonalProfileFavoriteExtra.attachEach(
          PersonalProfileShowcases.merge(
            modules,
            PersonalProfileShowcases.parse(content['showcases']),
          ),
          PersonalProfileFavoriteExtra.parseEach(
                content['favoriteShowcaseExtras'],
              ) ??
              const {},
        )
      : PersonalProfileFavoriteExtra.attach(
          PersonalProfileShowcases.merge(
            modules,
            PersonalProfileShowcases.parse(content['showcases']),
          ),
          PersonalProfileFavoriteExtra.parse(
                content['favoriteShowcaseExtra'],
              ) ??
              (editable && PersonalProfileFavoriteExtra.serverHolds(content)
                  ? const []
                  : null),
        ),
  data: PersonalProfileShowcaseData(
    achievementShowcase: editable
        ? PersonalProfileShowcases.parseAchievements(
            content['achievementShowcase'],
          )
        : null,
    publicAchievements: editable
        ? null
        : PersonalProfileShowcaseData.parsePublic(
            profile['publicAchievements'],
          ),
    mainRoleEditable: editable && content['mainRole'] is String,
    achievementCount: parseAchievementCount(profile),
    favoriteExtrasEach:
        editable && PersonalProfileFavoriteExtra.serverHoldsEach(content),
  ),
);
