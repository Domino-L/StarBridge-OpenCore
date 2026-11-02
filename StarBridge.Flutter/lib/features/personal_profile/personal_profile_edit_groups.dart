import 'dart:convert';

import 'personal_profile_favorite_modules.dart';
import 'personal_profile_models.dart';

/// Compare with what the editor actually displayed, not with raw server data:
/// rendering defaults and local projections are not proof of user edits.
Map<String, Map<String, Object?>> personalProfileEditGroups(
  PersonalProfileSnapshot displayed,
  PersonalProfileEdit edit,
) {
  final groups = <String, Map<String, Object?>>{};
  if (edit.about.trim() != displayed.about.trim()) {
    groups['introduction'] = {'introduction': edit.about.trim()};
  }
  if (edit.avatarStyle != displayed.avatarStyle) {
    groups['avatarStyle'] = {'avatarStyle': edit.avatarStyle};
  }
  if (edit.wallpaperId != displayed.wallpaperId) {
    groups['wallpaper'] = {'wallpaperId': edit.wallpaperId};
  }
  var layout = edit.moduleLayout;
  if (edit.favoriteShipIds != null) {
    layout = ProfileFavoriteModules.materialize([
      for (final module in layout)
        PersonalProfileModuleLayoutItem(
          moduleId: module.moduleId,
          size: module.size,
          isVisible: module.isVisible,
          position: module.position,
        ),
    ], edit.favoriteShipIds);
  }
  List<Map<String, Object?>> wire(
    List<PersonalProfileModuleLayoutItem> value,
  ) => [
    for (var index = 0; index < value.length; index++)
      {
        'id': value[index].moduleId,
        'span': value[index].size.span,
        'isVisible': value[index].isVisible,
        'order': index,
        'position': value[index].position,
        if (value[index].favoriteShipIds != null)
          'favoriteShipIds': value[index].favoriteShipIds,
      },
  ];
  if (jsonEncode(wire(layout)) != jsonEncode(wire(displayed.moduleLayout))) {
    groups['layout'] = {'modules': wire(layout)};
  }
  final style = edit.playStyle;
  if (style != null) {
    final changed = <String, Object?>{
      if (style.roles != null) 'skilledRoles': style.roles,
      if (style.interests != null) 'participationInterests': style.interests,
      if (style.support != null) 'supportCapabilities': style.support,
    };
    if (changed.isNotEmpty) groups['playStyle'] = changed;
  }
  final schedule = edit.schedule;
  if (schedule != null) {
    final windows = schedule.windows;
    groups['schedule'] = {
      'showOnlineTime': windows.isNotEmpty,
      'onlineTimeStart': windows.isEmpty ? '19:00' : windows.first.startTime,
      'onlineTimeEnd': windows.isEmpty ? '22:00' : windows.first.endTime,
      'availabilityTimeZoneId': schedule.timeZoneId.isEmpty
          ? null
          : schedule.timeZoneId,
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
  // Callsign and visibility are separate explicit authorities, never page groups.
  return groups;
}
