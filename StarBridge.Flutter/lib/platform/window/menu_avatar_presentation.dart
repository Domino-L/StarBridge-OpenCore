abstract interface class MenuAvatarPresentation {
  set showAvatars(bool value);
}

/// Removes only avatar presentation fields, never message/attachment content.
Map<String, Object?> withoutMenuAvatars(Map<String, Object?> view) {
  Object? clean(Object? value) => switch (value) {
    Map map => <String, Object?>{
      for (final entry in map.entries)
        entry.key as String: entry.key == 'avatar' || entry.key == 'ownAvatar'
            ? null
            : clean(entry.value),
    },
    List list => [for (final item in list) clean(item)],
    _ => value,
  };
  return clean(view) as Map<String, Object?>;
}

String? menuInlineAvatar(String? value) =>
    value != null &&
        value.length <= 128 * 1024 &&
        (value.startsWith('data:image/png;base64,') ||
            value.startsWith('data:image/jpeg;base64,'))
    ? value
    : null;
