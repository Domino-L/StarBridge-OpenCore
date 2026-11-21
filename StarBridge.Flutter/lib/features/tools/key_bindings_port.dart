import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

@immutable
final class KeyBindingEntry {
  const KeyBindingEntry({
    required this.device,
    required this.instance,
    required this.input,
    required this.customized,
    this.multiTap,
    this.mode,
  });
  final String device, input;
  final int instance;
  final bool customized;
  final int? multiTap;
  final String? mode;
  bool get cleared => input.isEmpty;
}

@immutable
final class KeyBindingAction {
  const KeyBindingAction(this.name, this.bindings, {this.localizedName});
  final String name;

  /// From the localization file the player installed, when there is one.
  final String? localizedName;
  final List<KeyBindingEntry> bindings;
  bool get customized => bindings.any((binding) => binding.customized);
}

@immutable
final class KeyBindingMap {
  const KeyBindingMap(this.name, this.actions, {this.localizedName});
  final String name;
  final String? localizedName;
  final List<KeyBindingAction> actions;
}

@immutable
final class KeyBindingsSnapshot {
  const KeyBindingsSnapshot({
    required this.state,
    required this.channel,
    this.path,
    this.modifiedAt,
    this.defaultsVersion,
    this.maps = const [],
    this.namesState = 'unused',
    this.namesPath,
    this.view,
    this.defaultsRelease,
    this.localizations = const [],
    this.localization,
    this.localizationFallback = false,
  });

  /// Names languages installed with this game version: folder names.
  final List<String> localizations;
  final String? localization;

  /// The chosen language is not installed here, so the default was used.
  final bool localizationFallback;

  /// The release players know, such as 4.10.2; null on a table without one.
  final String? defaultsRelease;
  final KeyBindingsView? view;
  final String state, channel, namesState;
  final String? path, defaultsVersion, namesPath;
  final DateTime? modifiedAt;
  final List<KeyBindingMap> maps;
}

@immutable
final class KeyBindingsView {
  const KeyBindingsView({
    required this.mouse,
    this.keyboard,
    this.localization,
    this.listHeight,
    this.listOpen,
    this.notesOpen,
  });

  /// The chosen keyboard size; null: none chosen, the width picks one.
  final String? keyboard;
  final String mouse;

  /// The chosen names language folder; null follows the interface.
  final String? localization;

  /// The page layout: the list's height and what is folded; null: as it comes.
  final int? listHeight;
  final bool? listOpen, notesOpen;
}

abstract interface class KeyBindingsPort {
  /// language: 'zh-Hans', 'zh-Hant' or 'en', from the interface; localization:
  /// a folder from the listed ones, or null to follow the interface.
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  });

  /// Remembers the chosen keyboard size and mouse style on this device.
  Future<void> saveView(KeyBindingsView view);
}

final class BridgeKeyBindings implements KeyBindingsPort {
  BridgeKeyBindings(this._session);
  final BridgeClientSession _session;

  static const _states = {
    'ok',
    'noFile',
    'notInstalled',
    'multiple',
    'unreadable',
    'format',
  };

  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) async {
    final response = await _session.request(
      'keyBindings.read',
      payload: {
        'schemaVersion': 1,
        'channel': channel,
        'language': language,
        'localization': ?localization,
      },
    );
    return parseKeyBindings(response.payload, channel);
  }

  static Never _bad() => throw const BridgeFormatException(
    'Key bindings response is incompatible.',
  );

  @visibleForTesting
  static KeyBindingsSnapshot parseKeyBindings(
    Map<String, Object?> payload,
    String channel,
  ) {
    final state = payload['state'], path = payload['path'];
    final modified = payload['modifiedAtUtc'];
    final version = payload['defaultsVersion'], maps = payload['maps'];
    final namesState = payload['namesState'], namesPath = payload['namesPath'];
    if (payload['schemaVersion'] != 1 ||
        !_states.contains(state) ||
        payload['channel'] != channel ||
        (path != null && path is! String) ||
        (modified != null && modified is! String) ||
        (version != null && version is! String) ||
        !const {
          'unused',
          'missing',
          'unreadable',
          'ok',
          'bundled',
        }.contains(namesState) ||
        (namesPath != null && namesPath is! String) ||
        maps is! List) {
      _bad();
    }
    return KeyBindingsSnapshot(
      state: state as String,
      channel: channel,
      path: path as String?,
      modifiedAt: modified == null
          ? null
          : DateTime.tryParse(modified as String) ?? _bad(),
      defaultsVersion: version as String?,
      namesState: namesState as String,
      namesPath: namesPath as String?,
      view: _view(payload['view']),
      localizations: switch (payload['localizations']) {
        null => const [],
        final List<Object?> list when list.every((e) => e is String) =>
          list.cast<String>(),
        _ => _bad(),
      },
      localization: switch (payload['localization']) {
        null => null,
        final String name => name,
        _ => _bad(),
      },
      localizationFallback: switch (payload['localizationFallback']) {
        null => false,
        final bool fallback => fallback,
        _ => _bad(),
      },
      defaultsRelease: switch (payload['defaultsRelease']) {
        null => null,
        final String release => release,
        _ => _bad(),
      },
      maps: [for (final map in maps) _map(map)],
    );
  }

  static KeyBindingsView? _view(Object? value) {
    if (value == null) return null;
    final view = _object(value);
    final keyboard = view['keyboard'], mouse = view['mouse'];
    final localization = view['localization'];
    final listHeight = view['listHeight'];
    final listOpen = view['listOpen'], notesOpen = view['notesOpen'];
    if ((keyboard != null && keyboard is! String) ||
        mouse is! String ||
        (localization != null && localization is! String) ||
        (listHeight != null && listHeight is! int) ||
        (listOpen != null && listOpen is! bool) ||
        (notesOpen != null && notesOpen is! bool)) {
      _bad();
    }
    return KeyBindingsView(
      keyboard: keyboard as String?,
      mouse: mouse,
      localization: localization as String?,
      listHeight: listHeight as int?,
      listOpen: listOpen as bool?,
      notesOpen: notesOpen as bool?,
    );
  }

  @override
  Future<void> saveView(KeyBindingsView view) async {
    await _session.request(
      'keyBindings.saveView',
      payload: {
        'schemaVersion': 1,
        'keyboard': ?view.keyboard,
        'mouse': view.mouse,
        'localization': view.localization,
        'listHeight': ?view.listHeight,
        'listOpen': ?view.listOpen,
        'notesOpen': ?view.notesOpen,
      },
    );
  }

  static Map<String, Object?> _object(Object? value) =>
      value is Map<String, Object?> ? value : _bad();

  static KeyBindingMap _map(Object? value) {
    final map = _object(value);
    final name = map['name'], actions = map['actions'];
    final localized = map['localizedName'];
    if (name is! String ||
        actions is! List ||
        (localized != null && localized is! String)) {
      _bad();
    }
    return KeyBindingMap(name, [
      for (final action in actions) _action(action),
    ], localizedName: localized as String?);
  }

  static KeyBindingAction _action(Object? value) {
    final action = _object(value);
    final name = action['name'], bindings = action['bindings'];
    final localized = action['localizedName'];
    if (name is! String ||
        bindings is! List ||
        (localized != null && localized is! String)) {
      _bad();
    }
    return KeyBindingAction(name, [
      for (final binding in bindings) _binding(binding),
    ], localizedName: localized as String?);
  }

  static KeyBindingEntry _binding(Object? value) {
    final binding = _object(value);
    final device = binding['device'], instance = binding['instance'];
    final input = binding['input'], customized = binding['customized'];
    final multiTap = binding['multiTap'], mode = binding['mode'];
    if (!const {
          'keyboardMouse',
          'joystick',
          'gamepad',
          'unknown',
        }.contains(device) ||
        instance is! int ||
        input is! String ||
        customized is! bool ||
        (multiTap != null && multiTap is! int) ||
        (mode != null && mode is! String)) {
      _bad();
    }
    return KeyBindingEntry(
      device: device as String,
      instance: instance,
      input: input,
      customized: customized,
      multiTap: multiTap as int?,
      mode: mode as String?,
    );
  }
}
