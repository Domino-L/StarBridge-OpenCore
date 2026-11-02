import 'dart:async';

import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_window_preferences.dart';

/// Coalesces layout transfer to the primary engine. A drag reports every
/// pointer event (hundreds per second); each transfer encodes the whole
/// preference document and crosses both engines on the shared platform
/// thread. The first change is sent at once, later ones at most once per
/// [interval], and the trailing send always carries the final geometry.
final class MenuLayoutSync {
  MenuLayoutSync(
    this._send, {
    this.interval = const Duration(milliseconds: 16),
  });
  final void Function() _send;
  final Duration interval;
  Timer? _window;
  var _dirty = false;

  void changed() {
    if (_window != null) {
      _dirty = true;
      return;
    }
    _send();
    _window = Timer(interval, () {
      _window = null;
      if (!_dirty) return;
      _dirty = false;
      changed();
    });
  }

  void cancel() {
    _window?.cancel();
    _window = null;
    _dirty = false;
  }

  /// Display-only document for one opening; never contains scope IDs.
  static String payload(
    MenuWindowPreferences preferences,
    Map<String, Object?>? layout,
  ) => MenuWindowPreferences(preferences.revision, {
    ...(layout ?? preferences.layout),
    if (!MenuRestorePreferences.fromSettings(preferences.settings)!
        .remembersWindows)
      'open': <String>[],
  }, preferences.settings).encode();
}
