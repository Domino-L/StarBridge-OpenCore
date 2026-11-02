import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'overlay_appearance_options.dart';

/// A finite, declarative form supplied by an installed appearance. It has no
/// scripts, asset paths, runtime commands or authority fields.
final class OverlayAppearanceConfiguration {
  OverlayAppearanceConfiguration._(
    this.appearanceId,
    this.profileId,
    this.version,
    this.collection,
    this.title,
    this.description,
    this.slots,
    this.preview,
    this.fields,
  );
  final String appearanceId, profileId, collection;
  final int version;
  final AppearanceText title, description;
  final List<AppearanceSlot> slots;
  final AppearanceBitmap? preview;
  final List<AppearanceField> fields;

  factory OverlayAppearanceConfiguration.fromMap(Map<String, Object?> source) {
    if (utf8.encode(jsonEncode(source)).length > 48 * 1024) {
      throw const FormatException('Appearance form too large.');
    }
    _exact(source, {
      'schemaVersion',
      'appearanceId',
      'profileId',
      'version',
      'collection',
      'title',
      'description',
      'slots',
      if (source.containsKey('preview')) 'preview',
      if (source.containsKey('fields')) 'fields',
    });
    if (source['schemaVersion'] != 1 ||
        source['schemaVersion'] is! int ||
        source['version'] is! int ||
        (source['version'] as int) < 1 ||
        (source['version'] as int) > 1000) {
      throw const FormatException('Unsupported appearance form.');
    }
    final slots = _list(
      source['slots'],
      12,
    ).map((value) => AppearanceSlot.fromMap(_map(value))).toList();
    if (slots.isEmpty ||
        slots.map((s) => s.id).toSet().length != slots.length ||
        slots.map((s) => jsonEncode(s.identity.keys.toList())).toSet().length !=
            1 ||
        slots.map((s) => jsonEncode(s.identity)).toSet().length !=
            slots.length) {
      throw const FormatException('Duplicate appearance slot.');
    }
    final collection = _key(source['collection']);
    final fields = _list(
      source['fields'] ?? const [],
      4,
    ).map((value) => AppearanceField.fromMap(_map(value))).toList();
    if (source.containsKey('fields') && source['fields'] == null ||
        fields.map((field) => field.key).toSet().length != fields.length ||
        fields.any((field) => field.key == collection)) {
      throw const FormatException('Invalid appearance global fields.');
    }
    return OverlayAppearanceConfiguration._(
      _key(source['appearanceId']),
      _key(source['profileId']),
      source['version'] as int,
      collection,
      AppearanceText.from(source['title']),
      AppearanceText.from(source['description']),
      List.unmodifiable(slots),
      source['preview'] == null
          ? null
          : AppearanceBitmap.fromMap(_map(source['preview'])),
      List.unmodifiable(fields),
    );
  }

  /// Null means unsupported saved data. Never replace it with inferred defaults.
  Map<String, Map<String, Object?>?>? read(OverlayAppearanceOptions options) {
    final result = <String, Map<String, Object?>?>{
      for (final slot in slots) slot.id: null,
    };
    final profile = options.profile(profileId);
    if (profile == null) return result;
    try {
      if (profile['version'] != version) return null;
      final values = _map(profile['values']);
      _exact(values, {
        collection,
        for (final field in fields)
          if (values.containsKey(field.key)) field.key,
      });
      _fieldValues(values);
      for (final value in _list(values[collection], slots.length)) {
        final row = _map(value);
        final matches = slots.where(
          (slot) => slot.identity.entries.every((e) => row[e.key] == e.value),
        );
        if (matches.length != 1) return null;
        final slot = matches.single;
        if (result[slot.id] != null) return null;
        final choice = slot.choices.where((c) => c.value == row[slot.selector]);
        if (choice.length != 1) return null;
        _exact(row, {
          ...slot.identity.keys,
          slot.selector,
          ...choice.single.fields.map((f) => f.key),
        });
        if (choice.single.fields.any(
          (f) => !f.options.any((o) => o.value == row[f.key]),
        )) {
          return null;
        }
        result[slot.id] = row;
      }
      return result;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object>? readFields(OverlayAppearanceOptions options) {
    if (read(options) == null) return null;
    final profile = options.profile(profileId);
    return _fieldValues(profile == null ? const {} : _map(profile['values']));
  }

  Map<String, Object> _fieldValues(Map<String, Object?> values) => {
    for (final field in fields)
      field.key: () {
        if (!values.containsKey(field.key)) return field.defaultValue;
        final value = values[field.key];
        if (!field.options.any((option) => option.value == value)) {
          throw const FormatException('Invalid appearance global value.');
        }
        return value!;
      }(),
  };

  OverlayAppearanceOptions changeField(
    OverlayAppearanceOptions options,
    String fieldKey,
    Object value,
  ) {
    final rows = read(options);
    final field = fields.where((field) => field.key == fieldKey).firstOrNull;
    if (rows == null ||
        field == null ||
        !field.options.any((option) => option.value == value)) {
      throw const FormatException('Unsupported appearance global value.');
    }
    return _write(options, rows, fieldChanges: {fieldKey: value});
  }

  /// Removing scene items must not reset independent presentation settings.
  OverlayAppearanceOptions clearCollection(OverlayAppearanceOptions options) {
    final rows = read(options);
    if (rows == null) {
      throw const FormatException('Unsupported appearance values.');
    }
    final values = options.profile(profileId)?['values'];
    if (values == null ||
        !fields.any((field) => _map(values).containsKey(field.key))) {
      return options.withProfile(profileId, null);
    }
    return _write(options, {for (final slot in slots) slot.id: null});
  }

  OverlayAppearanceOptions select(
    OverlayAppearanceOptions options,
    String slotId,
    int index,
  ) {
    final rows = read(options);
    if (rows == null) {
      throw const FormatException('Unsupported saved appearance values.');
    }
    final slot = slots.singleWhere((s) => s.id == slotId);
    if (index < 0 || index > slot.choices.length) {
      throw const FormatException('Invalid appearance choice.');
    }
    if (index == 0) {
      rows[slotId] = null;
    } else {
      final choice = slot.choices[index - 1];
      final previous = rows[slotId];
      rows[slotId] = {
        ...slot.identity,
        slot.selector: choice.value,
        for (final field in choice.fields)
          field.key: field.options.any((o) => o.value == previous?[field.key])
              ? previous![field.key]
              : field.defaultValue,
      };
    }
    return _write(options, rows);
  }

  OverlayAppearanceOptions change(
    OverlayAppearanceOptions options,
    String slotId,
    String fieldKey,
    Object value,
  ) {
    final rows = read(options);
    if (rows == null || rows[slotId] == null) {
      throw const FormatException('Unsupported appearance values.');
    }
    final slot = slots.singleWhere((s) => s.id == slotId);
    final row = rows[slotId]!;
    final choice = slot.choices.singleWhere(
      (c) => c.value == row[slot.selector],
    );
    final field = choice.fields.singleWhere((f) => f.key == fieldKey);
    if (!field.options.any((o) => o.value == value)) {
      throw const FormatException('Invalid appearance value.');
    }
    rows[slotId] = {...row, fieldKey: value};
    return _write(options, rows);
  }

  OverlayAppearanceOptions _write(
    OverlayAppearanceOptions previous,
    Map<String, Map<String, Object?>?> rows, {
    Map<String, Object> fieldChanges = const {},
  }) => previous.withProfile(profileId, {
    'version': version,
    'values': {
      collection: [
        for (final slot in slots)
          if (rows[slot.id] != null) rows[slot.id],
      ],
      for (final field in fields)
        if (fieldChanges.containsKey(field.key) ||
            previous.profile(profileId)?['values'] is Map &&
                _map(previous.profile(profileId)!['values'])
                    .containsKey(field.key))
          field.key:
              fieldChanges[field.key] ??
              _map(previous.profile(profileId)!['values'])[field.key],
    },
  });
}

/// Small installed-pack PNG only: no file names, remote URLs or executable data.
/// Private artwork stays outside the source tree; callers receive detached bytes.
final class AppearanceBitmap {
  AppearanceBitmap._(this.width, this.height, List<int> bytes)
    : _bytes = List.unmodifiable(bytes);
  final int width, height;
  final List<int> _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  factory AppearanceBitmap.fromMap(Map<String, Object?> source) {
    _exact(source, {'format', 'width', 'height', 'data'});
    final width = source['width'],
        height = source['height'],
        data = source['data'];
    if (source['format'] != 'png' ||
        width is! int ||
        height is! int ||
        width < 1 ||
        width > 2048 ||
        height < 1 ||
        height > 1024 ||
        width * height > 1048576 ||
        data is! String ||
        data.length > 21848) {
      throw const FormatException('Invalid appearance bitmap.');
    }
    final bytes = base64Decode(data);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 45 ||
        bytes.length > 16 * 1024 ||
        !Iterable<int>.generate(8).every((i) => bytes[i] == signature[i]) ||
        !Iterable<int>.generate(4)
            .every((i) => bytes[12 + i] == [73, 72, 68, 82][i])) {
      throw const FormatException('Invalid appearance PNG.');
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(8) != 13 ||
        header.getUint32(16) != width ||
        header.getUint32(20) != height) {
      throw const FormatException('Appearance PNG dimensions do not match.');
    }
    return AppearanceBitmap._(width, height, bytes);
  }
}

final class AppearanceText {
  const AppearanceText(this.zhCN, this.zhTW, this.en);
  final String zhCN, zhTW, en;
  factory AppearanceText.from(Object? value) {
    final m = _map(value);
    _exact(m, {'zhCN', 'zhTW', 'en'});
    String text(String key) {
      final v = m[key];
      if (v is! String || v.isEmpty || v.length > 256) {
        throw const FormatException('Invalid appearance label.');
      }
      return v;
    }

    return AppearanceText(text('zhCN'), text('zhTW'), text('en'));
  }
  String resolve(Locale locale) => locale.languageCode != 'zh'
      ? en
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? zhTW
      : zhCN;
}

final class AppearanceSlot {
  AppearanceSlot._(
    this.id,
    this.group,
    this.label,
    this.identity,
    this.selector,
    this.choices,
  );
  final String id, selector;
  final AppearanceText group, label;
  final Map<String, Object> identity;
  final List<AppearanceChoice> choices;
  factory AppearanceSlot.fromMap(Map<String, Object?> m) {
    _exact(m, {'id', 'group', 'label', 'identity', 'selector', 'choices'});
    final input = _map(m['identity']);
    if (input.isEmpty || input.length > 4) {
      throw const FormatException('Invalid slot identity.');
    }
    final keys = input.keys.toList()..sort();
    final identity = <String, Object>{
      for (final key in keys) _key(key): _scalar(input[key]),
    };
    final selector = _key(m['selector']);
    final choices = _list(
      m['choices'],
      8,
    ).map((v) => AppearanceChoice.fromMap(_map(v))).toList();
    if (identity.containsKey(selector) ||
        choices.isEmpty ||
        choices.map((c) => c.value).toSet().length != choices.length ||
        choices.any(
          (c) => c.fields.any(
            (f) => identity.containsKey(f.key) || f.key == selector,
          ),
        )) {
      throw const FormatException('Invalid appearance choices.');
    }
    return AppearanceSlot._(
      _key(m['id']),
      AppearanceText.from(m['group']),
      AppearanceText.from(m['label']),
      Map.unmodifiable(identity),
      selector,
      List.unmodifiable(choices),
    );
  }
}

final class AppearanceChoice {
  AppearanceChoice._(this.value, this.label, this.fields);
  final Object value;
  final AppearanceText label;
  final List<AppearanceField> fields;
  factory AppearanceChoice.fromMap(Map<String, Object?> m) {
    _exact(m, {'value', 'label', 'fields'});
    final fields = _list(
      m['fields'],
      4,
    ).map((v) => AppearanceField.fromMap(_map(v))).toList();
    if (fields.map((f) => f.key).toSet().length != fields.length) {
      throw const FormatException('Duplicate appearance field.');
    }
    return AppearanceChoice._(
      _scalar(m['value']),
      AppearanceText.from(m['label']),
      List.unmodifiable(fields),
    );
  }
}

final class AppearanceField {
  AppearanceField._(this.key, this.label, this.defaultValue, this.options);
  final String key;
  final AppearanceText label;
  final Object defaultValue;
  final List<AppearanceValue> options;
  factory AppearanceField.fromMap(Map<String, Object?> m) {
    _exact(m, {'key', 'label', 'default', 'options'});
    final options = _list(
      m['options'],
      8,
    ).map((v) => AppearanceValue.fromMap(_map(v))).toList();
    final value = _scalar(m['default']);
    if (options.isEmpty ||
        options.map((o) => o.value).toSet().length != options.length ||
        !options.any((o) => o.value == value)) {
      throw const FormatException('Invalid appearance defaults.');
    }
    return AppearanceField._(
      _key(m['key']),
      AppearanceText.from(m['label']),
      value,
      List.unmodifiable(options),
    );
  }
}

final class AppearanceValue {
  AppearanceValue._(this.value, this.label);
  final Object value;
  final AppearanceText label;
  factory AppearanceValue.fromMap(Map<String, Object?> m) {
    _exact(m, {'value', 'label'});
    return AppearanceValue._(
      _scalar(m['value']),
      AppearanceText.from(m['label']),
    );
  }
}

Object _scalar(Object? value) {
  if (value is bool || value is int || value is String && value.length <= 64) {
    return value!;
  }
  throw const FormatException('Invalid appearance form scalar.');
}

String _key(Object? v) {
  if (v is! String ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(v) ||
      const {'__proto__', 'prototype', 'constructor'}.contains(v)) {
    throw const FormatException('Invalid appearance form key.');
  }
  return v;
}

Map<String, Object?> _map(Object? v) {
  if (v is! Map || v.keys.any((k) => k is! String)) {
    throw const FormatException('Expected appearance form object.');
  }
  return Map<String, Object?>.from(v);
}

List<Object?> _list(Object? v, int max) {
  if (v is! List || v.length > max) {
    throw const FormatException('Invalid appearance form list.');
  }
  return List<Object?>.from(v);
}

void _exact(Map<String, Object?> m, Set<String> fields) {
  if (m.length != fields.length || m.keys.any((k) => !fields.contains(k))) {
    throw const FormatException('Invalid appearance form fields.');
  }
}
