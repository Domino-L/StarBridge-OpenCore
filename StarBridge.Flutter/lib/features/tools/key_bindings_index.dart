import '../../app/localization/app_strings.dart';
import 'key_bindings_labels.dart';
import 'key_bindings_names.dart';
import 'key_bindings_port.dart';

/// When a binding applies. A key usually means different things in each.
const keyBindingScenes = [
  'flight',
  'turret',
  'foot',
  'eva',
  'ground',
  'social',
  'other',
  'all',
];

const _sceneMaps = <String, String>{
  'seat_general': 'flight',
  'spaceship_general': 'flight',
  'vehicle_mfd': 'flight',
  'spaceship_view': 'flight',
  'spaceship_movement': 'flight',
  'spaceship_quantum': 'flight',
  'spaceship_docking': 'flight',
  'spaceship_targeting': 'flight',
  'spaceship_targeting_advanced': 'flight',
  'spaceship_target_hailing': 'flight',
  'spaceship_radar': 'flight',
  'spaceship_scanning': 'flight',
  'spaceship_mining': 'flight',
  'spaceship_salvage': 'flight',
  'spaceship_weapons': 'flight',
  'spaceship_missiles': 'flight',
  'spaceship_defensive': 'flight',
  'spaceship_power': 'flight',
  'spaceship_hud': 'flight',
  'lights_controller': 'flight',
  'turret_movement': 'turret',
  'turret_advanced': 'turret',
  'player': 'foot',
  'prone': 'foot',
  'tractor_beam': 'foot',
  'mining': 'foot',
  'incapacitated': 'foot',
  'player_choice': 'foot',
  'zero_gravity_eva': 'eva',
  'zero_gravity_traversal': 'eva',
  'vehicle_general': 'ground',
  'vehicle_driver': 'ground',
  'default': 'social',
  'ui_notification': 'social',
  'player_emotes': 'social',
  'player_input_optical_tracking': 'social',
};

String keyBindingScene(String map) => _sceneMaps[map] ?? 'other';

const _modifiers = {'lalt', 'ralt', 'lctrl', 'rctrl', 'lshift', 'rshift'};

/// One binding of one action, split into the modifiers held and the key pressed.
final class KeyBindingRef {
  KeyBindingRef(this.map, this.action, this.entry, this.name) {
    final tokens = entry.input
        .toLowerCase()
        .split('+')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final mods = tokens.where(_modifiers.contains).toList()..sort();
    var rest = tokens.where((t) => !_modifiers.contains(t)).join('+');
    // A modifier bound on its own is that key, not a layer.
    if (rest.isEmpty && mods.isNotEmpty) rest = mods.removeLast();
    key = rest;
    modifiers = mods.join('+');
  }
  final KeyBindingMap map;
  final KeyBindingAction action;
  final KeyBindingEntry entry;

  /// Display name, or null when nothing names it.
  final String? name;
  late final String key;
  late final String modifiers;
  String get scene => keyBindingScene(map.name);
  bool get isMouse =>
      key.startsWith('mouse') ||
      key.startsWith('mwheel') ||
      key.startsWith('maxis');
}

/// Every binding once, so the page can light keys without walking the file on
/// each frame. Built when a new answer or interface language arrives.
final class KeyBindingsIndex {
  KeyBindingsIndex(AppStrings strings, this.snapshot) {
    for (final map in snapshot.maps) {
      final names = keyBindingActionNames(strings, map.actions);
      actionNames[map.name] = names;
      mapNames[map.name] = keyBindingMapName(strings, map);
      for (final action in map.actions) {
        for (final entry in action.bindings) {
          if (entry.cleared) continue;
          final ref = KeyBindingRef(map, action, entry, names[action.name]);
          refs.add(ref);
          if (entry.device == 'keyboardMouse') keyboard.add(ref);
        }
      }
    }
  }
  final KeyBindingsSnapshot snapshot;
  final refs = <KeyBindingRef>[];
  final keyboard = <KeyBindingRef>[];
  final actionNames = <String, Map<String, String?>>{};
  final mapNames = <String, String>{};

  bool get hasDefaults => snapshot.defaultsVersion != null;

  static bool inScene(String map, String scene) =>
      scene == 'all' || keyBindingScene(map) == scene;

  /// Keys on the keyboard, not mouse buttons, for this scene and held modifier.
  /// A search or a build without the table lights matches on every layer.
  Map<String, List<KeyBindingRef>> keysFor({
    required String scene,
    required String layer,
    required String query,
    required bool allLayers,
    required AppStrings strings,
    bool onlyChanged = false,
  }) {
    final out = <String, List<KeyBindingRef>>{};
    for (final ref in keyboard) {
      if (ref.isMouse) continue;
      if (onlyChanged && !ref.entry.customized) continue;
      if (query.isNotEmpty) {
        if (!matches(
          strings,
          ref.action,
          ref.name,
          query,
          entries: [ref.entry],
        )) {
          continue;
        }
      } else {
        if (!inScene(ref.map.name, scene)) continue;
        if (!allLayers && ref.modifiers != layer) continue;
      }
      (out[ref.key] ??= []).add(ref);
    }
    return out;
  }

  /// How many keyboard bindings each held modifier has in this scene.
  Map<String, int> layerCounts(String scene) {
    final out = <String, int>{};
    for (final ref in keyboard) {
      if (ref.isMouse || !inScene(ref.map.name, scene)) continue;
      out[ref.modifiers] = (out[ref.modifiers] ?? 0) + 1;
    }
    return out;
  }

  /// All the actions on a key, in every scene and layer, for the opened key.
  List<KeyBindingRef> onKey(String key) => [
    for (final ref in keyboard)
      if (ref.key == key) ref,
  ];

  List<KeyBindingRef> onInput(
    String device,
    String token, {
    required String scene,
    String layer = '',
    int? instance,
  }) {
    final out = <KeyBindingRef>[];
    for (final ref in refs) {
      if (ref.entry.device != device || !inScene(ref.map.name, scene)) continue;
      if (instance != null && ref.entry.instance != instance) continue;
      if (device == 'keyboardMouse') {
        if (ref.key == token && ref.modifiers == layer) out.add(ref);
      } else if (device == 'gamepad') {
        final tokens = ref.entry.input.toLowerCase().split('+');
        final held = tokens.length > 1 && tokens.contains('shoulderl');
        if (held != (layer == 'shoulderl')) continue;
        final rest = held
            ? tokens.where((t) => t != 'shoulderl').join('+')
            : tokens.join('+');
        if (rest == token) out.add(ref);
      } else if (ref.entry.input.toLowerCase() == token) {
        out.add(ref);
      }
    }
    return out;
  }

  static String squash(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s'), '');

  /// query is already squashed.
  /// [entries]: the bindings on screen; keys are matched only among them.
  static bool matches(
    AppStrings strings,
    KeyBindingAction action,
    String? name,
    String query, {
    Iterable<KeyBindingEntry>? entries,
  }) {
    if (query.isEmpty) return true;
    if (squash(name ?? '').contains(query) ||
        squash(action.name).contains(query)) {
      return true;
    }
    return (entries ?? action.bindings).any(
      (b) =>
          squash(b.input).contains(query) ||
          squash(keyBindingLabel(strings, b)).contains(query),
    );
  }
}
