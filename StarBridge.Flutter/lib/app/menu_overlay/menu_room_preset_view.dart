import '../../features/party_rooms/room_preset_port.dart';

/// Only opaque actions and user-facing names cross into the menu renderer.
final class MenuRoomPresetView {
  const MenuRoomPresetView({
    required this.revision,
    required this.loaded,
    required this.choices,
    this.open,
    this.clear,
    this.draftName,
    this.error,
  });
  final int revision;
  final bool loaded;
  final List<RoomPresetChoice> choices;
  final String? open, clear, draftName, error;

  static MenuRoomPresetView? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map ||
        raw.keys.any(
          (key) => !const {
            'revision',
            'loaded',
            'choices',
            'open',
            'clear',
            'draftName',
            'error',
          }.contains(key),
        ) ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        raw['loaded'] is! bool ||
        raw['choices'] is! List ||
        (raw['choices'] as List).length > 256) {
      throw const FormatException();
    }
    String? action(Object? value) {
      if (value == null) return null;
      if (value is! String || !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(value)) {
        throw const FormatException();
      }
      return value;
    }

    String? name(Object? value) {
      if (value == null) return null;
      if (value is! String || value.length > 512) throw const FormatException();
      return value;
    }

    if (raw['error'] != null && raw['error'] != 'unavailable') {
      throw const FormatException();
    }
    return MenuRoomPresetView(
      revision: raw['revision'] as int,
      loaded: raw['loaded'] as bool,
      open: action(raw['open']),
      clear: action(raw['clear']),
      draftName: name(raw['draftName']),
      error: raw['error'] as String?,
      choices: [
        for (final choice in raw['choices'] as List)
          if (choice is Map &&
              choice.keys.every((key) => key == 'name' || key == 'action'))
            RoomPresetChoice(
              action(choice['action']) ?? (throw const FormatException()),
              name(choice['name']) ?? (throw const FormatException()),
            )
          else
            throw const FormatException(),
      ],
    );
  }
}
