import 'dart:collection';

import 'package:flutter/foundation.dart';

enum OverlaySourceMode { none, auto, room, community }

enum OverlaySourceModule { notice, overview, members, chat, events }

/// Display intent only. Neither saved identities nor UI choices grant access.
@immutable
final class OverlaySourceBinding {
  const OverlaySourceBinding.follow()
    : mode = OverlaySourceMode.none,
      communityCode = null,
      ownerKey = null;
  const OverlaySourceBinding.automatic()
    : mode = OverlaySourceMode.auto,
      communityCode = null,
      ownerKey = null;
  const OverlaySourceBinding.room()
    : mode = OverlaySourceMode.room,
      communityCode = null,
      ownerKey = null;

  factory OverlaySourceBinding.community(String code, String owner) {
    if (!_key(code) || !_key(owner)) {
      throw const FormatException('Invalid source identity.');
    }
    return OverlaySourceBinding._(OverlaySourceMode.community, code, owner);
  }
  const OverlaySourceBinding._(this.mode, this.communityCode, this.ownerKey);
  final OverlaySourceMode mode;
  final String? communityCode;
  final String? ownerKey;

  factory OverlaySourceBinding.fromMap(Map<String, Object?> value) {
    _exact(value, {'mode', 'communityCode', 'ownerKey'});
    final mode = value['mode'];
    final code = value['communityCode'];
    final owner = value['ownerKey'];
    if (mode == 'community' && code is String && owner is String) {
      return OverlaySourceBinding.community(code, owner);
    }
    if (code != null || owner != null) {
      throw const FormatException('Unexpected source identity.');
    }
    return switch (mode) {
      'none' => const OverlaySourceBinding.follow(),
      'auto' => const OverlaySourceBinding.automatic(),
      'room' => const OverlaySourceBinding.room(),
      _ => throw const FormatException('Invalid source mode.'),
    };
  }
  Map<String, Object?> toMap() => {
    'mode': mode.name,
    'communityCode': communityCode,
    'ownerKey': ownerKey,
  };
  @override
  bool operator ==(Object other) =>
      other is OverlaySourceBinding &&
      other.mode == mode &&
      other.communityCode == communityCode &&
      other.ownerKey == ownerKey;
  @override
  int get hashCode => Object.hash(mode, communityCode, ownerKey);
}

@immutable
final class OverlayPresetSources {
  OverlayPresetSources({
    this.binding = const OverlaySourceBinding.follow(),
    this.autoSwitch = false,
    Map<OverlaySourceModule, OverlaySourceBinding> modules = const {},
    List<OverlaySourceBinding> chatSources = const [],
  }) : modules = UnmodifiableMapView(Map.of(modules)),
       chatSources = List.unmodifiable(
         [...chatSources]..sort((a, b) {
           final mode = a.mode.index.compareTo(b.mode.index);
           if (mode != 0) return mode;
           final code = (a.communityCode ?? '').compareTo(
             b.communityCode ?? '',
           );
           return code != 0
               ? code
               : (a.ownerKey ?? '').compareTo(b.ownerKey ?? '');
         }),
       ) {
    if (chatSources.length > 8 ||
        chatSources.toSet().length != chatSources.length ||
        chatSources.any(
          (s) =>
              s.mode != OverlaySourceMode.room &&
              s.mode != OverlaySourceMode.community,
        )) {
      throw const FormatException('Invalid chat sources.');
    }
    if (autoSwitch &&
        binding.mode != OverlaySourceMode.room &&
        binding.mode != OverlaySourceMode.community) {
      throw const FormatException(
        'Automatic switching requires a concrete source.',
      );
    }
  }
  final OverlaySourceBinding binding;
  final bool autoSwitch;
  final Map<OverlaySourceModule, OverlaySourceBinding> modules;
  final List<OverlaySourceBinding> chatSources;
  OverlaySourceBinding forModule(OverlaySourceModule module) =>
      modules[module] ?? const OverlaySourceBinding.follow();

  factory OverlayPresetSources.fromLegacy(Object? preference) =>
      OverlayPresetSources(
        binding: preference == 'PartyRoom'
            ? const OverlaySourceBinding.room()
            : const OverlaySourceBinding.follow(),
      );

  bool get hasOrganizationBindings =>
      binding.mode == OverlaySourceMode.community ||
      [
        ...modules.values,
        ...chatSources,
      ].any((value) => value.mode == OverlaySourceMode.community);

  /// Both export and import apply this boundary; a package never grants access
  /// or installs automatic behavior on another device.
  OverlayPresetSources forTransfer() {
    OverlaySourceBinding clean(OverlaySourceBinding value) =>
        value.mode == OverlaySourceMode.community
        ? const OverlaySourceBinding.automatic()
        : value;
    return OverlayPresetSources(
      binding: clean(binding),
      modules: {
        for (final entry in modules.entries) entry.key: clean(entry.value),
        if (chatSources.isNotEmpty)
          OverlaySourceModule.chat:
              chatSources.any((source) => source.mode == OverlaySourceMode.room)
              ? const OverlaySourceBinding.room()
              : const OverlaySourceBinding.follow(),
      },
    );
  }

  factory OverlayPresetSources.fromMap(Map<String, Object?> value) {
    _exact(value, {
      'schemaVersion',
      'sourceBinding',
      'autoSwitch',
      'moduleSources',
      if (value['schemaVersion'] == 3) 'chatSources',
    });
    if ((value['schemaVersion'] != 2 && value['schemaVersion'] != 3) ||
        value['autoSwitch'] is! bool) {
      throw const FormatException('Invalid source policy version.');
    }
    final moduleMap = _map(value['moduleSources']);
    final chat = value['schemaVersion'] == 3 ? value['chatSources'] : const [];
    if (chat is! List || (value['schemaVersion'] == 3 && chat.isEmpty)) {
      throw const FormatException('Invalid chat source list.');
    }
    _exact(moduleMap, OverlaySourceModule.values.map((m) => m.name).toSet());
    return OverlayPresetSources(
      binding: OverlaySourceBinding.fromMap(_map(value['sourceBinding'])),
      autoSwitch: value['autoSwitch'] as bool,
      chatSources: chat
          .map((s) => OverlaySourceBinding.fromMap(_map(s)))
          .toList(),
      modules: {
        for (final module in OverlaySourceModule.values)
          module: OverlaySourceBinding.fromMap(_map(moduleMap[module.name])),
      },
    );
  }
  Map<String, Object?> toMap() => {
    'schemaVersion': chatSources.isEmpty ? 2 : 3,
    if (chatSources.isNotEmpty)
      'chatSources': chatSources.map((s) => s.toMap()).toList(),
    'sourceBinding': binding.toMap(),
    'autoSwitch': autoSwitch,
    'moduleSources': {
      for (final module in OverlaySourceModule.values)
        module.name: forModule(module).toMap(),
    },
  };
  OverlayPresetSources withModule(
    OverlaySourceModule module,
    OverlaySourceBinding value,
  ) => OverlayPresetSources(
    binding: binding,
    autoSwitch: autoSwitch,
    modules: {...modules, module: value},
    chatSources: module == OverlaySourceModule.chat ? const [] : chatSources,
  );
  OverlayPresetSources withChatSources(List<OverlaySourceBinding> values) =>
      OverlayPresetSources(
        binding: binding,
        autoSwitch: autoSwitch,
        modules: modules,
        chatSources: values,
      );
  @override
  bool operator ==(Object other) =>
      other is OverlayPresetSources &&
      other.binding == binding &&
      other.autoSwitch == autoSwitch &&
      listEquals(other.chatSources, chatSources) &&
      OverlaySourceModule.values.every(
        (module) => other.forModule(module) == forModule(module),
      );
  @override
  int get hashCode => Object.hash(
    binding,
    autoSwitch,
    Object.hashAll(chatSources),
    Object.hashAll(OverlaySourceModule.values.map(forModule)),
  );
}

bool _key(String value) =>
    value.isNotEmpty &&
    value.trim() == value &&
    value.length <= 256 &&
    !value.codeUnits.any((c) => c < 32 || (c >= 127 && c <= 159));
Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected source object.');
  }
  return Map<String, Object?>.from(value);
}

void _exact(Map<String, Object?> value, Set<String> fields) {
  if (!setEquals(value.keys.toSet(), fields)) {
    throw const FormatException('Invalid source fields.');
  }
}
