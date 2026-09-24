import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../localization/app_strings.dart';

import 'menu_overlay_theme.dart';
import 'menu_overlay_frame.dart';
import 'menu_bridge_preview.dart';
import 'menu_friends_view.dart';
import 'menu_comms_view.dart';
import 'menu_profile_view.dart';
import 'menu_feature_view.dart';
import '../../platform/window/menu_window_preferences.dart';

// Auxiliary entry point: no account/bootstrap, disk access, plugins or Host.
void runMenuOverlaySurface({bool workspacePreview = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MenuOverlaySurfaceApp(workspacePreview: workspacePreview));
}

class MenuOverlaySurfaceApp extends StatefulWidget {
  const MenuOverlaySurfaceApp({super.key, this.workspacePreview = false});
  final bool workspacePreview;

  @override
  State<MenuOverlaySurfaceApp> createState() => _MenuOverlaySurfaceAppState();
}

class _MenuOverlaySurfaceAppState extends State<MenuOverlaySurfaceApp> {
  static const _channel = MethodChannel('starbridge/menu-surface');
  int _opening = -1;
  bool _wanted = false;
  bool _workspacePreview = false;
  Map<Object?, Object?> _labels = const {};
  MenuFriendsView _friends = const MenuFriendsView('idle');
  int _friendsRevision = -1;
  Timer? _friendsAck;
  MenuCommsView _comms = const MenuCommsView('idle');
  int _commsRevision = -1;
  bool _commsDisconnected = false;
  final _profileRevisions = <String, int>{};
  final _profiles = <String, MenuProfileView>{};
  Map<String, Object?>? _windowLayout;
  final _features = <String, MenuFeatureView>{};
  final _featureRevisions = <String, int>{};
  final _featureTimers = <String, Timer>{};
  final _featureVisible = <String>{};
  MenuWindowPreferences _preferences = MenuWindowPreferences.defaults;
  bool _preferencesFailed = false;
  List<String>? _contextValues;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'snapshot') _accept(call.arguments);
      if ((call.method == 'preferencesState' || call.method == 'contextView') &&
          call.arguments is Map) {
        final args = call.arguments as Map;
        if (_wanted &&
            args['opening'] == _opening &&
            args['payload'] is String) {
          try {
            final data = jsonDecode(args['payload'] as String);
            if (call.method == 'preferencesState' &&
                data is Map &&
                data['failed'] == true) {
              setState(() => _preferencesFailed = true);
            }
            if (call.method == 'contextView' &&
                data is List &&
                data.length == 5 &&
                data.every((v) => v is String && v.length <= 512)) {
              setState(() => _contextValues = List<String>.from(data));
            }
          } on Object {
            /* Invalid presentation is ignored. */
          }
        }
      }
      if (call.method == 'featureView') {
        final data = call.arguments;
        if (data is Map &&
            _wanted &&
            _labels['liveFeatures'] == true &&
            data['opening'] == _opening &&
            data['revision'] is int) {
          final entry = MenuFeatureView.envelope(data['payload']);
          if (entry != null &&
              _featureVisible.contains(entry.$1) &&
              (data['revision'] as int) > (_featureRevisions[entry.$1] ?? -1)) {
            _featureTimers.remove(entry.$1)?.cancel();
            setState(() {
              _featureRevisions[entry.$1] = data['revision'] as int;
              _features[entry.$1] = entry.$2;
            });
          }
        }
      }
      if (call.method == 'profileView') {
        final data = call.arguments;
        if (data is Map &&
            _wanted &&
            _labels['liveFriends'] == true &&
            data['opening'] == _opening &&
            data['revision'] is int) {
          try {
            final payload = data['payload'];
            if (payload is String && utf8.encode(payload).length <= 1048576) {
              final view = jsonDecode(payload);
              if (view is Map && view['window'] is String) {
                final id = view['window'] as String;
                final revision = data['revision'] as int;
                if (_profiles.containsKey(id) &&
                    revision > (_profileRevisions[id] ?? -1)) {
                  setState(() {
                    _profileRevisions[id] = revision;
                    _profiles[id] = MenuProfileView.parse(view);
                  });
                }
              }
            }
          } on Object {
            /* Reject malformed envelopes without opening unsolicited windows. */
          }
        }
      }
      if (call.method == 'commsView') {
        final data = call.arguments;
        if (data is Map &&
            _wanted &&
            _labels['liveComms'] == true &&
            data['opening'] == _opening &&
            data['revision'] is int &&
            (data['revision'] as int) > _commsRevision) {
          setState(() {
            _commsRevision = data['revision'] as int;
            _commsDisconnected = false;
            _comms = MenuCommsView.parse(data['payload']);
          });
        }
      }
      if (call.method == 'friendsView') {
        final data = call.arguments;
        if (data is Map &&
            _wanted &&
            _labels['liveFriends'] == true &&
            data['opening'] == _opening &&
            data['revision'] is int &&
            (data['revision'] as int) > _friendsRevision) {
          setState(() {
            _friendsAck?.cancel();
            _friendsRevision = data['revision'] as int;
            _friends = MenuFriendsView.parse(data['payload']);
          });
        }
      }
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      _accept(await _channel.invokeMethod<Object?>('ready'));
    } on PlatformException {
      // The native first-frame timeout owns safe recovery; never reveal an
      // unconfigured/blank surface after a failed handshake.
    } on MissingPluginException {
      // Not a stand-alone desktop app. No fallback to the account bootstrap.
    }
  }

  void _accept(Object? value) {
    if (!mounted || value is! Map) return;
    final opening = value['opening'];
    final wanted = value['wanted'];
    if (opening is! int || opening < 0 || wanted is! bool) return;
    if (opening < _opening || (opening == _opening && !_wanted && wanted)) {
      return;
    }
    if (wanted &&
        ['contextLabel', 'returnLabel', 'settingsLabel'].any(
          (key) => value[key] is! String || (value[key] as String).isEmpty,
        )) {
      return;
    }
    final newOpening = opening != _opening;
    setState(() {
      _opening = opening;
      _wanted = wanted;
      _workspacePreview = value['workspacePreview'] == true;
      _labels = wanted ? Map<Object?, Object?>.from(value) : const {};
      if (newOpening || !wanted) {
        _contextValues = null;
        if (newOpening && wanted) {
          try {
            final prefs = value['preferences'];
            if (prefs is String && prefs.length <= 32768) {
              _preferences =
                  MenuWindowPreferences.parse(jsonDecode(prefs)) ??
                  MenuWindowPreferences.defaults;
              _windowLayout = _preferences.layout;
            }
          } on Object {
            /* Keep in-memory geometry on malformed preference data. */
          }
          _preferencesFailed = value['preferencesFailed'] == true;
        }
        for (final timer in _featureTimers.values) {
          timer.cancel();
        }
        _featureTimers.clear();
        _featureRevisions.clear();
        _features.clear();
        _featureVisible.clear();
        _friendsAck?.cancel();
        _friendsRevision = -1;
        _friends = const MenuFriendsView('idle');
        _commsRevision = -1;
        _commsDisconnected = false;
        _comms = const MenuCommsView('idle');
        _profileRevisions.clear();
        _profiles.clear();
      }
    });
    if (newOpening && wanted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wanted && _opening == opening) {
          unawaited(_notify('painted', opening));
        }
      });
    }
  }

  Future<void> _notify(String method, [Object? argument]) async {
    final opening = _opening;
    if (method == 'friendsVisible' &&
        argument is Map &&
        argument['visible'] == false) {
      _friendsAck?.cancel();
    }
    if (method == 'friendsAction') {
      _friendsAck?.cancel();
      _friendsAck = Timer(
        const Duration(seconds: 5),
        () => _friendsFailure(opening),
      );
    }
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on PlatformException {
      if (method == 'featureAction' || method == 'featureVisible') {
        _featureFailure(opening, argument);
      }
      if (method == 'friendsAction') _friendsFailure(opening);
      if (method == 'commsCompose' &&
          mounted &&
          _wanted &&
          opening == _opening) {
        setState(() => _commsDisconnected = true);
      }
      if (method == 'profileAction' &&
          mounted &&
          _wanted &&
          opening == _opening) {
        _profileFailure(argument);
      }
      // Dismiss is retryable (button/hotkey/Alt-Tab); no fake close success.
    } on MissingPluginException {
      if (method == 'featureAction' || method == 'featureVisible') {
        _featureFailure(opening, argument);
      }
      if (method == 'friendsAction') _friendsFailure(opening);
      if (method == 'commsCompose' &&
          mounted &&
          _wanted &&
          opening == _opening) {
        setState(() => _commsDisconnected = true);
      }
      if (method == 'profileAction' &&
          mounted &&
          _wanted &&
          opening == _opening) {
        _profileFailure(argument);
      }
      // Native lifetime ended. Do not launch another client to recover.
    }
  }

  void _profileFailure(Object? argument) {
    if (argument is Map && _profiles.containsKey(argument['window'])) {
      setState(
        () => _profiles[argument['window'] as String] = const MenuProfileView(
          'unavailable',
        ),
      );
    }
  }

  void _featureFailure(int opening, Object? argument) {
    if (!mounted || !_wanted || opening != _opening || argument is! Map) return;
    final tool = argument['tool'];
    if (tool is! String || !_featureVisible.contains(tool)) return;
    _featureTimers.remove(tool)?.cancel();
    setState(
      () => _features[tool] = const MenuFeatureView(
        'unavailable',
        notice: '连接中断，请刷新核对当前状态。',
      ),
    );
  }

  void _friendsFailure(int opening) {
    if (!mounted || !_wanted || opening != _opening) return;
    _friendsAck?.cancel();
    setState(
      () => _friends = MenuFriendsView(
        _friends.state,
        rows: _friends.rows,
        incoming: _friends.incoming,
        interactive: true,
        section: _friends.section,
        query: _friends.query,
        feedback: 'unknown',
        requiresRefresh: true,
      ),
    );
  }

  void _profileAction(String action, String window, String source, String key) {
    // The preview owns opaque window keys only; account references stay primary.
    if (action == 'close') {
      _profiles.remove(window);
      _profileRevisions.remove(window);
    } else if (action == 'open') {
      _profiles[window] = const MenuProfileView('loading');
    }
    unawaited(
      _notify('profileAction', {
        'opening': _opening,
        'action': action,
        'window': window,
        'source': source,
        'key': key,
      }),
    );
  }

  @override
  void dispose() {
    for (final timer in _featureTimers.values) {
      timer.cancel();
    }
    _friendsAck?.cancel();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _savePreferences() {
    if (!_wanted || _labels['preferences'] is! String) return;
    // Transfer the latest geometry while this opening is still authorized.
    // The primary engine coalesces disk writes even if Alt-Tab hides us now.
    unawaited(
      _notify('preferencesChanged', {
        'opening': _opening,
        'payload': MenuWindowPreferences(_preferences.revision, {
          ...(_windowLayout ?? _preferences.layout),
          if (_preferences.settings['restoreDesktop'] != true)
            'open': <String>[],
        }, _preferences.settings).encode(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildMenuOverlayTheme(const Locale('zh')),
    home: TickerMode(
      enabled: _wanted,
      child: (widget.workspacePreview || _workspacePreview)
          ? MenuBridgePreview(
              key: ValueKey(_opening),
              visible: _wanted,
              initialSettings: _preferences.settings,
              preferencesFailed: _preferencesFailed,
              contextValues: _contextValues,
              onSettingsChanged: (settings) {
                _preferences = MenuWindowPreferences(
                  _preferences.revision,
                  _preferences.layout,
                  settings,
                );
                _savePreferences();
              },
              localCall: _labels['nativeTools'] == true
                  ? (action, arguments) => _channel.invokeMethod<Object?>(
                      'localTool',
                      {'opening': _opening, 'action': action, ...arguments},
                    )
                  : null,
              initialLayout: _windowLayout,
              onLayoutChanged: (layout) {
                _windowLayout = layout;
                _savePreferences();
              },
              profiles: Map.unmodifiable(_profiles),
              features: Map.unmodifiable(_features),
              onFeatureVisible: _labels['liveFeatures'] == true
                  ? (tool, visible) {
                      visible
                          ? _featureVisible.add(tool)
                          : _featureVisible.remove(tool);
                      if (!visible) _featureTimers.remove(tool)?.cancel();
                      if (visible) {
                        final opening = _opening;
                        _featureTimers[tool] = Timer(
                          const Duration(seconds: 18),
                          () => _featureFailure(opening, {'tool': tool}),
                        );
                      }
                      unawaited(
                        _notify('featureVisible', {
                          'opening': _opening,
                          'tool': tool,
                          'visible': visible,
                        }),
                      );
                    }
                  : null,
              onFeatureAction: _labels['liveFeatures'] == true
                  ? (tool, key, value) {
                      _featureTimers.remove(tool)?.cancel();
                      final opening = _opening;
                      _featureTimers[tool] = Timer(
                        const Duration(seconds: 5),
                        () {
                          if (mounted && _wanted && _opening == opening) {
                            setState(
                              () => _features[tool] = const MenuFeatureView(
                                'unavailable',
                                notice: '操作结果未确认，请刷新核对。',
                              ),
                            );
                          }
                        },
                      );
                      unawaited(
                        _notify('featureAction', {
                          'opening': _opening,
                          'tool': tool,
                          'key': key,
                          'value': value,
                        }),
                      );
                    }
                  : null,
              onProfileAction: _labels['liveFriends'] == true
                  ? _profileAction
                  : null,
              friends: _labels['liveFriends'] == true ? _friends : null,
              comms: _labels['liveComms'] == true ? _comms : null,
              commsDisconnected: _commsDisconnected,
              onCommsVisible: _labels['liveComms'] == true
                  ? (visible) => unawaited(
                      _notify('commsVisible', {
                        'opening': _opening,
                        'visible': visible,
                      }),
                    )
                  : null,
              onCommsAction: _labels['liveComms'] == true
                  ? (action, key) => unawaited(
                      _notify('commsAction', {
                        'opening': _opening,
                        'action': action,
                        'key': key,
                      }),
                    )
                  : null,
              onCommsCompose: _labels['liveComms'] == true
                  ? (action, key, text, revision) => unawaited(
                      _notify('commsCompose', {
                        'opening': _opening,
                        'action': action,
                        'key': key,
                        'text': text,
                        'revision': revision,
                      }),
                    )
                  : null,
              onFriendsVisible: _labels['liveFriends'] == true
                  ? (visible) => unawaited(
                      _notify('friendsVisible', {
                        'opening': _opening,
                        'visible': visible,
                      }),
                    )
                  : null,
              onFriendsAction: _labels['liveFriends'] == true
                  ? (action, key, value) => unawaited(
                      _notify('friendsAction', {
                        'opening': _opening,
                        'action': action,
                        'key': key,
                        'value': value,
                      }),
                    )
                  : null,
              onDismiss: () => unawaited(_notify('dismiss')),
            )
          : !_wanted
          ? const SizedBox.expand()
          : CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    unawaited(_notify('dismiss')),
              },
              child: Focus(
                autofocus: true,
                child: MenuOverlayFrame(
                  contextLabel: _labels['contextLabel']! as String,
                  returnLabel: _labels['returnLabel']! as String,
                  settingsLabel: _labels['settingsLabel']! as String,
                  onReturn: () => unawaited(_notify('dismiss')),
                  tools: const [],
                ),
              ),
            ),
    ),
  );
}
