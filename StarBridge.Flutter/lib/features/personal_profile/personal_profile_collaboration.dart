import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'personal_profile_models.dart';
import 'personal_profile_role_catalog.dart';

abstract final class ProfileCollaboration {
  static final options = <String, Map<String, PersonalProfileTagValue>>{
    'roles': {
      for (final id in PersonalProfileRoleCatalog.categories.keys)
        id: PersonalProfileRoleCatalog.resolve(id)!,
    },
    'interests': {
      'fleet-operations': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.fleet-operations',
        category: PersonalProfileTagCategory.command,
      ),
      'squad-missions': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.squad-missions',
        category: PersonalProfileTagCategory.command,
      ),
      'pve': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.pve',
        category: PersonalProfileTagCategory.airCombat,
      ),
      'pvp': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.pvp',
        category: PersonalProfileTagCategory.airCombat,
      ),
      'bounty': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.bounty',
        category: PersonalProfileTagCategory.airCombat,
      ),
      'ground': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.ground',
        category: PersonalProfileTagCategory.groundCombat,
      ),
      'trading': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.trading',
        category: PersonalProfileTagCategory.logistics,
      ),
      'mining': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.mining',
        category: PersonalProfileTagCategory.industry,
      ),
      'salvage': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.salvage',
        category: PersonalProfileTagCategory.industry,
      ),
      'exploration': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.exploration',
        category: PersonalProfileTagCategory.recon,
      ),
      'racing': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.racing',
        category: PersonalProfileTagCategory.ship,
      ),
      'social': const PersonalProfileTagValue(
        labelKey: 'profile.collab.interests.social',
        category: PersonalProfileTagCategory.ship,
      ),
    },
    'support': {
      'command': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.command',
        category: PersonalProfileTagCategory.command,
      ),
      'pilot': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.pilot',
        category: PersonalProfileTagCategory.ship,
      ),
      'gunner': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.gunner',
        category: PersonalProfileTagCategory.ship,
      ),
      'medical': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.medical',
        category: PersonalProfileTagCategory.medical,
      ),
      'supply': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.supply',
        category: PersonalProfileTagCategory.logistics,
      ),
      'engineering': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.engineering',
        category: PersonalProfileTagCategory.ship,
      ),
      'navigation': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.navigation',
        category: PersonalProfileTagCategory.recon,
      ),
      'transport': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.transport',
        category: PersonalProfileTagCategory.logistics,
      ),
      'teaching': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.teaching',
        category: PersonalProfileTagCategory.command,
      ),
      'ship-sharing': const PersonalProfileTagValue(
        labelKey: 'profile.collab.support.ship-sharing',
        category: PersonalProfileTagCategory.logistics,
      ),
    },
  };
  static int limit(String group) => group == 'roles' ? 5 : 3;
  static List<PersonalProfileTagValue>? tags(Object? raw, String group) =>
      raw == null
      ? null
      : [for (final id in (raw as List).cast<String>()) options[group]![id]!];

  static List<String> ids(List<PersonalProfileTagValue> tags, String group) =>
      {for (final tag in tags) _id(tag, group)}.toList();

  static String _id(PersonalProfileTagValue tag, String group) {
    const aliases = {
      'profile.role.expeditionCommander': 'fleet-command',
      'profile.role.pilot': 'pilot',
      'profile.role.gunner': 'gunner',
      'profile.role.fighterPilot': 'fighter-pilot',
      'profile.playstyle.pveCombat': 'pve',
      'profile.support.pilot': 'pilot',
      'profile.support.gunner': 'gunner',
    };
    final alias = aliases[tag.labelKey];
    if (alias != null && options[group]!.containsKey(alias)) return alias;
    for (final entry in options[group]!.entries) {
      if (tag.labelKey == entry.value.labelKey || tag.labelKey == entry.key) {
        return entry.key;
      }
      for (final locale in AppStrings.supportedLocales) {
        final translated = AppStrings.resolve(locale)
            .text(entry.value.labelKey);
        if ((tag.displayLabel ?? tag.labelKey) == translated) return entry.key;
      }
    }
    // Do not silently remove unknown historic selections during unrelated edits.
    return tag.displayLabel ?? tag.labelKey;
  }

  static bool validGroup(List<String>? ids, String group) =>
      ids == null ||
      (ids.length <= limit(group) &&
          ids.toSet().length == ids.length &&
          ids.every(options[group]!.containsKey));

  static List<PersonalProfileAvailabilityWindow> windows(Object? raw) => [
    for (final w in (raw as List).cast<Map>())
      PersonalProfileAvailabilityWindow(
        days: (w['days'] as List).cast<int>(),
        startTime: w['startTime'] as String,
        endTime: w['endTime'] as String,
      ),
  ];
  static bool validTime(String value) =>
      RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value);
  static bool validSchedule(PersonalProfileSchedule? schedule) =>
      schedule == null ||
      (schedule.windows.length <= 3 &&
          (schedule.windows.isEmpty || schedule.timeZoneId.isNotEmpty) &&
          schedule.windows.every(
            (w) =>
                w.days.isNotEmpty &&
                w.days.length <= 7 &&
                w.days.toSet().length == w.days.length &&
                w.days.every((d) => d >= 0 && d <= 6) &&
                validTime(w.startTime) &&
                validTime(w.endTime),
          ));

  static String daysLabel(AppStrings strings, List<int> days) {
    final set = days.toSet();
    if (set.length == 7) return strings.text('profile.collab.everyDay');
    if (set.length == 5 && set.containsAll([1, 2, 3, 4, 5])) {
      return strings.text('profile.availability.weekdays');
    }
    if (set.length == 2 && set.containsAll([6, 0])) {
      return strings.text('profile.availability.weekend');
    }
    return [
      for (final day in [1, 2, 3, 4, 5, 6, 0])
        if (set.contains(day)) strings.text('profile.collab.day.$day'),
    ].join(' / ');
  }

  static String summary(
    BuildContext context,
    List<PersonalProfileAvailabilityWindow> windows,
  ) {
    final strings = AppStrings.of(context);
    if (windows.isEmpty) return strings.text('profile.collab.noTimes');
    return windows
        .map(
          (w) =>
              '${daysLabel(strings, w.days)} ${w.startTime}–'
              '${w.endsNextDay ? "${strings.text('profile.collab.nextDay')} " : ""}${w.endTime}',
        )
        .join(' · ');
  }
}
