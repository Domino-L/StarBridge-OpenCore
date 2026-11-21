import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'personal_profile_collaboration.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_showcases.dart';

/// Compare with what the editor actually displayed, not with raw server data:
/// rendering defaults and local projections are not proof of user edits.
Map<String, Map<String, Object?>> personalProfileEditGroups(
  PersonalProfileSnapshot displayed,
  PersonalProfileEdit edit, {
  bool fromEditor = true,
}) {
  final groups = <String, Map<String, Object?>>{};
  if (edit.about.trim() != displayed.about.trim()) {
    groups['introduction'] = {'introduction': edit.about.trim()};
  }
  if (edit.avatarStyle != displayed.avatarStyle) {
    groups['avatarStyle'] = {'avatarStyle': edit.avatarStyle};
  }
  if (edit.wallpaperId.trim() != displayed.wallpaperId.trim()) {
    groups['wallpaper'] = {'wallpaperId': edit.wallpaperId};
  }
  List<String> strings(Object? value) => [
    for (final item in (value as List? ?? const []).whereType<String>())
      item.trim(),
  ];
  final content = displayed.presentation?.content;
  final favoriteCodes = edit.favoriteShipCodes;
  if (favoriteCodes != null &&
      !listEquals(
        strings(favoriteCodes).map((code) => code.toLowerCase()).toList(),
        strings(content?['favoriteShipCodes'])
            .map((code) => code.toLowerCase())
            .toList(),
      )) {
    groups['favorites'] = {'favoriteShipCodes': favoriteCodes};
  }
  final wishlist = edit.shipWishlist;
  if (wishlist != null &&
      !listEquals(strings(wishlist), strings(content?['shipWishlist']))) {
    groups['wishlist'] = {'shipWishlist': wishlist};
  }
  var layout = edit.moduleLayout;
  if (changedLocalProfileFavoriteIds(displayed, edit) case final ids?) {
    layout = ProfileFavoriteModules.materialize([
      for (final module in layout)
        PersonalProfileModuleLayoutItem(
          moduleId: module.moduleId,
          size: module.size,
          isVisible: module.isVisible,
          position: module.position,
        ),
    ], ids);
  }
  List<Map<String, Object?>> wire(
    List<PersonalProfileModuleLayoutItem> value, {
    bool compare = false,
  }) => [
    for (var index = 0; index < value.length; index++)
      {
        'id': value[index].moduleId,
        'span': value[index].size.span,
        'isVisible': value[index].isVisible,
        'order': index,
        'position': value[index].position,
        if (compare)
          'favoriteShipIds': [
            for (final id in value[index].favoriteShipIds ?? const <String>[])
              id.toLowerCase(),
          ]
        else if (value[index].favoriteShipIds != null)
          'favoriteShipIds': value[index].favoriteShipIds,
      },
  ];
  // `modules` keeps only what released clients know; the single-column order
  // and the showcase-only entries go in `showcases` (2026-11-03).
  final baseline = fromEditor
      ? PersonalProfileLayout.normalize(displayed.moduleLayout)
      : displayed.moduleLayout;
  final comparedLayout = fromEditor
      ? PersonalProfileLayout.normalize(layout)
      : layout;
  final modules = wire(PersonalProfileShowcases.modulesOf(layout));
  final layoutGroup = <String, Object?>{
    if (jsonEncode(
          wire(
            PersonalProfileShowcases.modulesOf(comparedLayout),
            compare: true,
          ),
        ) !=
        jsonEncode(
          wire(PersonalProfileShowcases.modulesOf(baseline), compare: true),
        ))
      'modules': modules,
  };
  final showcases = PersonalProfileShowcases.wire(
    PersonalProfileLayout.normalize(layout),
  );
  if (jsonEncode(showcases) !=
      jsonEncode(
        PersonalProfileShowcases.wire(
          PersonalProfileLayout.normalize(displayed.moduleLayout),
        ),
      )) {
    layoutGroup['showcases'] = showcases;
  }
  final picks = edit.achievementShowcase;
  if (picks != null &&
      !listEquals(
        strings(picks),
        strings(displayed.showcaseData.achievementShowcase),
      )) {
    layoutGroup['achievementShowcase'] = picks;
  }
  // The 4th showcase ship: only when it changed (2026-11-05). A server with
  // the per-module map (user 11-06) gets the whole map, `{}` to clear; the
  // server keeps the old single field in step itself.
  // A 4th ship hidden on read as a model repeat (user 11-07) is still saved
  // on the server: once the user saves other layout changes, the save also
  // sends the 4th ships as shown, so the hidden copy is cleared. A save that
  // leaves the layout untouched still writes nothing to it.
  final layoutSaved = layoutGroup.isNotEmpty;
  if (PersonalProfileFavoriteExtra.serverHoldsEach(content)) {
    var extras = PersonalProfileFavoriteExtra.editEach(
      baseline,
      comparedLayout,
    );
    if (extras == null && layoutSaved) {
      final next = PersonalProfileFavoriteExtra.eachOf(
        PersonalProfileFavoriteExtra.attachEach(
          layout,
          PersonalProfileFavoriteExtra.eachOf(layout),
        ),
      );
      final saved =
          PersonalProfileFavoriteExtra.parseEach(
            content!['favoriteShowcaseExtras'],
          ) ??
          const <String, String>{};
      final same =
          next.length == saved.length &&
          next.entries.every((e) => saved[e.key] == e.value);
      if (!same) extras = next;
    }
    if (extras != null) layoutGroup['favoriteShowcaseExtras'] = extras;
  } else {
    var extra = PersonalProfileFavoriteExtra.edit(baseline, comparedLayout);
    if (extra == null && layoutSaved) {
      final next = PersonalProfileFavoriteExtra.of(
        PersonalProfileFavoriteExtra.attach(
          layout,
          PersonalProfileFavoriteExtra.of(layout),
        ),
      );
      final saved = PersonalProfileFavoriteExtra.parse(
        content?['favoriteShowcaseExtra'],
      );
      if (next != null && saved != null && next.join(',') != saved.join(',')) {
        extra = next;
      }
    }
    if (extra != null) layoutGroup['favoriteShowcaseExtra'] = extra;
  }
  if (layoutGroup.isNotEmpty) groups['layout'] = layoutGroup;
  final style = changedPersonalProfilePlayStyle(displayed, edit.playStyle);
  if (style != null) {
    final changed = <String, Object?>{
      if (style.roles != null) 'skilledRoles': style.roles,
      if (style.interests != null) 'participationInterests': style.interests,
      if (style.support != null) 'supportCapabilities': style.support,
      // Only a page whose server returned the field can hold it (11-05).
      if (style.mainRole != null &&
          displayed.presentation?.content.containsKey('mainRole') == true)
        'mainRole': style.mainRole,
    };
    if (changed.isNotEmpty) groups['playStyle'] = changed;
  }
  final schedule = edit.schedule;
  if (schedule != null &&
      jsonEncode(_scheduleFields(schedule)) !=
          jsonEncode(
            _scheduleFields(
              PersonalProfileSchedule(
                timeZoneId: displayed.timeZoneLabel,
                rhythm: displayed.activityRhythm,
                windows: displayed.availabilityWindows,
              ),
            ),
          )) {
    groups['schedule'] = _scheduleFields(schedule);
  }
  // Callsign and visibility are separate explicit authorities, never page groups.
  return groups;
}

List<String>? changedLocalProfileFavoriteIds(
  PersonalProfileSnapshot displayed,
  PersonalProfileEdit edit,
) {
  final ids = edit.favoriteShipIds;
  final baseline =
      displayed.local?.favoriteShipIds ??
      ProfileFavoriteModules.selections(displayed.moduleLayout);
  return ids == null ||
          listEquals(
            ids.map((id) => id.toLowerCase()).toList(),
            (baseline ?? const <String>[])
                .map((id) => id.toLowerCase())
                .toList(),
          )
      ? null
      : ids;
}

PersonalProfilePlayStyle? changedPersonalProfilePlayStyle(
  PersonalProfileSnapshot displayed,
  PersonalProfilePlayStyle? draft,
) {
  if (draft == null) return null;
  List<String>? changed(
    List<String>? ids,
    List<PersonalProfileTagValue> baseline,
    String field,
  ) {
    if (ids == null) return null;
    final before = {...ProfileCollaboration.ids(baseline, field)};
    final after = {for (final id in ids) id.trim()};
    if (setEquals(before, after)) return null;
    return [
      ...before.where(after.contains),
      ...after.where((id) => !before.contains(id)),
    ];
  }

  final main = displayed.roles.where((role) => role.isPrimary).firstOrNull;
  final mainId = main == null ? '' : ProfileCollaboration.idOf(main, 'roles');
  final mainChanged =
      draft.mainRole != null && draft.mainRole!.trim() != mainId;
  final roles =
      changed(draft.roles, displayed.roles, 'roles') ??
      (mainChanged && draft.roles != null
          ? ProfileCollaboration.ids(displayed.roles, 'roles')
          : null);
  final interests = changed(
    draft.interests,
    displayed.participationInterests,
    'interests',
  );
  final support = changed(
    draft.support,
    displayed.supportCapabilities,
    'support',
  );
  if (!mainChanged && roles == null && interests == null && support == null) {
    return null;
  }
  return PersonalProfilePlayStyle(
    roles: roles,
    interests: interests,
    support: support,
    mainRole: mainChanged ? draft.mainRole : null,
  );
}

Map<String, Object?> _scheduleFields(PersonalProfileSchedule schedule) {
  final windows = schedule.windows;
  final zone = schedule.timeZoneId.trim();
  return {
    'showOnlineTime': windows.isNotEmpty,
    'onlineTimeStart': windows.isEmpty ? '19:00' : windows.first.startTime,
    'onlineTimeEnd': windows.isEmpty ? '22:00' : windows.first.endTime,
    'availabilityTimeZoneId': zone.isEmpty ? null : zone,
    'availabilityWindows': [
      for (final window in windows)
        {
          ...window.toJson(),
          // Java's strict page contract orders Monday first, Sunday last.
          // Sort a copy: click order and the editor's draft remain untouched.
          'days': [...window.days]
            ..sort((a, b) => (a == 0 ? 7 : a).compareTo(b == 0 ? 7 : b)),
        },
    ],
    'activityRhythm': switch (schedule.rhythm) {
      PersonalProfileActivityRhythm.casual => '休闲',
      PersonalProfileActivityRhythm.regular => '稳定活跃',
      PersonalProfileActivityRhythm.intensive => '高频活跃',
      PersonalProfileActivityRhythm.weekends => '周末为主',
      PersonalProfileActivityRhythm.irregular => '不固定',
    },
  };
}
