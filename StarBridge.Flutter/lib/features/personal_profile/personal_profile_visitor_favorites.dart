import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_models.dart';
import 'personal_profile_showcases.dart';

List<PersonalProfileModuleLayoutItem> visitorFavoriteLayout(
  List<PersonalProfileModuleLayoutItem> layout,
) {
  final visible = layout.where((item) => item.isVisible).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  return [...visible, ...layout.where((item) => !item.isVisible)];
}

/// A visitor page whose older flat favourite modules (no saved ship IDs) sit
/// beside other visible favourite modules: each flat module takes the page's
/// flat favourites in order, skipping any ship or model another module already
/// shows, up to its span. Several flat modules share them in layout order. A
/// page with a single visible flat module is left as it is (the flat path).
List<PersonalProfileModuleLayoutItem> visitorFlatFavorites(
  List<PersonalProfileModuleLayoutItem> layout,
  List<String> flatCodes,
  PersonalProfileShipIdentity? Function(String id) lookup,
) {
  bool favorite(PersonalProfileModuleLayoutItem item) =>
      item.isVisible && PersonalProfileModuleIds.isFavorite(item.moduleId);
  final visible = layout.where(favorite).toList();
  // One visible flat module keeps the flat path. With any other visible
  // favourite module (picked, explicitly empty or flat), each flat module
  // gets its own share, so no ship shows twice.
  if (visible.length < 2 ||
      !visible.any((item) => item.favoriteShipIds == null)) {
    return layout;
  }
  final takenIds = <String>{};
  final takenModels = <String>{};
  void take(String id) {
    takenIds.add(id.toLowerCase());
    if (lookup(id) case final ship?) {
      takenModels.add(ProfileFavoriteModules.modelKey(ship));
    }
  }

  bool taken(String id) =>
      takenIds.contains(id.toLowerCase()) ||
      switch (lookup(id)) {
        final ship? => takenModels.contains(
          ProfileFavoriteModules.modelKey(ship),
        ),
        null => false,
      };

  for (final item in layout.where(favorite)) {
    PersonalProfileFavoriteExtra.picked(item).forEach(take);
  }
  // Ships the response can show come first, so an ID with no hangar row never
  // takes a slot from one that can show; it still counts as pending after.
  final queue = [
    ...flatCodes.where((id) => lookup(id) != null),
    ...flatCodes.where((id) => lookup(id) == null),
  ];
  List<String> fill(int span) {
    final ids = <String>[];
    while (queue.isNotEmpty && ids.length < span) {
      final id = queue.removeAt(0);
      if (taken(id)) continue;
      ids.add(id);
      take(id);
    }
    return ids;
  }

  return [
    for (final item in layout)
      if (!favorite(item) || item.favoriteShipIds != null)
        item
      else
        item.copyWith(favoriteShipIds: fill(item.size.span)),
  ];
}

/// The layout the visitor's ship filtering sees: hidden favourite modules
/// without their picks, so a hidden pick never filters or reserves a visible
/// ship. The snapshot keeps those picks ([visitorRestoreHiddenPicks]).
List<PersonalProfileModuleLayoutItem> visitorWithoutHiddenPicks(
  List<PersonalProfileModuleLayoutItem> layout,
) => [
  for (final item in layout)
    PersonalProfileModuleIds.isFavorite(item.moduleId) && !item.isVisible
        ? PersonalProfileModuleLayoutItem(
            moduleId: item.moduleId,
            size: item.size,
            isVisible: false,
            position: item.position,
          )
        : item,
];

/// Puts the hidden modules' own picks (as received) back after filtering.
List<PersonalProfileModuleLayoutItem> visitorRestoreHiddenPicks(
  List<PersonalProfileModuleLayoutItem> shown,
  List<PersonalProfileModuleLayoutItem> received,
) {
  final picks = {
    for (final item in received) item.moduleId: item.favoriteShipIds,
  };
  return [
    for (final item in shown)
      item.isVisible
          ? item
          : item.copyWith(favoriteShipIds: picks[item.moduleId]),
  ];
}

/// Visitors see only visible modules' 4th ships: a hidden module's 4th never
/// reserves, replaces or joins a visible card (HK already sends none). The
/// older single field belongs to the base favourite module.
Map<String, Object?> visitorVisibleExtras(
  Map<String, Object?> content,
  List<PersonalProfileModuleLayoutItem> modules,
) {
  final visible = {
    for (final item in modules)
      if (item.isVisible && PersonalProfileModuleIds.isFavorite(item.moduleId))
        item.moduleId,
  };
  final extras = content['favoriteShowcaseExtras'];
  return {
    ...content,
    if (extras is Map)
      'favoriteShowcaseExtras': {
        for (final entry in extras.entries)
          if (visible.contains(entry.key)) entry.key: entry.value,
      },
    if (!visible.contains(PersonalProfileModuleIds.favoriteShips))
      'favoriteShowcaseExtra': null,
  };
}

/// The visitor's candidate ships, in the order the page shows them. With no
/// visible picking module (the flat path) that is the flat list's own order,
/// then the 4th ships, so a 4th never becomes the large card.
List<String> visitorFavoriteCodes(
  List<PersonalProfileModuleLayoutItem> layout,
  List<String> legacyCodes,
) => {
  if (!layout.any(
    (item) =>
        item.isVisible &&
        PersonalProfileModuleIds.isFavorite(item.moduleId) &&
        item.favoriteShipIds != null,
  ))
    for (final code in legacyCodes) code.toLowerCase(),
  for (final item in layout)
    if (item.isVisible && PersonalProfileModuleIds.isFavorite(item.moduleId))
      for (final id in PersonalProfileFavoriteExtra.picked(item))
        id.toLowerCase(),
  for (final code in legacyCodes) code.toLowerCase(),
}.toList();

/// The favourite module's state line: ships still to resolve, none chosen,
/// or no hangar data.
Widget profileFavoritesStateText(
  BuildContext context,
  int unresolvedCount,
  bool hangarAvailable,
) {
  final key = unresolvedCount > 0
      ? 'profile.ships.pendingDetails'
      : hangarAvailable
      ? 'profile.ships.empty'
      : 'profile.ships.notConnected';
  return Text(
    AppStrings.of(context).text(key).replaceAll('{count}', '$unresolvedCount'),
    key: const Key('profile-favorites-empty-state'),
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.tokens.colors.textSecondary),
  );
}
