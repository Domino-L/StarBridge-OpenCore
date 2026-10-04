import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../menu_overlay/menu_friends_session.dart';
import '../preferences/app_preferences_port.dart';
import '../social_windows/window_presentation.dart';
import '../../platform/window/menu_preview_window_port.dart';
import '../../platform/window/menu_profile_navigation.dart';

/// One authenticated primary-engine lease; the auxiliary engine only renders
/// bounded snapshots and returns opaque UI keys. No second Host or account.
final class FriendsWindowBinding {
  FriendsWindowBinding({
    required MenuFriendsSession Function(void Function(Map<String, Object?>))
    create,
    required this.openChat,
    required this.openMessages,
    required this.openProfile,
    this.preferences,
    this.channel = const MethodChannel('starbridge/friends-primary'),
  }) {
    _session = create(_publish);
    channel.setMethodCallHandler(_receive);
    preferences?.projection.addListener(_presentationChanged);
  }

  final MethodChannel channel;
  final AppPreferencesPort? preferences;
  final Future<void> Function(MenuChatTarget, bool Function()) openChat;
  final Future<void> Function(bool Function()) openMessages;
  final Future<void> Function(MenuProfileTarget) openProfile;
  late final MenuFriendsSession _session;
  bool _disposed = false, _visible = false, _openingNow = false;
  int _opening = 0, _revision = 0;
  Map<String, Object?> _view = const {'state': 'idle'};
  Map<String, Object?> get _snapshot => {
    'opening': _opening,
    'revision': _revision,
    if (preferences != null)
      'presentation': encodeWindowPresentation(preferences!.projection.value.effective),
    'view': jsonEncode(_view),
  };

  Future<bool> open() async {
    if (_disposed) return false;
    if (_openingNow) return true;
    _openingNow = true;
    if (!_visible) {
      _opening++;
      _visible = true;
      _session.show(true);
    }
    try {
      final shown = await channel.invokeMethod<bool>('show', _snapshot) == true;
      if (!shown && !_disposed) _hide();
      return shown;
    } on PlatformException {
      _hide();
      return false;
    } on MissingPluginException {
      _hide();
      return false;
    } finally {
      _openingNow = false;
    }
  }

  void _publish(Map<String, Object?> view) {
    if (_disposed) return;
    _view = view;
    _revision++;
    unawaited(_notify('snapshot', _snapshot));
  }

  void _presentationChanged() => _publish(_view);

  Future<void> _notify(String method, [Object? value]) async {
    try {
      await channel.invokeMethod<void>(method, value);
    } on PlatformException {
      // Closing/replacing the primary shell must never replay a command.
    } on MissingPluginException {
      // Non-Windows tests and preview shells use the ordinary friends page.
    }
  }

  void _hide() {
    _visible = false;
    _session.show(false);
  }

  Future<Object?> _receive(MethodCall call) async {
    final args = call.arguments;
    if (_disposed || args is! Map || args['opening'] != _opening) return false;
    if (call.method == 'hidden') {
      _hide();
      return true;
    }
    if (call.method != 'action' ||
        !_visible ||
        args['revision'] != _revision ||
        args['scope'] != _view['scope']) {
      return false;
    }
    final action = args['action'], key = args['key'], value = args['value'];
    if (action is! String ||
        key is! String ||
        value is! String ||
        action.length > 32 ||
        key.length > 128 ||
        value.length > 128) {
      return false;
    }
    final opening = _opening, scope = _view['scope'];
    bool current() =>
        !_disposed &&
        _visible &&
        opening == _opening &&
        scope == _view['scope'];
    if (action == 'chat') {
      final target = _session.chatTarget(key);
      if (target == null) return false;
      await openChat(target, current);
    } else if (action == 'messages') {
      await openMessages(current);
    } else if (action == 'profile') {
      final target = _session.profileTarget(key);
      if (target == null) return false;
      await openProfile(target);
    } else {
      _session.act(action, key, value);
    }
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visible = false;
    channel.setMethodCallHandler(null);
    preferences?.projection.removeListener(_presentationChanged);
    _session.dispose();
    unawaited(_notify('detach'));
  }
}
