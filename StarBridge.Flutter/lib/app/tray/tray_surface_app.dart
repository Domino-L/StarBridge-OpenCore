import 'dart:async';
import '../../design_system/scrolling/starbridge_scroll_behavior.dart';


import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design_system/style_registry.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../localization/app_strings.dart';
import '../presence/manual_presence.dart';
import '../presence/projected_connection_mode.dart';
import '../../features/onboarding/connection_mode_port.dart';
import 'tray_quick_panel.dart';
import 'tray_star_arrival.dart';
import 'tray_surface_snapshot.dart';

// Called only by trayMain. Deliberately does NOT call bootstrapStarBridge,
// create an account, load preferences from disk or attach NativeHostBridge.
void runTraySurface() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TraySurfaceApp());
}

class TraySurfaceApp extends StatefulWidget {
  const TraySurfaceApp({super.key});
  @override
  State<TraySurfaceApp> createState() => _TraySurfaceAppState();
}

class _TraySurfaceAppState extends State<TraySurfaceApp> {
  static const _channel = MethodChannel('starbridge/tray-surface');
  final _source = ValueNotifier(const ManualPresenceSnapshot(scope: 0));
  final _modeSource = ValueNotifier(const ConnectionModeSnapshot());
  late final _mode = ProjectedConnectionMode(
    source: _modeSource,
    write: (scope) async {
      if (scope is! int) throw StateError('Context changed');
      await _action('offlineMode', expectedScope: scope);
    },
  );
  late final _presence = ManualPresenceController(
    source: _source,
    connectionMode: _mode,
    write: (mode, scope) async {
      if (_snapshot?.scope != scope) throw StateError('Context changed');
      await _action('presence', mode: mode.name);
    },
  );
  TraySurfaceSnapshot? _snapshot;
  VoidCallback? _restoreRelease;
  int _receivedSnapshots = 0;
  GlobalKey _logo = GlobalKey();
  int? _layoutOpening, _layoutHeight;
  int? _paintedOpening;
  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'snapshot') _receive(call.arguments);
    });
    unawaited(_ready());
  }

  Future<void> _ready() async {
    final observed = _receivedSnapshots;
    try {
      final result = await _channel.invokeMethod<Object?>('ready');
      if (mounted && _receivedSnapshots == observed) _receive(result);
    } on Object {
      /* Native timed fallback owns recovery. */
    }
  }

  void _receive(Object? raw) {
    if (!mounted || raw == null) return;
    final next = TraySurfaceSnapshot.parse(raw);
    if (next.scope == _snapshot?.scope && next.revision < _snapshot!.revision) {
      return;
    }
    _receivedSnapshots++;
    if (next.opening != _snapshot?.opening) {
      _logo = GlobalKey();
    }
    setState(() => _snapshot = next);
    _source.value = ManualPresenceSnapshot(
      scope: next.scope,
      confirmedMode: next.presence,
      canChange: next.canChangePresence,
      automaticKey: next.automaticKey,
    );
    _modeSource.value = ConnectionModeSnapshot(
      scope: next.scope,
      state: next.connectionMode,
      canEnterOffline: next.canEnterOffline,
    );
    _restoreRelease?.call();
    _restoreRelease = next.canRestoreOnline
        ? _presence.bindOnlineRestore(() async {
            await _action('resumeOnline', expectedScope: next.scope);
            return _modeSource.value.state == ConnectionModeState.online;
          })
        : null;
  }

  Future<void> _reportLayout(Size size) async {
    if (!mounted) return;
    final opening = _snapshot?.opening;
    if (opening == null) return;
    final height = size.height.ceil();
    if (_layoutOpening == opening && _layoutHeight == height) return;
    _layoutOpening = opening;
    _layoutHeight = height;
    try {
      // Measure unconstrained content, not the current native viewport. This
      // also allows the window to grow again after a language/state change.
      await _channel.invokeMethod<void>('layout', {
        'opening': opening,
        'height': height,
      });
      if (!mounted || _snapshot?.opening != opening) return;
      if (_paintedOpening != opening) {
        _paintedOpening = opening;
        await _channel.invokeMethod<void>('painted', opening);
      }
    } on Object {
      /* Native timed fallback owns recovery. */
    }
  }

  Future<void> _action(
    String action, {
    String? mode,
    int? expectedScope,
  }) async {
    if (expectedScope != null && expectedScope != _snapshot?.scope) {
      throw StateError('Context changed');
    }
    final sentScope = _snapshot!.scope;
    final result = await _channel.invokeMethod<Object?>('action', {
      'action': action,
      'scope': sentScope,
      'mode': ?mode,
    });
    if (action == 'resumeOnline') {
      // Restoring can legitimately replace the primary transport generation.
      // Never adopt that command's delayed projection as current authority:
      // reread the primary projection, preserving any newer pushed snapshot.
      if (mounted) await _ready();
      return;
    }
    // A command acknowledgement may omit native presentation metadata. Keep the
    // current opening token so normal updates never replay the entrance.
    if (result is Map) {
      final received = TraySurfaceSnapshot.parse(result);
      if (!mounted ||
          _snapshot?.scope != sentScope ||
          received.scope != sentScope ||
          received.revision < _snapshot!.revision) {
        throw StateError('Context changed');
      }
      _receive({
        ...result,
        'opening': _snapshot?.opening ?? 0,
        'keyboard': _snapshot?.keyboard ?? false,
      });
    }
  }

  void _dismiss() {
    unawaited(_channel.invokeMethod<void>('dismiss'));
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _restoreRelease?.call();
    _presence.dispose();
    _mode.dispose();
    _modeSource.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _snapshot;
    if (state == null) return const SizedBox.shrink();
    final parts = state.locale.split('-');
    final locale = Locale(parts.first, parts.length > 1 ? parts[1] : null);
    final tokens = StyleRegistry()
        .resolve(
          state.styleId,
          state.dark ? AppearanceMode.dark : AppearanceMode.light,
        )
        .tokens;
    return MaterialApp(
      themeAnimationDuration:
          state.reduceMotion ||
              (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
          ? Duration.zero
          : kThemeAnimationDuration,
      builder: (context, child) => StarBridgeInteractionConfiguration(
        suite: interactionSuiteFromName(state.interactionStyle),
        reduceMotion: state.reduceMotion,
        child: child!,
      ),
      scrollBehavior: const StarBridgeScrollBehavior(),
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        tokens,
        locale,
        interactionSuite: interactionSuiteFromName(state.interactionStyle),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: _TrayLayout(
            key: ValueKey(state.opening),
            onLayout: (size) => unawaited(_reportLayout(size)),
            child: TrayStarArrival(
              key: ValueKey(state.opening),
              logoKey: _logo,
              reduceMotion: state.reduceMotion,
              keyboard: state.keyboard,
              child: TrayQuickPanel(
                state: state.state,
                logoKey: _logo,
                manualPresence: _presence,
                onDismiss: _dismiss,
                onOpen: () => _action('open'),
                onExit: () => _action('exit'),
                onOverlaySettings: () => _action('overlaySettings'),
                onToggleOverlay: state.canToggleOverlay
                    ? () => _action('toggleOverlay')
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayLayout extends SingleChildRenderObjectWidget {
  const _TrayLayout({required this.onLayout, required super.child, super.key});
  final ValueChanged<Size> onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TrayLayoutBox(onLayout);
  @override
  void updateRenderObject(BuildContext context, _TrayLayoutBox renderObject) {
    renderObject.onLayout = onLayout;
  }
}

class _TrayLayoutBox extends RenderProxyBox {
  _TrayLayoutBox(this.onLayout);
  ValueChanged<Size> onLayout;
  Size? _reported;
  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onLayout(size);
    });
  }
}
