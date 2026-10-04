import 'dart:async';
import '../../design_system/scrolling/starbridge_scroll_behavior.dart';

import '../../design_system/icons/window_control_icon.dart';
import '../../design_system/styles/window_caption_palette.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../localization/app_strings.dart';
import '../menu_overlay/menu_friends_view.dart';
import '../social_windows/window_presentation.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

void runFriendsWindow() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FriendsWindowApp());
}

/// Presentation only: no bootstrap, credentials, Host or message polling.
class FriendsWindowApp extends StatefulWidget {
  const FriendsWindowApp({super.key});
  @override
  State<FriendsWindowApp> createState() => _FriendsWindowAppState();
}

class _FriendsWindowAppState extends State<FriendsWindowApp> {
  static const _channel = MethodChannel('starbridge/friends-surface');
  WindowPresentation _presentation = const WindowPresentation();
  StarBridgeTokens get _clientTokens => _presentation.tokens;
  MenuFriendsView _view = const MenuFriendsView('loading');
  int _opening = 0, _revision = -1;
  bool _pending = false, _failed = false;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'snapshot') _accept(call.arguments);
      if (call.method == 'windowState' && call.arguments is bool && mounted) {
        setState(() => _maximized = call.arguments as bool);
      }
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    try {
      _accept(await _channel.invokeMethod<Object?>('ready'));
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _accept(Object? payload) {
    if (!mounted || payload is! Map) return;
    final opening = payload['opening'], revision = payload['revision'];
    if (opening is! int ||
        revision is! int ||
        opening < _opening ||
        (opening == _opening && revision < _revision)) {
      return;
    }
    setState(() {
      _opening = opening;
      _revision = revision;
      _view = MenuFriendsView.parse(payload['view']);
      _presentation = WindowPresentation.decode(payload['presentation']);
      _failed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && opening == _opening && revision == _revision) {
        unawaited(_painted(opening));
      }
    });
  }

  Future<void> _painted(int opening) async {
    try {
      await _channel.invokeMethod<void>('painted', {'opening': opening});
    } on PlatformException {
      // Native timeout restores the ordinary page if presentation fails.
    } on MissingPluginException {
      // Widget-only preview.
    }
  }

  Future<void> _windowControl(String command) async {
    try {
      await _channel.invokeMethod<void>('windowControl', command);
    } on PlatformException {
      // Window controls never replay account or social commands.
    } on MissingPluginException {
      // Widget-only preview.
    }
  }

  Widget _captionButton(String label, WindowGlyph icon, String command) =>
      SizedBox(
        width: 44,
        height: 34,
        child: IconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: const RoundedRectangleBorder(),
            foregroundColor: _clientTokens.colors.textSecondary,
            hoverColor: command == 'close'
                ? WindowCaptionPalette.closeHover
                : _clientTokens.surfaces.selected.fill,
          ).copyWith(side: const WidgetStatePropertyAll(BorderSide.none)),
          iconSize: 15,
          onPressed: () => unawaited(_windowControl(command)),
          icon: WindowControlIcon(icon),
        ),
      );

  Future<void> _action(String action, String key, String value) async {
    if (_pending) return;
    final opening = _opening;
    setState(() => _pending = true);
    try {
      final accepted = await _channel.invokeMethod<bool>('action', {
        'opening': opening,
        'revision': _revision,
        'scope': _view.scope,
        'action': action,
        'key': key,
        'value': value,
      });
      if (mounted && opening == _opening) {
        setState(() => _failed = accepted != true);
      }
    } on PlatformException {
      if (mounted && opening == _opening) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
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
    home: Scaffold(
      // Detached desktop windows are raised reading surfaces, not the menu's
      // near-black ground. Reuse the client's palette without changing overlays.
      backgroundColor: _clientTokens.surfaces.raised.fill,
      body: DecoratedBox(
        key: const ValueKey('friends-window-frame'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: _clientTokens.surfaces.windowFrame,
            width: _clientTokens.stroke.hairline,
          ),
        ),
        child: Column(
          children: [
            // Same surface as the roster. Native hit-testing owns the title's
            // drag / double-click region and leaves the right 132 DIPs interactive.
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 14),
                      child: Text(
                        '好友',
                        style: TextStyle(
                          fontSize: 12,
                          color: _clientTokens.colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  _captionButton('最小化', WindowGlyph.minimize, 'minimize'),
                  _captionButton(
                    _maximized ? '还原' : '最大化',
                    _maximized ? WindowGlyph.restore : WindowGlyph.maximize,
                    'toggleMaximize',
                  ),
                  _captionButton('关闭好友窗口', WindowGlyph.close, 'close'),
                ],
              ),
            ),
            if (_failed)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('操作未确认，请刷新列表核对后再试。'),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _pending,
                child: MenuFriendsPanel(
                  key: ValueKey('$_opening:${_view.scope}'),
                  embedded: true,
                  view: _view,
                  onClose: () => unawaited(_windowControl('close')),
                  onAction: (a, k, v) => unawaited(_action(a, k, v)),
                  onChat: (key) => unawaited(_action('chat', key, '')),
                  onProfile: (key) => unawaited(_action('profile', key, '')),
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _pending
                    ? null
                    : () => unawaited(_action('messages', '', '')),
                icon: const WindowControlIcon(WindowGlyph.chat, size: 18),
                label: const Text('打开最近聊天'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
