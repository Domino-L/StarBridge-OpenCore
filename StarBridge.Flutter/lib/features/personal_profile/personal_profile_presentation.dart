/// Server read provenance, not an instruction to copy local or legacy data.
/// Retains exact wire content for later explicit-group edits without projecting
/// rich layouts or unresolved ship references through a lossy UI model.
final class PersonalProfilePresentation {
  PersonalProfilePresentation._(
    this.revision,
    this.sourceVersion,
    this.origins,
    this.content,
    this.avatarStyle,
    this.wallpaperId,
  );

  final int revision;
  final String? sourceVersion;
  final Map<String, String> origins;
  final Map<String, Object?> content;
  final int avatarStyle;
  final String wallpaperId;

  bool canAutoImport(String group) =>
      origins[group] == 'default' || origins[group] == 'linkedLegacy';

  /// A caller must identify actual user edits, not pass an entire projected
  /// page. Empty edits perform no write; an explicitly cleared group can
  /// become custom.
  Map<String, Object?>? editRequest(Map<String, Map<String, Object?>> edits) {
    if (edits.isEmpty) return null;
    // The 4th showcase ship is sent only as an explicit layout edit: omitted,
    // the server keeps the saved value.
    final nextContent = <String, Object?>{...content}
      ..remove('presenceIntent')
      ..remove('favoriteShowcaseExtra')
      // Likewise the per-module 4th ships (user 11-06) and the main role:
      // sent only when the owner changed them.
      ..remove('favoriteShowcaseExtras')
      ..remove('mainRole');
    // WhenWritingNull omits these nullable record properties on a Host read,
    // but the page write contract requires both keys in the content object.
    nextContent.putIfAbsent('availabilityTimeZoneId', () => null);
    nextContent.putIfAbsent('availabilityWindows', () => const <Object?>[]);
    Object? nextStyle = avatarStyle;
    Object? nextWallpaper = wallpaperId;
    for (final entry in edits.entries) {
      final allowed = _fields[entry.key];
      if (allowed == null ||
          entry.value.isEmpty ||
          entry.value.keys.any((field) => !allowed.contains(field))) {
        throw const FormatException('Invalid explicit page edit');
      }
      if (entry.key == 'avatarStyle') {
        nextStyle = entry.value['avatarStyle'];
      } else if (entry.key == 'wallpaper') {
        nextWallpaper = entry.value['wallpaperId'];
      } else {
        for (final field in entry.value.entries) {
          final previous = content[field.key];
          final draft = field.value;
          if (_orderedTags.contains(field.key) &&
              previous is List &&
              draft is List) {
            final kept = {...draft};
            nextContent[field.key] = [
              ...previous.where(kept.remove),
              ...draft.where(kept.remove),
            ];
          } else {
            nextContent[field.key] = draft;
          }
        }
      }
    }
    return _freeze({
      'schemaVersion': 1,
      'expectedRevision': revision,
      'sourceVersion': sourceVersion,
      'editedGroups': edits.keys.toList(growable: false),
      'avatarStyle': nextStyle,
      'wallpaperId': nextWallpaper,
      'content': nextContent,
    }) as Map<String, Object?>;
  }

  bool sameGroup(String group, PersonalProfilePresentation other) =>
      origins[group] == other.origins[group] &&
      switch (group) {
        'avatarStyle' => avatarStyle == other.avatarStyle,
        'wallpaper' => wallpaperId == other.wallpaperId,
        _ => _fields[group]!.every(
          (field) =>
              content.containsKey(field) == other.content.containsKey(field) &&
              (group == 'playStyle'
                  ? samePlayStyleField(content[field], other.content[field])
                  : sameValue(content[field], other.content[field])),
        ),
      };

  static bool samePlayStyleField(Object? left, Object? right) =>
      left is List && right is List
      ? left.toSet().length == right.toSet().length &&
            left.toSet().containsAll(right)
      : sameValue(left, right);

  static bool sameValue(Object? left, Object? right) {
    if (left is List && right is List) {
      return left.length == right.length &&
          left.indexed.every((item) => sameValue(item.$2, right[item.$1]));
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.entries.every(
            (entry) =>
                right.containsKey(entry.key) &&
                sameValue(entry.value, right[entry.key]),
          );
    }
    return left == right;
  }

  static final groups = Set<String>.unmodifiable(_fields.keys);
  static const _orderedTags = {
    'skilledRoles',
    'participationInterests',
    'supportCapabilities',
  };
  static const _fields = {
    'introduction': {'introduction'},
    'layout': {
      'modules',
      'showcases',
      'achievementShowcase',
      'favoriteShowcaseExtra',
      'favoriteShowcaseExtras',
    },
    'favorites': {'favoriteShipCodes'},
    'wishlist': {'shipWishlist'},
    'playStyle': {
      'skilledRoles',
      'supportCapabilities',
      'participationInterests',
      'mainRole',
    },
    'schedule': {
      'showOnlineTime',
      'onlineTimeStart',
      'onlineTimeEnd',
      'activityRhythm',
      'availabilityTimeZoneId',
      'availabilityWindows',
    },
    'avatarStyle': {'avatarStyle'},
    'wallpaper': {'wallpaperId'},
  };

  static PersonalProfilePresentation? fromProfile(
    Map<String, Object?> profile,
  ) {
    final metadata = profile['presentation'];
    if (metadata == null) return null; // Older backend; never infer provenance.
    if (metadata is! Map ||
        metadata.length != 3 ||
        metadata['schemaVersion'] != 1 ||
        !metadata.containsKey('sourceVersion')) {
      throw const FormatException('Page provenance');
    }
    final version = metadata['sourceVersion'];
    final origins = metadata['origins'];
    final revision = profile['revision'];
    final content = profile['content'];
    final style = profile['avatarStyle'];
    final wallpaper = profile['wallpaperId'];
    if (version != null &&
            (version is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(version)) ||
        origins is! Map ||
        origins.length != groups.length ||
        !groups.every(
          (group) => const {
            'default',
            'custom',
            'unknown',
            'imported',
            'linkedLegacy',
          }.contains(origins[group]),
        ) ||
        revision is! int ||
        revision < 0 ||
        content is! Map ||
        style is! int ||
        style < 0 ||
        style > 3 ||
        wallpaper is! String) {
      throw const FormatException('Page provenance');
    }
    return PersonalProfilePresentation._(
      revision,
      version as String?,
      Map.unmodifiable(origins.cast<String, String>()),
      _freeze(content) as Map<String, Object?>,
      style,
      wallpaper,
    );
  }

  static Object? _freeze(Object? value) => switch (value) {
    Map value => Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freeze(entry.value),
    }),
    List value => List<Object?>.unmodifiable(value.map(_freeze)),
    _ => value,
  };
}
