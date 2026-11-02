import '../../features/overlay_settings/overlay_workspace_layout_item.dart';

/// Wire view of the in-game quick-adjust panel. The primary engine owns all
/// workspace state; this only carries display rows and the action keys the
/// menu may send back through the `hud` feature.
const menuHudQuickModules = [
  'Notice',
  'Squads',
  'Members',
  'Chat',
  'Events',
  'Crosshair',
];

typedef MenuHudQuickPreset = ({
  String id,
  String name,
  String bound,
  bool active,
});
typedef MenuHudQuickSource = ({String id, String label, bool enabled});
typedef MenuHudQuickNote = ({
  String kind,
  Map<String, String> args,
  bool ok,
  bool undo,
});

final class MenuHudQuickView {
  const MenuHudQuickView({
    required this.available,
    required this.editable,
    required this.dirty,
    required this.hotkey,
    required this.presetName,
    required this.presets,
    required this.modules,
    this.source,
    this.note,
    this.placing = false,
    this.placeResult = '',
    this.presetId = '',
    this.canUndo = false,
    this.canRedo = false,
    this.layout = const [],
    this.eventSide = 'Right',
    this.eventY = 0.3,
  });

  /// Placement mode: the menu shows only the on-screen editing layer.
  final bool placing, canUndo, canRedo;
  final String placeResult, presetId, eventSide;
  final double eventY;
  final List<OverlayWorkspaceLayoutItem> layout;

  final bool available, editable, dirty;
  final String hotkey, presetName;
  final List<MenuHudQuickPreset> presets;
  final Map<String, bool> modules;
  final ({
    String current,
    String label,
    String origin,
    bool canChange,
    List<MenuHudQuickSource> options,
  })?
  source;
  final MenuHudQuickNote? note;

  static const _origins = {'auto', 'account', 'preset', 'temporary'};
  static const _notes = {
    'hudOn',
    'hudOff',
    'preset',
    'presetBound',
    'source',
    'shown',
    'hidden',
    'undone',
    'failed',
  };

  static Map<String, String> _args(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map || raw.length > 4) throw const FormatException();
    final args = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.value as String).length > 160) {
        throw const FormatException();
      }
      args[entry.key as String] = entry.value as String;
    }
    return args;
  }

  static MenuHudQuickView? parse(Object? value) {
    if (value == null) return null;
    if (value is! Map) throw const FormatException();
    String text(Map map, String key, int max) {
      final v = map[key] ?? '';
      if (v is! String || v.length > max) throw const FormatException();
      return v;
    }

    bool flag(Map map, String key) {
      final v = map[key] ?? false;
      if (v is! bool) throw const FormatException();
      return v;
    }

    final rawPresets = value['presets'] ?? const [];
    if (rawPresets is! List || rawPresets.length > 64) {
      throw const FormatException();
    }
    final ids = <String>{};
    final presets = [
      for (final entry in rawPresets)
        if (entry is Map && ids.add(text(entry, 'id', 64)))
          (
            id: text(entry, 'id', 64),
            name: text(entry, 'name', 64),
            bound: text(entry, 'bound', 128),
            active: flag(entry, 'active'),
          )
        else
          throw const FormatException(),
    ];
    final rawModules = value['modules'] ?? const {};
    if (rawModules is! Map) throw const FormatException();
    final modules = <String, bool>{};
    for (final key in menuHudQuickModules) {
      if (rawModules[key] case final bool visible) modules[key] = visible;
    }
    if (rawModules.keys.any((key) => !menuHudQuickModules.contains(key))) {
      throw const FormatException();
    }
    final rawSource = value['source'];
    final source = switch (rawSource) {
      null => null,
      Map() => (
        current: text(rawSource, 'current', 160),
        label: text(rawSource, 'label', 160),
        origin: _origins.contains(rawSource['origin'])
            ? rawSource['origin'] as String
            : throw const FormatException(),
        canChange: flag(rawSource, 'canChange'),
        options: switch (rawSource['options'] ?? const []) {
          final List list when list.length <= 80 => [
            for (final option in list)
              if (option is Map)
                (
                  id: text(option, 'id', 160),
                  label: text(option, 'label', 160),
                  enabled: flag(option, 'enabled'),
                )
              else
                throw const FormatException(),
          ],
          _ => throw const FormatException(),
        },
      ),
      _ => throw const FormatException(),
    };
    final rawNote = value['note'];
    final note = switch (rawNote) {
      null => null,
      Map() when _notes.contains(rawNote['kind']) => (
        kind: rawNote['kind'] as String,
        args: _args(rawNote['args']),
        ok: flag(rawNote, 'ok'),
        undo: flag(rawNote, 'undo'),
      ),
      _ => throw const FormatException(),
    };
    return MenuHudQuickView(
      available: flag(value, 'available'),
      editable: flag(value, 'editable'),
      dirty: flag(value, 'dirty'),
      hotkey: text(value, 'hotkey', 64),
      presetName: text(value, 'presetName', 64),
      presets: List.unmodifiable(presets),
      modules: Map.unmodifiable(modules),
      source: source,
      note: note,
      placing: flag(value, 'placing'),
      placeResult:
          const {
            '',
            'saved',
            'cancelled',
            'failed',
          }.contains(value['placeResult'] ?? '')
          ? (value['placeResult'] ?? '') as String
          : throw const FormatException(),
      presetId: text(value, 'presetId', 64),
      canUndo: flag(value, 'canUndo'),
      canRedo: flag(value, 'canRedo'),
      layout: switch (value['layout'] ?? const []) {
        final List list when list.length <= 8 => List.unmodifiable([
          for (final item in list)
            if (item is Map)
              OverlayWorkspaceLayoutItem.fromMap(item.cast<String, Object?>())
            else
              throw const FormatException(),
        ]),
        _ => throw const FormatException(),
      },
      eventSide: switch ((value['events'] as Map?)?['side'] ?? 'Right') {
        'Left' => 'Left',
        'Right' => 'Right',
        _ => throw const FormatException(),
      },
      eventY: switch ((value['events'] as Map?)?['y'] ?? 0.3) {
        final num y when y.isFinite && y >= 0 && y <= 1 => y.toDouble(),
        _ => throw const FormatException(),
      },
    );
  }
}
