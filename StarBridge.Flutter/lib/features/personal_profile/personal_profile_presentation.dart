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

  /// A caller must identify actual user edits, not pass an entire projected
  /// page. Empty edits perform no write; an explicit empty value still writes
  /// and becomes custom even when it equals the inherited display value.
  Map<String, Object?>? editRequest(Map<String, Map<String, Object?>> edits) {
    if (edits.isEmpty) return null;
    const fields = {
      'introduction': {'introduction'},
      'layout': {'modules'},
      'favorites': {'favoriteShipCodes'},
      'wishlist': {'shipWishlist'},
      'playStyle': {
        'skilledRoles',
        'supportCapabilities',
        'participationInterests',
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
    final nextContent = <String, Object?>{...content}..remove('presenceIntent');
    Object? nextStyle = avatarStyle;
    Object? nextWallpaper = wallpaperId;
    for (final entry in edits.entries) {
      final allowed = fields[entry.key];
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
        nextContent.addAll(entry.value);
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

  static const groups = {
    'introduction',
    'layout',
    'favorites',
    'schedule',
    'playStyle',
    'wishlist',
    'avatarStyle',
    'wallpaper',
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
