import 'dart:convert';

import '../bridge/bridge_client_session.dart';

class MenuWindowPreferences {
  const MenuWindowPreferences(this.revision, this.layout, this.settings);
  final int revision;
  final Map<String, Object?> layout, settings;
  static const panelIds = {
    'friends',
    'comms',
    'organizations',
    'rooms',
    'hud',
    'screenshot',
    'image',
    'browser',
    'settings',
  };
  static const defaults = MenuWindowPreferences(
    0,
    {'version': 1, 'panels': [], 'open': []},
    {
      'showClock': true,
      'showContext': true,
      'dimming': 133 / 255,
      'restoreDesktop': false,
      'snapWindows': false,
    },
  );
  static MenuWindowPreferences? parse(Object? raw) {
    if (raw is! Map ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0) {
      return null;
    }
    final layout = raw['layout'], settings = raw['settings'];
    if (layout is! Map ||
        settings is! Map ||
        layout.length != 3 ||
        settings.keys.any(
          (key) => !const {
            'showClock',
            'showContext',
            'dimming',
            'restoreDesktop',
            'snapWindows',
          }.contains(key),
        ) ||
        layout['version'] != 1 ||
        layout['open'] is! List ||
        layout['panels'] is! List) {
      return null;
    }
    final panels = layout['panels'] as List;
    final open = layout['open'] as List;
    if (open.length > panelIds.length ||
        open.any((id) => !panelIds.contains(id)) ||
        open.toSet().length != open.length ||
        (open.isNotEmpty && settings['restoreDesktop'] != true) ||
        const [
          'restoreDesktop',
          'snapWindows',
        ].any((key) => settings.containsKey(key) && settings[key] is! bool)) {
      return null;
    }
    if (panels.length > 9 ||
        settings['showClock'] is! bool ||
        settings['showContext'] is! bool ||
        settings['dimming'] is! num) {
      return null;
    }
    final dim = settings['dimming'] as num;
    if (!dim.isFinite || dim < .3 || dim > .9) return null;
    final ids = <String>{};
    for (final panel in panels) {
      if (panel is! Map ||
          panel.length != 2 ||
          !panelIds.contains(panel['id']) ||
          !ids.add(panel['id'] as String)) {
        return null;
      }
      final bounds = panel['bounds'];
      if (bounds is! List || bounds.length != 4) return null;
      for (var i = 0; i < 4; i++) {
        final n = bounds[i];
        if (n is! num ||
            !n.isFinite ||
            n.abs() > 1000000 ||
            (i >= 2 && n <= 0)) {
          return null;
        }
      }
    }
    return MenuWindowPreferences(
      raw['revision'] as int,
      Map<String, Object?>.from(layout),
      Map<String, Object?>.from(settings),
    );
  }

  Map<String, Object?> toMap() => {
    'revision': revision,
    'layout': layout,
    'settings': settings,
  };
  String encode() => jsonEncode(toMap());
}

abstract interface class MenuWindowPreferencesPort {
  Future<MenuWindowPreferences> read();
  Future<MenuWindowPreferences> save(MenuWindowPreferences value);
}

final class BridgeMenuWindowPreferences implements MenuWindowPreferencesPort {
  const BridgeMenuWindowPreferences(this.session);
  final BridgeClientSession session;
  @override
  Future<MenuWindowPreferences> read() async {
    final result = await session.request(
      'applicationPreferences.menu.get',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 3),
    );
    return MenuWindowPreferences.parse(result.payload) ??
        (throw const FormatException('Invalid menu preferences'));
  }

  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async {
    final result = await session.request(
      'applicationPreferences.menu.update',
      payload: {
        'schemaVersion': 1,
        'expectedRevision': value.revision,
        'layout': value.layout,
        'settings': value.settings,
      },
      timeout: const Duration(seconds: 3),
    );
    return MenuWindowPreferences.parse(result.payload) ??
        (throw const FormatException('Invalid menu preferences'));
  }
}
