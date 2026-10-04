import 'dart:async';
import '../../design_system/scrolling/starbridge_scroll_behavior.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../localization/app_strings.dart';
import 'window_presentation.dart';
import '../routing/open_destination_intent.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/direct_messages/direct_messages_page.dart';
import '../../features/notifications/notification_inbox_page.dart';
import 'social_window_codec.dart';
import 'social_window_frame.dart';
import 'social_window_ports.dart';

void runSocialWindow(String kind) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SocialWindowApp(kind: kind));
}

class SocialWindowApp extends StatefulWidget {
  const SocialWindowApp({required this.kind, super.key});
  final String kind;
  @override
  State<SocialWindowApp> createState() => _SocialWindowAppState();
}

class _SocialWindowAppState extends State<SocialWindowApp> {
  late final MethodChannel channel = MethodChannel(
    'starbridge/${widget.kind}-surface',
  );
  Map _view = const {};
  WindowPresentation _presentation = const WindowPresentation();
  int _opening = 0, _revision = -1, _targetVersion = -1;
  bool _active = false, _maximized = false, _failed = false;
  WindowMessagesPort? _port;
  DirectMessagesModule? _messages;
  WindowInboxController? _inbox;
  Conversation? _target;
  String? _reportedRef;
  void _reportViewport() {
    final ref = _messages?.selected?.ref;
    if (ref == _reportedRef) return;
    _reportedRef = ref;
    unawaited(
      _request(_view['scope'] as String, 'viewport', {
        'ref': ref,
      }).catchError((_) => null),
    );
  }

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'snapshot') _accept(call.arguments);
      if (call.method == 'windowState' && mounted && call.arguments is bool) {
        setState(() => _maximized = call.arguments as bool);
      }
      if (call.method == 'viewportActive' &&
          mounted &&
          call.arguments is bool) {
        setState(() => _active = call.arguments as bool);
        if (_active) _pulse();
      }
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      _accept(await channel.invokeMethod<Object?>('ready'));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<Object?> _request(
    String scope,
    String op,
    Map<String, Object?> args,
  ) async {
    if (!mounted || scope != _view['scope']) {
      throw PlatformException(code: 'window.stale');
    }
    final result = await channel.invokeMethod<Object?>('rpc', {
      ...args,
      'op': op,
      'scope': scope,
      'opening': _opening,
    });
    if (!mounted || scope != _view['scope']) {
      throw PlatformException(code: 'window.stale');
    }
    return result;
  }

  void _accept(Object? payload) {
    if (!mounted ||
        payload is! Map ||
        payload['opening'] is! int ||
        payload['revision'] is! int ||
        payload['view'] is! String) {
      return;
    }
    final opening = payload['opening'] as int,
        revision = payload['revision'] as int;
    if (opening < _opening || (opening == _opening && revision < _revision)) {
      return;
    }
    final view = jsonDecode(payload['view'] as String);
    if (view is! Map || view['scope'] is! String) return;
    final changed = view['scope'] != _view['scope'];
    setState(() {
      _opening = opening;
      _revision = revision;
      _view = view;
      _presentation = WindowPresentation.decode(payload['presentation']);
      _failed = false;
      if (changed) {
        _messages?.dispose();
        _inbox?.dispose();
        _messages = null;
        _inbox = null;
        _target = null;
        _targetVersion = -1;
        _reportedRef = null;
        final scope = view['scope'] as String;
        Future<Object?> request(String op, Map<String, Object?> args) =>
            _request(scope, op, args);
        if (widget.kind == 'messages') {
          _port = WindowMessagesPort(request, () => _view);
          _messages = DirectMessagesModule(_port!);
          _messages!.addListener(_reportViewport);
        } else {
          _inbox = WindowInboxController(request);
        }
      }
      if (_targetVersion != view['targetVersion']) {
        _targetVersion = view['targetVersion'] as int? ?? 0;
        _target = view['target'] is Map
            ? decodeConversation(view['target'] as Map)
            : null;
      }
    });
    if (!changed) _pulse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && opening == _opening) {
        unawaited(_notify('painted', {'opening': opening}));
      }
    });
  }

  void _pulse() {
    if (!_active) return;
    final messages = _messages;
    if (messages != null && !messages.loaded && !messages.busy) {
      unawaited(messages.refresh());
      return;
    }
    if (_port != null && !_port!.activity.isClosed) _port!.activity.add(null);
    if (_active && _inbox != null && !_inbox!.busy) {
      unawaited(_inbox!.refresh(reuseFresh: true));
    }
  }

  Future<void> _notify(String method, Object? args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on PlatformException {
      /* No replay. */
    } on MissingPluginException {
      /* Widget tests. */
    }
  }

  Future<void> _navigate(String route) async {
    try {
      await _request(_view['scope'] as String, 'navigate', {'route': route});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    _messages?.dispose();
    _inbox?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    scrollBehavior: const StarBridgeScrollBehavior(),
    debugShowCheckedModeBanner: false,
    locale: _presentation.locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: _presentation.theme,
    home: SocialWindowFrame(
      title: widget.kind == 'messages' ? '聊天' : '通知',
      maximized: _maximized,
      control: (c) => unawaited(_notify('windowControl', c)),
      child: Actions(
        actions: {
          OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
            onInvoke: (i) {
              unawaited(_navigate(i.route));
              return null;
            },
          ),
        },
        child: NativeViewportScope(
          active: _active,
          child: TickerMode(
            enabled: _active,
            child: Column(
              children: [
                if (_failed)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('暂时无法完成操作，请重新打开窗口核对。'),
                  ),
                Expanded(
                  child: _messages != null
                      ? DirectMessagesPage(
                          key: ValueKey(_view['scope']),
                          createPort: () => _port!,
                          sharedModule: _messages,
                          openProfile: _view['openProfile'] == true
                              ? (target) {
                                  unawaited(
                                    _request(
                                      _view['scope'] as String,
                                      'profile',
                                      {'ref': target.ref},
                                    ).catchError((_) => null),
                                  );
                                }
                              : null,
                          initialConversation: _target,
                          openCommunityInvite: _view['openInvite'] == true
                              ? (_, code) async {
                                  await _request(
                                    _view['scope'] as String,
                                    'openInvite',
                                    {'code': code},
                                  );
                                }
                              : null,
                          sendCommunityInvite: _view['sendInvite'] == true
                              ? (_, chat) async {
                                  final ref = chat.selected?.ref;
                                  if (ref != null) {
                                    await _request(
                                      _view['scope'] as String,
                                      'sendInvite',
                                      {'ref': ref},
                                    );
                                  }
                                }
                              : null,
                          onBack: () => unawaited(_navigate('/friends')),
                        )
                      : _inbox != null
                      ? NotificationInboxPage(
                          key: ValueKey(_view['scope']),
                          controller: _inbox!,
                          openSafety: () =>
                              unawaited(_navigate('/account-safety')),
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
