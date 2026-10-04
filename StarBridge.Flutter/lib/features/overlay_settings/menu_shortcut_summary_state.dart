import 'package:flutter/foundation.dart';

import '../../platform/window/menu_shortcut_settings.dart';

/// Shares the existing settings port between the header and shortcut editor.
/// No polling, persistence, retries or independent keyboard registration.
final class MenuShortcutSummaryState extends ChangeNotifier
    implements MenuShortcutSettingsPort {
  MenuShortcutSummaryState(this.port);
  final MenuShortcutSettingsPort port;
  MenuShortcutSettings? value;
  Future<MenuShortcutSettings>? _reading;
  bool _closed = false;
  int _epoch = 0;

  @override
  Future<MenuShortcutSettings> readShortcut() => _reading ??= _read();

  Future<MenuShortcutSettings> _read() async {
    final epoch = ++_epoch;
    try {
      final result = await port.readShortcut();
      if (!_closed && epoch == _epoch) {
        value = result;
        notifyListeners();
      }
      return result;
    } on Object {
      if (!_closed && epoch == _epoch) {
        value = null;
        notifyListeners();
      }
      rethrow;
    } finally {
      _reading = null;
    }
  }

  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings draft) async {
    final epoch = ++_epoch;
    final result = await port.saveShortcut(draft);
    if (!_closed && epoch == _epoch) {
      value = result;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _closed = true;
    value = null;
    super.dispose();
  }
}
