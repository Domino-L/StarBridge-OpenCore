import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'menu_preview_window_port.dart';
import 'menu_action_validation.dart';
import 'menu_profile_navigation.dart';
import 'menu_feature_lease.dart';
import 'menu_window_preferences.dart';
import 'menu_screenshot_directory.dart';
import 'menu_screenshot_directory_request.dart';
import 'menu_hotkey_port.dart';
import 'menu_shortcut_settings.dart';
import 'menu_shortcut_request.dart';
import 'menu_browser_resume.dart';
import 'menu_browser_resume_request.dart';
import 'menu_attention.dart';
import 'menu_notice.dart';
import 'menu_live_presentation_feeds.dart';
import 'menu_recovery.dart';
import 'menu_recovery_decision.dart';
import 'menu_recovery_lifecycle.dart';
import 'menu_startup_lifecycle.dart';
import '../bridge/bridge_client_session.dart';

/// Owned by the primary application runtime and shared by its compositions.
/// Contains no account data; a replaced composition cannot clear the next one.
final class MenuWindowLifetime {
  MethodChannelMenuPreviewWindow? _owner;
  int _nextRequest = 0;
  final _recovery = MenuRecoveryLifecycle();
  final startup = MenuStartupLifecycle();
  Future<void> prepareStartup(BridgeClientSession session) =>
      startup.prepare(session);

  /// Explicit normal application exit only, never hide, logout or disposal.
  Future<void> completeExit() async {
    try {
      final owner = _owner;
      if (owner != null && !owner._disposed) {
        owner._preferencesTimer?.cancel();
        await owner._preferencesWork;
        await owner._savePreferences();
        if (owner.preferences != null && owner._preferences == null) return;
      }
      await _recovery.finish();
    } on Object {
      // A failed flush/confirmation remains interrupted. Do not block exit.
    }
  }
}

/// Uses the application's existing native menu window, not a second process.
final class MethodChannelMenuPreviewWindow
    implements
        MenuLiveWindowPort,
        MenuNoticeDeliveryOwner,
        MenuWindowStartupPort,
        MenuShortcutSettingsProvider,
        MenuBrowserResumeProvider,
        MenuWindowPreferencesProvider,
        MenuScreenshotDirectoryProvider {
  MethodChannelMenuPreviewWindow({
    required this.lifetime,
    this.friends,
    this.comms,
    this.profiles,
    this.features = const {},
    this.preferences,
    this.contextValues,
    this.hotkeys,
    this.hotkeyLabels,
    this.attention,
    this.notices,
    this.recovery,
    MenuBrowserResumePort? browserResume,
    MenuScreenshotDirectoryPort? screenshotDirectory,
    this.browserResumeProvider,
    this.screenshotDirectoryProvider,
    // Preserve the existing public constructor argument names for callers.
    // ignore: prefer_initializing_formals
  }) : _browserResume = browserResume,
       // ignore: prefer_initializing_formals
       _screenshotDirectory = screenshotDirectory;
  final MenuWindowLifetime lifetime;
  final MenuRecoveryPort? recovery;
  @override
  MenuBrowserResumePort? get browserResume =>
      browserResumeProvider?.call() ?? _browserResume;
  @override
  MenuScreenshotDirectoryPort? get screenshotDirectory =>
      screenshotDirectoryProvider?.call() ?? _screenshotDirectory;
  final MenuBrowserResumePort? _browserResume;
  final MenuScreenshotDirectoryPort? _screenshotDirectory;
  final MenuBrowserResumePort? Function()? browserResumeProvider;
  final MenuScreenshotDirectoryPort? Function()? screenshotDirectoryProvider;
  late final _screenshotRequests = MenuScreenshotDirectoryRequest(
    null,
    sourceProvider: () => screenshotDirectory,
  );
  final _recoveryDecision = MenuRecoveryDecision();
  bool get _recoveryPending => _recoveryDecision.pending;
  set _recoveryPending(bool value) => _recoveryDecision.reset(value);
  final MenuHotkeyPort? hotkeys;
  @override
  MenuShortcutSettingsPort? get shortcutSettings =>
      hotkeys is MenuShortcutSettingsPort
      ? hotkeys as MenuShortcutSettingsPort
      : null;
  final MenuOpenLabels Function()? hotkeyLabels;
  final MenuAttentionSource Function()? attention;
  final MenuNoticeSource Function()? notices;
  final _feeds = MenuLivePresentationFeeds();
  @override
  bool get menuNoticeDeliveryActive =>
      _ownsChannel && _live && _generation != null && _feeds.hasNotices;
  Future<void> _windowStateWork = Future.value();
  @override
  void initialize() => hotkeys?.initialize(
    () => ++lifetime._nextRequest,
    _hotkey,
    _revokeHotkeySession,
  );

  void _revokeHotkeySession() {
    _suspend();
    _live = false;
    final shown = _shown;
    if (shown != null && !shown.isCompleted) shown.complete(false);
    if (_ownsChannel) {
      lifetime._owner = null;
      _channel.setMethodCallHandler(null);
    }
    if (_request != null) unawaited(_detach(_request));
  }

  Future<void> _hotkey(MenuHotkeyIntent intent) async {
    if (_disposed || !liveAvailable) return;
    if (intent.action == 'close') {
      if (_ownsChannel && _request == intent.request) {
        await _channel.invokeMethod<void>('close', {'request': _request});
      }
    } else if (intent.action == 'open' &&
        intent.targetWindow > 0 &&
        intent.targetProcessId > 0) {
      final labels = hotkeyLabels?.call();
      if (labels == null) return;
      await _open(
        contextLabel: labels.contextLabel,
        returnLabel: labels.returnLabel,
        settingsLabel: labels.settingsLabel,
        live: true,
        target: intent,
      );
    }
  }

  Future<void> _reportWindow(int request, String phase, [int handle = 0]) {
    return _windowStateWork = _windowStateWork
        .then((_) async {
          if (!_disposed) await hotkeys?.window(request, phase, handle);
        })
        .catchError((Object _) {});
  }

  final Map<String, MenuFeatureFactory> features;
  final MenuWindowPreferencesPort? preferences;
  @override
  MenuWindowPreferencesPort? get menuPreferences => preferences;
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
  int? _request;
  bool get _ownsChannel => identical(lifetime._owner, this);
  bool _opening = false;
  @override
  bool get liveAvailable => friends != null && !_disposed;

  bool _currentOpening(int? generation, int? request) =>
      !_disposed &&
      _ownsChannel &&
      _live &&
      generation != null &&
      generation == _generation &&
      request == _request;

  Future<Object?> _handleMethod(MethodCall call) async {
    final generation = _generation, request = _request;
    bool current() => _currentOpening(generation, request);
    if (call.method == 'screenshotDirectory' ||
        call.method == 'screenshotDestination') {
      return _screenshotRequests.dispatch(
        method: call.method,
        arguments: call.arguments,
        opening: generation,
        isCurrent: current,
      );
    }
    if (call.method == 'browserResume') {
      return MenuBrowserResumeRequest.handle(
        arguments: call.arguments,
        opening: generation,
        isCurrent: current,
        port: browserResume,
      );
    }
    if (call.method == 'recoveryAction') {
      final value = await _recoveryDecision.choose(
        arguments: call.arguments,
        opening: generation,
        current: _preferences,
        preferences: preferences,
        isCurrent: current,
      );
      _preferences = value;
      lifetime._recovery.resolved();
      return value.encode();
    }
    if (call.method == 'shortcutSettings') {
      return MenuShortcutRequest.handle(
        arguments: call.arguments,
        opening: generation,
        isCurrent: current,
        port: shortcutSettings,
        afterSave: () async {
          // Shortcut and geometry share one persisted CAS revision.
          if (preferences != null && current()) {
            final refreshed = await preferences!.read();
            if (current()) _preferences = refreshed;
          }
        },
      );
    }
    await _event(call);
    return null;
  }

  Future<void> _event(MethodCall call) async {
    if (_disposed || !_ownsChannel) return;
    if (call.method == 'state') {
      final args = call.arguments;
      if (args is! Map || args['request'] != _request || _request == null) {
        return;
      }
      final state = args['state'];
      if (state == 'visible') {
        unawaited(
          _reportWindow(
            _request!,
            'visible',
            args['window'] is int ? args['window'] as int : 0,
          ),
        );
      }
      if (state == 'hidden' || state == 'unavailable') {
        unawaited(_reportWindow(_request!, 'closed'));
      }
      final shown = _shown;
      if (state == 'visible' && shown != null && !shown.isCompleted) {
        shown.complete(true);
        _startAttention();
        _contextTimer?.cancel();
        _contextTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _publishContext(),
        );
        _publishContext();
      }
      if (state == 'hidden' || state == 'unavailable') {
        _preferencesTimer?.cancel();
        if (!_savingPreferences) _preferencesWork = _savePreferences();
        _suspend();
        if (shown != null && !shown.isCompleted) shown.complete(false);
      }
    } else if (call.method == 'preferencesChanged') {
      final args = call.arguments;
      if (_live &&
          !_recoveryPending &&
          args is Map &&
          args['opening'] == _generation &&
          _generation != null &&
          args['payload'] is String &&
          (args['payload'] as String).length <= 32768) {
        try {
          final proposed = MenuWindowPreferences.parse(
            jsonDecode(args['payload'] as String),
          );
          if (proposed != null && _preferences != null) {
            final next = lifetime.startup.changes(_preferences!, proposed);
            final previous = _pendingPreferences ?? _preferences!.toMap();
            if (jsonEncode(previous) == jsonEncode(next.toMap())) return;
            final immediate =
                jsonEncode(previous['settings']) != jsonEncode(next.settings) ||
                jsonEncode((previous['layout'] as Map)['open']) !=
                    jsonEncode(next.layout['open']);
            _pendingPreferences = next.toMap();
            _feeds.updateSettings(next.settings);
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
    } else if (_recoveryPending) {
      // No account reads or actions are authorized before recovery consent.
      return;
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
        if (tool == 'hud' && args['key'] == 'toggle' && args['value'] == '') {
          _features.putIfAbsent(
            tool,
            () => features[tool]!(
              (view) =>
                  _publish({...view, 'tool': tool}, method: 'featureView'),
            ),
          );
        }
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
      _feeds.bindAvatars(_social, _preferences?.settings);
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
      _feeds.bindAvatars(_communications, _preferences?.settings);
      _communications!.show(args['visible'] as bool);
    } else if (call.method == 'friendsAction' && _live && _generation != null) {
      final args = call.arguments, lease = _social;
      if (lease is! MenuFriendsActionLease ||
          args is! Map ||
          !validMenuFriendsAction(args, _generation)) {
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
          !validMenuCommsCompose(args, _generation)) {
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
    if (!_ownsChannel ||
        !_live ||
        _generation == null ||
        contextValues == null ||
        _disposed) {
      return;
    }
    final payload = MenuLivePresentationFeeds.contextPayload(contextValues!());
    if (payload == null) return;
    unawaited(
      _send({
        'opening': _generation,
        'revision': ++_revision,
        'payload': payload,
      }, 'contextView'),
    );
  }

  void _startAttention() {
    final generation = _generation;
    if (!_ownsChannel || !_live || generation == null || _disposed) return;
    _feeds.start(
      attention: attention,
      notices: notices,
      settings: _preferences?.settings,
      visibleConversationKey: () => switch (_communications) {
        MenuConversationVisibility reader => reader.visibleConversationKey,
        _ => null,
      },
      isCurrent: () =>
          !_disposed && _ownsChannel && _live && _generation == generation,
      publish: (value, method) => _publish(value, method: method),
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
    if (_disposed || !_ownsChannel || !_live || generation == null) return;
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
      _feeds.stop();
      _social?.show(false);
      _communications?.show(false);
      _profiles?.hide();
      for (final feature in _features.values) {
        feature.show(false);
      }
    } on MissingPluginException {
      _feeds.stop();
      _social?.show(false);
      _communications?.show(false);
      _profiles?.hide();
      for (final feature in _features.values) {
        feature.show(false);
      }
    }
  }

  // A hidden or failed opening has no authority to keep feature reads alive.
  // Share this cleanup between native hide, failed open and account detach.
  void _suspend() {
    _screenshotRequests.retire();
    _feeds.stop();
    _generation = null;
    _contextTimer?.cancel();
    _social?.show(false);
    _communications?.show(false);
    _profiles?.hide();
    for (final feature in _features.values) {
      feature.show(false);
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
    MenuHotkeyIntent? target,
  }) async {
    if (_opening || _disposed) return false;
    _opening = true;
    _suspend();
    _live = live;
    final shown = Completer<bool>();
    _shown = shown;
    // A replaced account can finish disposing after the next one has attached.
    // Only the latest owner may remove the handler or control the native menu.
    final previous = lifetime._owner;
    if (previous != null && !identical(previous, this)) {
      previous._suspend();
      final pending = previous._shown;
      if (pending != null && !pending.isCompleted) pending.complete(false);
    }
    lifetime._owner = this;
    final request = ++lifetime._nextRequest;
    _request = request;
    _channel.setMethodCallHandler(_handleMethod);
    var visible = false;
    try {
      var preferencesFailed = false;
      if (preferences != null && live) {
        try {
          _preferencesTimer?.cancel();
          await _preferencesWork;
          if (_disposed || !_ownsChannel) return false;
          await _savePreferences();
          if (_disposed || !_ownsChannel) return false;
          _preferences = await preferences!.read();
        } on Object {
          _preferences = null;
          preferencesFailed = true;
        }
      }
      // Reads may finish after logout/disposal. Never recreate the detached
      // native workspace using this account's labels or capability factories.
      if (_disposed || !_ownsChannel) return false;
      _recoveryPending = false;
      final opening = await lifetime._recovery.prepare(
        live: live && !lifetime.startup.protectsLayout,
        preferences: live ? _preferences : null,
        preferencesPort: preferences,
        recovery: recovery,
        isCurrent: () => !_disposed && _ownsChannel,
      );
      if (_disposed || !_ownsChannel) return false;
      if (live) _preferences = opening.preferences;
      _recoveryPending = opening.pending;
      preferencesFailed |= opening.failed;
      if (live) await _reportWindow(request, 'opening');
      if (_disposed || !_ownsChannel) return false;
      final generation = await _channel
          .invokeMethod<int>('preview', {
            'schemaVersion': 1,
            'request': request,
            if (target != null) 'targetWindow': target.targetWindow,
            if (target != null) 'targetProcessId': target.targetProcessId,
            'contextLabel': contextLabel,
            'returnLabel': returnLabel,
            'settingsLabel': settingsLabel,
            'liveFriends': live,
            'liveComms': live && comms != null,
            'liveFeatures': live && features.isNotEmpty,
            'shortcutSettings': live && shortcutSettings != null,
            'browserResume': live && browserResume != null,
            'screenshotDirectory': live && screenshotDirectory != null,
            'preferences': lifetime.startup
                .presentation(opening.presentation)
                .encode(),
            'startupMode': lifetime.startup.mode,
            'preferencesFailed': preferencesFailed,
            'recoveryPending': live && _recoveryPending,
          })
          .timeout(const Duration(seconds: 6));
      if (_disposed || !_ownsChannel || generation == null || generation <= 0) {
        return false;
      }
      if (shown.isCompleted && !await shown.future) return false;
      _generation = generation;
      // A successful request is not evidence that Windows revealed the menu.
      visible = await shown.future.timeout(const Duration(seconds: 6));
      // The visible acknowledgement can precede the preview response.
      if (visible && !_feeds.active) _startAttention();
      if (visible) {
        lifetime._recovery.visible(live: live, pending: _recoveryPending);
      }
      return visible && !_disposed && _ownsChannel;
    } on TimeoutException {
      // A newer account may already own the shared native channel after detach.
      if (_disposed || !_ownsChannel) return false;
      try {
        await _channel
            .invokeMethod<void>('close', {'request': request})
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
      if (!visible && !_disposed) {
        _suspend();
        unawaited(_reportWindow(request, 'closed'));
      }
      _shown = null;
      _opening = false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _screenshotRequests.retire();
    _feeds.stop();
    hotkeys?.dispose();
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
    if (_ownsChannel) {
      lifetime._owner = null;
      _channel.setMethodCallHandler(null);
    }
    // Native independently checks the request: a previous owner may still be
    // displayed while its replacement reads preferences, but can never detach
    // a newer native opening.
    if (_request != null) unawaited(_detach(_request));
  }

  Future<void> _detach(int? request) async {
    try {
      await _channel.invokeMethod<void>('detach', {'request': request});
    } on PlatformException {
      /* Native lifetime ended. */
    } on MissingPluginException {
      /* No native window. */
    }
  }
}
