import 'community_creation_port.dart';

// One ASCII character costs one unit, other Unicode scalars cost two.
// Limits are independent of the UI language, including mixed-language input.
int communityTextUnits(String value) =>
    value.runes.fold(0, (count, rune) => count + (rune <= 0x7f ? 1 : 2));

const communityProfileEditLimits = {
  'name': 32,
  'logoText': 16,
  'description': 400,
  'recruitingNote': 400,
  'websiteUrl': 256,
};

bool communityProfileTextFits(String field, String value) {
  if (field == 'name') {
    final runes = value.trim().runes;
    return runes.isNotEmpty &&
        runes.length <= 32 &&
        !value.runes.any((r) => r < 32 || (r >= 127 && r <= 159));
  }
  final limit = communityProfileEditLimits[field];
  if (limit == null) return true;
  return (field == 'websiteUrl'
          ? value.runes.length
          : communityTextUnits(value)) <=
      limit;
}

class CommunityTagQuota {
  CommunityTagQuota(
    Iterable<String> selected,
    List<CommunityTagOption> options,
  ) {
    for (final id in selected.toSet()) {
      final matches = options.where((tag) => tag.id == id);
      if (matches.isEmpty) {
        unknown++;
        continue;
      }
      switch (matches.first.categoryId) {
        case 'core':
          core++;
          break;
        case 'style':
        case 'scale':
          style++;
          break;
        default:
          other++;
      }
    }
  }
  int core = 0, style = 0, other = 0, unknown = 0;
  int get reservedStyle => style.clamp(0, 2);
  int get shared => other + (style > 2 ? style - 2 : 0);
  bool get withinCapacity => core <= 3 && shared <= 5 && unknown == 0;
  bool get valid => core >= 1 && withinCapacity;
}
