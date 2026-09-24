import 'party_rooms_module.dart';
import 'room_tag_definitions.dart';

/// ID-based WPF v3 hierarchy. Labels never determine ancestry or permissions.
final class RoomTagCatalog {
  RoomTagCatalog(Iterable<RoomTag> options)
    : options = {for (final tag in options) normalize(tag.id): tag};
  final Map<String, RoomTag> options;
  static final definitions = {
    for (final row in roomGameplayDefinitions) row.$1: row,
  };
  static String normalize(String id) => roomLegacyGameplayIds[id] ?? id;
  static List<String> pathIds(String id) {
    String? current = normalize(id);
    final path = <String>[];
    while (current != null && definitions.containsKey(current)) {
      path.insert(0, current);
      current = definitions[current]!.$3;
    }
    return path;
  }

  static bool descendant(String node, String ancestor) =>
      normalize(node) == normalize(ancestor) ||
      pathIds(node).contains(normalize(ancestor));
  static String fullText(RoomTag tag) {
    if (!tag.isGameplay) return tag.text;
    final path = pathIds(tag.id);
    return path.isEmpty
        ? tag.text
        : path.map((id) => definitions[id]!.$2).join(' / ');
  }

  static String compactText(RoomTag tag) =>
      tag.isGameplay ? fullText(tag).replaceAll(' / ', ' · ') : tag.text;
  static String name(String id) => definitions[normalize(id)]?.$2 ?? id;
  static String group(String id) =>
      roomContextDefinitions.where((row) => row.$1 == id).firstOrNull?.$3 ??
      'other';
  static List<RoomTag> ordered(Iterable<RoomTag> tags) {
    int rank(RoomTag tag) => tag.isGameplay
        ? 0
        : switch (group(tag.id)) {
            'need' => 1,
            'pace' => 2,
            'experience' => 3,
            _ => 4,
          };
    return tags.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  static List<RoomTag> get exampleOptions => [
    for (final row in roomGameplayDefinitions)
      RoomTag(
        id: row.$1,
        text: pathIds(row.$1).map(name).join(' / '),
        isGameplay: true,
      ),
    for (final row in roomContextDefinitions)
      RoomTag(id: row.$1, text: row.$2, isGameplay: false),
  ];
  List<String> children(String? parent) => [
    for (final row in roomGameplayDefinitions)
      if (row.$3 == parent &&
          options.values.any(
            (tag) => tag.isGameplay && descendant(tag.id, row.$1),
          ))
        row.$1,
    if (parent == null)
      for (final tag in options.values)
        if (tag.isGameplay && !definitions.containsKey(normalize(tag.id)))
          tag.id,
  ];
  String label(String id) => definitions[id]?.$2 ?? options[id]?.text ?? id;
  Set<String> normalizeSelection(Iterable<String> ids) =>
      ids.map(normalize).toSet();
  Set<String> adding(Set<String> selected, String id) {
    id = normalize(id);
    final next = normalizeSelection(selected);
    if (options[id]?.isGameplay == true) {
      next.removeWhere(
        (old) =>
            options[old]?.isGameplay == true &&
            (descendant(old, id) || descendant(id, old)),
      );
    }
    return next..add(id);
  }

  String? invalid(Set<String> selected, {bool requireGameplay = true}) {
    if (selected.any((id) => !options.containsKey(id))) return 'unknown';
    final gameplay = selected.where((id) => options[id]!.isGameplay).toList();
    if (gameplay.isEmpty && requireGameplay) return 'required';
    if (gameplay.length > 3) return 'gameplayLimit';
    if (selected.length - gameplay.length > 3) return 'contextLimit';
    if (selected.length > 5) return 'totalLimit';
    for (var a = 0; a < gameplay.length; a++) {
      for (var b = a + 1; b < gameplay.length; b++) {
        if (descendant(gameplay[a], gameplay[b]) ||
            descendant(gameplay[b], gameplay[a])) {
          return 'branch';
        }
      }
    }
    return null;
  }

  static bool matches(PartyRoom room, Set<String> selected, String query) {
    final gameplay = selected.where(
      (id) => definitions.containsKey(normalize(id)),
    );
    final context = selected.where(
      (id) => !definitions.containsKey(normalize(id)),
    );
    if (gameplay.isNotEmpty &&
        !room.tags.any(
          (tag) =>
              tag.isGameplay && gameplay.any((id) => descendant(tag.id, id)),
        )) {
      return false;
    }
    if (context.isNotEmpty &&
        !room.tags.any((tag) => !tag.isGameplay && context.contains(tag.id))) {
      return false;
    }
    final text = [
      room.title,
      room.goal,
      ...room.tags.map(fullText),
    ].join(' ').toLowerCase();
    return text.contains(query.trim().toLowerCase());
  }
}
