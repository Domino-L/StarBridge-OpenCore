import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Presentation-only values. The installed appearance owns each profile's
/// semantics; this envelope contains no assets, source grants or entitlements.
/// Keeping canonical JSON privately also prevents mutable caller maps from
/// changing a saved snapshot or an undo-history entry.
@immutable
final class OverlayAppearanceOptions {
  const OverlayAppearanceOptions.empty()
    : _json = '{"profiles":{},"schemaVersion":1}';

  const OverlayAppearanceOptions._(this._json);

  final String _json;
  static const maximumBytes = 16 * 1024;

  factory OverlayAppearanceOptions.fromMap(Map<String, Object?> source) {
    _exact(source, const {'schemaVersion', 'profiles'});
    if (source['schemaVersion'] is! int || source['schemaVersion'] != 1) {
      throw const FormatException('Unsupported appearance options.');
    }
    final profiles = source['profiles'];
    if (profiles is! Map || profiles.length > 8) {
      throw const FormatException('Invalid appearance profiles.');
    }
    for (final profile in profiles.values) {
      if (profile is! Map) {
        throw const FormatException('Invalid appearance profile.');
      }
      _exact(profile, const {'version', 'values'});
      final version = profile['version'];
      if (version is! int ||
          version < 1 ||
          version > 1000 ||
          profile['values'] is! Map) {
        throw const FormatException('Invalid appearance profile.');
      }
    }
    final budget = _ValueBudget();
    final normalized = budget.copy(source, 0);
    final json = jsonEncode(normalized);
    if (utf8.encode(json).length > maximumBytes) {
      throw const FormatException('Appearance options too large.');
    }
    return OverlayAppearanceOptions._(json);
  }

  Map<String, Object?> toMap() =>
      (jsonDecode(_json) as Map).cast<String, Object?>();

  /// Returns a detached copy, never the snapshot's internal state.
  Map<String, Object?>? profile(String id) {
    final value = (toMap()['profiles'] as Map)[id];
    return value == null ? null : (value as Map).cast<String, Object?>();
  }

  /// Replaces only one profile, preserving options of other appearances.
  /// An absent profile means the appearance's undecorated/default state.
  OverlayAppearanceOptions withProfile(
    String id,
    Map<String, Object?>? profile,
  ) {
    final copy = toMap();
    final profiles = copy['profiles'] as Map;
    if (profile == null) {
      profiles.remove(id);
    } else {
      profiles[id] = profile;
    }
    return OverlayAppearanceOptions.fromMap(copy);
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayAppearanceOptions && other._json == _json;

  @override
  int get hashCode => _json.hashCode;
}

void _exact(Map value, Set<String> fields) {
  if (!setEquals(value.keys.toSet(), fields)) {
    throw const FormatException('Invalid appearance fields.');
  }
}

final class _ValueBudget {
  int remaining = 1024;

  Object? copy(Object? value, int containers) {
    if (--remaining < 0) {
      throw const FormatException('Too many appearance values.');
    }
    if (value is Map || value is List) {
      if (containers >= 8) {
        throw const FormatException('Appearance options too deep.');
      }
    }
    if (value is Map) {
      for (final key in value.keys) {
        if (key is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(key) ||
            const {'__proto__', 'prototype', 'constructor'}.contains(key)) {
          throw const FormatException('Invalid appearance key.');
        }
      }
      final keys = value.keys.cast<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: copy(value[key], containers + 1),
      };
    }
    if (value is List) {
      return value.map((item) => copy(item, containers + 1)).toList();
    }
    if (value is String) {
      if (value.length > 256) {
        throw const FormatException('Appearance value too long.');
      }
      return value;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw const FormatException('Invalid appearance number.');
      }
      return value;
    }
    if (value == null || value is bool) return value;
    throw const FormatException('Invalid appearance value.');
  }
}
