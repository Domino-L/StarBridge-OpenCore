import 'personal_profile_models.dart';
import 'personal_profile_role_catalog.dart';

// Profile tag parsing for the HK page wire, moved out of the adapter
// (800-line gate) without change.
List<PersonalProfileTagValue> parseProfileTags(List<String> values) => [
  for (final value in values)
    PersonalProfileRoleCatalog.resolve(value) ??
        PersonalProfileTagValue(
          labelKey: value,
          displayLabel: value,
          category: classifyProfileTag(value),
        ),
];

PersonalProfileTagCategory classifyProfileTag(String value) {
  final normalized = value.toLowerCase();
  if (_containsAny(normalized, const ['指挥', 'command', 'leader'])) {
    return PersonalProfileTagCategory.command;
  }
  if (_containsAny(normalized, const ['医疗', 'medical', 'medic'])) {
    return PersonalProfileTagCategory.medical;
  }
  if (_containsAny(normalized, const ['后勤', '运输', 'logistics', 'cargo'])) {
    return PersonalProfileTagCategory.logistics;
  }
  if (_containsAny(normalized, const ['采矿', '打捞', '工业', 'mining', 'salvage'])) {
    return PersonalProfileTagCategory.industry;
  }
  if (_containsAny(normalized, const ['地面', 'ground', 'fps'])) {
    return PersonalProfileTagCategory.groundCombat;
  }
  if (_containsAny(normalized, const ['侦察', 'recon', 'scout'])) {
    return PersonalProfileTagCategory.recon;
  }
  if (_containsAny(normalized, const ['空战', 'fighter', 'pvp'])) {
    return PersonalProfileTagCategory.airCombat;
  }
  return PersonalProfileTagCategory.ship;
}

bool _containsAny(String value, List<String> candidates) =>
    candidates.any(value.contains);
