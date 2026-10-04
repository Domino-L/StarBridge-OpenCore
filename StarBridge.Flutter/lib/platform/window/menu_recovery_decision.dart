import 'package:flutter/services.dart';

import 'menu_window_preferences.dart';

/// Consent gate for one opening. Owns retries and interrupted decisions, but
/// delegates persistence to the existing revision-checked preference owner.
final class MenuRecoveryDecision {
  bool pending = false;
  bool _busy = false;
  int _epoch = 0;
  String? _choice;
  MenuWindowPreferences? _reply;

  void reset(bool value) {
    ++_epoch;
    pending = value;
    _busy = false;
    _choice = null;
    _reply = null;
  }

  Future<MenuWindowPreferences> choose({
    required Object? arguments,
    required int? opening,
    required bool Function() isCurrent,
    required MenuWindowPreferences? current,
    required MenuWindowPreferencesPort? preferences,
  }) async {
    if (!isCurrent() ||
        _busy ||
        arguments is! Map ||
        arguments.length != 2 ||
        arguments['opening'] != opening ||
        current == null ||
        !const {'restore', 'startClean'}.contains(arguments['action'])) {
      throw PlatformException(code: 'menuRecovery.session_unavailable');
    }
    if (!pending) {
      // An acknowledgment can be lost: retry this choice, not its disk write.
      if (arguments['action'] == _choice && _reply != null) return _reply!;
      throw PlatformException(code: 'menuRecovery.session_unavailable');
    }
    final epoch = _epoch;
    _busy = true;
    try {
      var value = current;
      if (arguments['action'] == 'startClean') {
        if (preferences == null) {
          throw const FormatException('No preferences owner');
        }
        value = await preferences.save(
          MenuWindowPreferences(value.revision, {
            ...value.layout,
            'open': <String>[],
          }, value.settings),
        );
      }
      if (!isCurrent() || epoch != _epoch) {
        throw PlatformException(code: 'menuRecovery.session_unavailable');
      }
      pending = false;
      _choice = arguments['action'] as String;
      return _reply = value;
    } on PlatformException {
      rethrow;
    } on Object {
      throw PlatformException(code: 'menuRecovery.unavailable');
    } finally {
      if (epoch == _epoch) _busy = false;
    }
  }
}
