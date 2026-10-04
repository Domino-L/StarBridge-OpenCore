import 'dart:math';

import '../bridge/bridge_client_session.dart';
import 'menu_window_preferences.dart';

/// Owned above composition/Host replacement. Consumed at actual app startup,
/// never on opening the menu or reading its settings. Contains no account data.
final class MenuStartupLifecycle {
  final String token = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String _mode = 'normal';
  String get mode => _mode;
  Future<void>? _work;
  bool _resolved = false;

  Future<void> prepare(BridgeClientSession session) async {
    if (_resolved) return;
    if (_work case final work?) return work;
    final work = _prepare(session);
    _work = work;
    try {
      await work;
    } finally {
      _work = null;
    }
  }

  Future<void> _prepare(BridgeClientSession session) async {
    if (!session.hostCapabilities.contains(
      'applicationPreferences.menu.startup',
    )) {
      _resolved = true; // Compatible old Host has no one-shot startup setting.
      return;
    }
    _mode = 'unverified';
    try {
      final reply = await session.request(
        'applicationPreferences.menu.startup',
        payload: {'schemaVersion': 1, 'token': token},
        timeout: const Duration(seconds: 3),
      );
      final data = reply.payload;
      if (data.length != 2 ||
          data['schemaVersion'] != 1 ||
          data['safe'] is! bool) {
        throw const FormatException('Invalid menu startup receipt');
      }
      _mode = data['safe'] == true ? 'safe' : 'normal';
      _resolved = true;
    } on Object {
      // Do not claim consumption or restore windows on an unknown result.
      // A later Host connection can retry the same durable receipt token.
    }
  }

  bool get protectsLayout => mode != 'normal';
  MenuWindowPreferences presentation(MenuWindowPreferences value) =>
      protectsLayout
      ? MenuWindowPreferences(value.revision, {
          ...value.layout,
          'open': <String>[],
        }, value.settings)
      : value;
  MenuWindowPreferences changes(
    MenuWindowPreferences current,
    MenuWindowPreferences proposed,
  ) => protectsLayout ? current.withSettingsPatch(proposed.settings) : proposed;
}
