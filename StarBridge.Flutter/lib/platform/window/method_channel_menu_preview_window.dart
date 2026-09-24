import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'menu_preview_window_port.dart';
import 'menu_profile_navigation.dart';
import 'menu_feature_lease.dart';
import 'menu_window_preferences.dart';

/// Uses the application's existing native menu window, not a second process.
final class MethodChannelMenuPreviewWindow implements MenuLiveWindowPort {
  MethodChannelMenuPreviewWindow({
    this.friends,
    this.comms,
    this.profiles,
    this.features = const {},
    this.preferences,
    this.contextValues,
  });
  final Map<String, MenuFeatureFactory> features;
  final MenuWindowPreferencesPort? preferences;
  final List<String> Function()? contextValues;
  Timer? _contextTimer;
  MenuWindowPreferences? _preferences;
  Map<String, Object?>? _pendingPreferences;
  bool _savingPreferences = false;
  Timer? _preferencesTimer;
  Future<void>? _preferencesWork;
  final _features = <String, MenuFeatureLease>{};
  final MenuFriendsReadLease Function(void Function(Map<String, Object?>))?
  friends;
  final MenuCommsReadLease Function(void Function(Map<String, Object?>))? comms;
  final MenuProfilesReadLease Function(void Function(Map<String, Object?>))?
  profiles;
  MenuProfilesReadLease? _profiles;
  MenuFriendsReadLease? _social;
  MenuCommsReadLease? _communications;
  int? _generation;
  int _revision = 0;
  bool _live = false, _disposed = false;
  Completer<bool>? _shown;
  static const _channel = MethodChannel('starbridge/menu-primary');
  bool _opening = false;
  @override
  bool get liveAvailable => friends != null && !_disposed;

  Future<void> _event(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'state') {
      final shown = _shown;
      if (call.arguments == 'visible' && shown != null && !shown.isCompleted) {
        shown.complete(true);
        _contextTimer?.cancel();
        _contextTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _publishContext(),
        );
        _publishContext();
      }
      if (call.arguments == 'hidden' || call.arguments == 'unavailable') {
        _preferencesTimer?.cancel();
        if (!_savingPreferences) _preferencesWork = _savePreferences();
        _contextTimer?.cancel();
        _social?.show(false);
        _communications?.show(false);
        _profiles?.hide();
        for (final feature in _features.values) {
          feature.show(false);
        }
        _generation = null;
        if (shown != null && !shown.isCompleted) shown.complete(false);
      }
    } else if (call.method == 'preferencesChanged') {
      final args = call.arguments;
      if (_live &&
          args is Map &&
          args['opening'] == _generation &&
          _generation != null &&
          args['payload'] is String &&
          (args['payload'] as String).length <= 32768) {
        try {
          final next = MenuWindowPreferences.parse(
            jsonDecode(args['payload'] as String),
          );
          if (next != null && _preferences != null) {
            final previous = _pendingPreferences ?? _preferences!.toMap();
            final immediate =
                jsonEncode(previous['settings']) != jsonEncode(next.settings) ||
                jsonEncode((previous['layout'] as Map)['open']) !=
                    jsonEncode(next.layout['open']);
            _pendingPreferences = next.toMap();
            _preferencesTimer?.cancel();
            if (immediate) {
              if (!_savingPreferences) _preferencesWork = _savePreferences();
            } else {
              _preferencesTimer = Timer(const Duration(milliseconds: 350), () {
                if (!_savingPreferences) _preferencesWork = _savePreferences();
              });
            }
          }
        } on Object {
          /* Invalid UI-only document is ignored. */
        }
      }
    } else if ((call.method == 'featureVisible' ||
            call.method == 'featureAction') &&
        _live &&
        _generation != null) {
      final args = call.arguments;
      if (args is! Map ||
          args['opening'] != _generation ||
          args['tool'] is! String ||
          !features.containsKey(args['tool'])) {
        return;
      }
      final tool = args['tool'] as String;
      if (call.method == 'featureVisible' && args['visible'] is bool) {
        if (args['visible'] == true) {
          _features.putIfAbsent(
            tool,
            () => features[tool]!(
              (view) =>
                  _publish({...view, 'tool': tool}, method: 'featureView'),
            ),
          );
        }
        _features[tool]?.show(args['visible'] as bool);
      } else if (call.method == 'featureAction' &&
          args['key'] is String &&
          (args['key'] as String).length <= 64 &&
          args['value'] is String &&
          (args['value'] as String).length <= 2048) {
        _features[tool]?.act(args['key'] as String, args['value'] as String);
      }
    } else if (call.method == 'friendsVisible' &&
        _live &&
        _generation != null) {
      final args = call.arguments;
      if (args is! Map ||
          args['opening'] != _generation ||
          args['visible'] is! bool) {
        return;
      }
      if (_social == null && args['visible'] != true) return;
      _social ??= friends!(_publish);
      _social!.show(args['visible'] as bool);
    } else if (call.method == 'commsVisible' &&
        _live &&
        _generation != null &&
        comms != null) {
      final args = call.arguments;
      if (args is! Map ||
          args['opening'] != _generation ||
          args['visible'] is! bool) {
        return;
      }
      if (_communications == null && args['visible'] != true) return;
      _communications ??= comms!((view) => _publish(view, method: 'commsView'));
      _communications!.show(args['visible'] as bool);
    } else if (call.method == 'friendsAction' && _live && _generation != null) {
      final args = call.arguments, lease = _social;
      if (lease is! MenuFriendsActionLease ||
          args is! Map ||
          args['opening'] != _generation ||
          !const {
            'prepare',
            'confirm',
            'dismiss',
            'refresh',
            'section',
            'search',
            'presence',
          }.contains(args['action']) ||
          args['key'] is! String ||
          (args['key'] as String).length > 64 ||
          args['value'] is! String ||
          (args['value'] as String).length > 128) {
        return;
      }
      (lease as MenuFriendsActionLease).act(
        args['action'] as String,
        args['key'] as String,
        args['value'] as String,
      );
    } else if (call.method == 'profileAction' && _live && _generation != null) {
      await _profile(call.arguments);
    } else if (call.method == 'commsCompose' && _live && _generation != null) {
      final args = call.arguments, lease = _communications;
      if (lease is! MenuCommsComposeLease ||
          args is! Map ||
          args['opening'] != _generation ||
          args['action'] is! String ||
          !const {'edit', 'send', 'check'}.contains(args['action']) ||
          args['key'] is! String ||
          (args['key'] as String).length > 64 ||
          args['text'] is! String ||
          (args['text'] as String).length > 1000 ||
          args['revision'] is! int ||
          (args['revision'] as int) < 0 ||
          (args['revision'] as int) > 1000000000) {
        return;
      }
      (lease as MenuCommsComposeLease).compose(
        args['action'] as String,
        args['key'] as String,
        args['text'] as String,
        args['revision'] as int,
      );
    } else if (call.method == 'commsAction' && _live && _generation != null) {
      final args = call.arguments;
      if (args is! Map ||
          args['opening'] != _generation ||
          args['action'] is! String ||
          args['key'] is! String) {
        return;
      }
      if ((args['key'] as String).length > 64) return;
      if (args['action'] == 'friend') {
        final source = _social, destination = _communications;
        if (destination is MenuChatOpener) {
          (destination as MenuChatOpener).openChat(
            source is MenuChatTargets
                ? (source as MenuChatTargets).chatTarget(args['key'] as String)
                : null,
          );
        }
      } else {
        _communications?.act(args['action'] as String, args['key'] as String);
      }
    }
  }

  void _publishContext() {
    if (!_live || _generation == null || contextValues == null || _disposed) {
      return;
    }
    final values = contextValues!();
    if (values.length != 5 || values.any((value) => value.length > 512)) return;
    unawaited(
      _send({
        'opening': _generation,
        'revision': ++_revision,
        'payload': jsonEncode(values),
      }, 'contextView'),
    );
  }

  Future<void> _savePreferences() async {
    if (_savingPreferences || preferences == null || _preferences == null) {
      return;
    }
    _savingPreferences = true;
    try {
      while (!_disposed && _pendingPreferences != null) {
        final data = _pendingPreferences!;
        _pendingPreferences = null;
        final next = MenuWindowPreferences.parse({
          ...data,
          'revision': _preferences!.revision,
        });
        if (next == null) continue;
        _preferences = await preferences!.save(next);
      }
    } on Object {
      _pendingPreferences = null;
      // Do not overwrite an externally changed document on an automatic retry.
      _preferences = null;
      if (_generation != null) {
        unawaited(
          _send({
            'opening': _generation,
            'revision': ++_revision,
            'payload': '{"failed":true}',
          }, 'preferencesState'),
        );
      }
    } finally {
      _savingPreferences = false;
    }
  }

  Future<void> _profile(Object? arguments) async {
    if (arguments is! Map ||
        arguments['opening'] != _generation ||
        arguments['window'] is! String ||
        !RegExp(r'^p[1-9][0-9]{0,8}$')
            .hasMatch(arguments['window'] as String)) {
      return;
    }
    final window = arguments['window'] as String;
    if (arguments['action'] == 'close') {
      _profiles?.closeWindow(window);
      return;
    }
    if (arguments['action'] == 'refresh') {
      _profiles?.refresh(window);
      return;
    }
    if (arguments['action'] != 'open' || arguments['key'] is! String) return;
    final owner = switch (arguments['source']) {
      'friends' => _social,
      'comms' => _communications,
      'organizations' => _features['organizations'],
      'organizationChat' => _features['organizationChat'],
      _ => null,
    };
    final key = arguments['key'] as String;
    final target = owner is MenuProfileTargets
        ? owner.profileTarget(key)
        : null;
    if (key.length > 64 ||
        target == null ||
        !target.isCurrent() ||
        profiles == null) {
      _publish({
        'window': window,
        'state': 'unavailable',
      }, method: 'profileView');
      return;
    }
    _profiles ??= profiles!((view) => _publish(view, method: 'profileView'));
    _profiles!.open(window, target);
  }

  void _publish(Map<String, Object?> view, {String method = 'friendsView'}) {
    final generation = _generation;
    if (_disposed || !_live || generation == null) return;
    unawaited(
      _send({
        'opening': generation,
        'revision': ++_revision,
        'payload': _encode(view),
      }, method),
    );
  }

  String _encode(Map<String, Object?> view) {
    final payload = jsonEncode(view);
    return utf8.encode(payload).length <= 1048576
        ? payload
        : '{"state":"unavailable"}';
  }

  Future<void> _send(Map<String, Object?> view, String method) async {
    try {
      await _channel.invokeMethod<void>(method, view);
    } on PlatformException {
      _social?.show(false);
      _communications?.show(false);
      _profiles?.hide();
      for (final feature in _features.values) {
        feature.show(false);
      }
    } on MissingPluginException {
      _social?.show(false);
      _communications?.show(false);
      _profiles?.hide();
      for (final feature in _features.values) {
        feature.show(false);
      }
    }
  }

  @override
  Future<bool> openLive({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) => liveAvailable
      ? _open(
          contextLabel: contextLabel,
          returnLabel: returnLabel,
          settingsLabel: settingsLabel,
          live: true,
        )
      : Future.value(false);

  @override
  Future<bool> open({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) => _open(
    contextLabel: contextLabel,
    returnLabel: returnLabel,
    settingsLabel: settingsLabel,
  );

  Future<bool> _open({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
    bool live = false,
  }) async {
    if (_opening || _disposed) return false;
    _opening = true;
    _social?.show(false);
    _communications?.show(false);
    _profiles?.hide();
    for (final feature in _features.values) {
      feature.show(false);
    }
    _generation = null;
    _live = live;
    final shown = Completer<bool>();
    _shown = shown;
    _channel.setMethodCallHandler(_event);
    try {
      var preferencesFailed = false;
      if (preferences != null && live) {
        try {
          _preferencesTimer?.cancel();
          await _preferencesWork;
          await _savePreferences();
          _preferences = await preferences!.read();
        } on Object {
          _preferences = null;
          preferencesFailed = true;
        }
      }
      final generation = await _channel
          .invokeMethod<int>('preview', {
            'schemaVersion': 1,
            'contextLabel': contextLabel,
            'returnLabel': returnLabel,
            'settingsLabel': settingsLabel,
            'liveFriends': live,
            'liveComms': live && comms != null,
            'liveFeatures': live && features.isNotEmpty,
            'preferences':
                ((live ? _preferences : null) ?? MenuWindowPreferences.defaults)
                    .encode(),
            'preferencesFailed': preferencesFailed,
          })
          .timeout(const Duration(seconds: 6));
      if (_disposed || generation == null || generation <= 0) return false;
      _generation = generation;
      // A successful request is not evidence that Windows revealed the menu.
      return await shown.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      try {
        await _channel
            .invokeMethod<void>('close')
            .timeout(const Duration(seconds: 1));
      } on Object {
        // Native first-frame timeout also cancels the pending opening.
      }
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      _shown = null;
      _opening = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _preferencesTimer?.cancel();
    _contextTimer?.cancel();
    _social?.dispose();
    _communications?.dispose();
    _profiles?.dispose();
    for (final feature in _features.values) {
      feature.dispose();
    }
    _generation = null;
    final shown = _shown;
    if (shown != null && !shown.isCompleted) shown.complete(false);
    _channel.setMethodCallHandler(null);
    unawaited(_detach());
  }

  Future<void> _detach() async {
    try {
      await _channel.invokeMethod<void>('detach');
    } on PlatformException {
      /* Native lifetime ended. */
    } on MissingPluginException {
      /* No native window. */
    }
  }
}
