import 'package:flutter/foundation.dart';

import 'personal_profile_collaboration.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_showcases.dart';

/// S2 could save these empty defaults when the Relay page was unavailable.
bool hasSavedProfileLayout(Map<String, Object?> content) {
  final layout = savedProfileLayout(content);
  if ((content['favoriteShipIds'] as List?)?.isNotEmpty == true ||
      layout.any((item) => item.favoriteShipIds?.isNotEmpty == true)) {
    return true;
  }
  final normalized = _layoutShape(layout);
  return !_defaultShells.any((shell) => listEquals(shell, normalized));
}

bool isDefaultProfileSchedule(PersonalProfileSchedule schedule) =>
    schedule.timeZoneId.isEmpty &&
    schedule.rhythm == PersonalProfileActivityRhythm.casual &&
    schedule.windows.isEmpty;

List<(String, int, bool, int)> _layoutShape(
  Iterable<PersonalProfileModuleLayoutItem> layout,
) => [
  for (final item in PersonalProfileLayout.normalize(layout))
    (item.moduleId, item.size.span, item.isVisible, item.position),
];

final _defaultShells = [
  _layoutShape(const []),
  _layoutShape(const [_defaultFavorite]),
  _layoutShape(const [
    _defaultFavorite,
    PersonalProfileModuleLayoutItem(
      moduleId: PersonalProfileModuleIds.hangarSummary,
      size: PersonalProfileModuleSize.three,
      isVisible: true,
      position: 3,
    ),
  ]),
];

const _defaultFavorite = PersonalProfileModuleLayoutItem(
  moduleId: PersonalProfileModuleIds.favoriteShips,
  size: PersonalProfileModuleSize.three,
  isVisible: true,
  position: 0,
);

/// The versioned server rejects content it would normalize. Isolate groups
/// with known mismatches before assembling the page; the server still makes
/// the final decision for the full contract.
bool isCanonicalProfileImportGroup(String group, Map<String, Object?> fields) =>
    switch (group) {
      'introduction' => _canonicalText(fields['introduction'] as String, 500),
      'favorites' => _canonicalList(fields['favoriteShipCodes'], 3),
      'playStyle' =>
        const [
              'skilledRoles',
              'supportCapabilities',
              'participationInterests',
            ].every((key) => _canonicalList(fields[key], 8)) &&
            (fields['mainRole'] == null ||
                _canonicalText(fields['mainRole'] as String, 80)),
      'schedule' => _canonicalSchedule(fields),
      'layout' => _canonicalLayout(fields),
      _ => true,
    };

bool _canonicalText(String value, int limit) =>
    value.length <= limit && value == value.trim();

bool _canonicalList(Object? value, int limit) {
  if (value == null) return true;
  final items = (value as List).cast<String>();
  return items.length <= limit &&
      items.toSet().length == items.length &&
      items.map((item) => item.toLowerCase()).toSet().length == items.length &&
      items.every((item) => item.isNotEmpty && _canonicalText(item, 80));
}

bool _canonicalSchedule(Map<String, Object?> fields) {
  final zone = fields['availabilityTimeZoneId'] as String?;
  final windows = (fields['availabilityWindows'] as List).cast<Map>();
  return (zone == null || _canonicalText(zone, 128)) &&
      windows.length <= 3 &&
      windows.every((window) {
        final days = (window['days'] as List).cast<int>();
        return days.isNotEmpty &&
            days.every((day) => day >= 0 && day <= 6) &&
            days.toSet().length == days.length &&
            ProfileCollaboration.validTime(window['startTime'] as String) &&
            ProfileCollaboration.validTime(window['endTime'] as String);
      });
}

bool _canonicalLayout(Map<String, Object?> fields) {
  final modules = (fields['modules'] as List? ?? const []).cast<Map>();
  final showcases = (fields['showcases'] as List? ?? const []).cast<Map>();
  final ids = modules.map((module) => module['id']);
  final shipId = RegExp(r'^[0-9a-fA-F]{32}$');
  return modules.length <= PersonalProfileLayout.maxModules &&
      ids.toSet().length == modules.length &&
      showcases.length <= PersonalProfileShowcases.maximum &&
      modules.every((module) {
        final picks = (module['favoriteShipIds'] as List? ?? const [])
            .cast<String>();
        final position = module['position'] as int;
        return PersonalProfileShowcases.isKnownId(module['id'] as String) &&
            picks.length <= 3 &&
            picks.map((pick) => pick.toLowerCase()).toSet().length ==
                picks.length &&
            picks.every(shipId.hasMatch) &&
            (module['isVisible'] == true
                ? position >= 0 && position < PersonalProfileLayout.maximumCells
                : position == -1);
      });
}
