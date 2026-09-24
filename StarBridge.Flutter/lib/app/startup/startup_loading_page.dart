import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../platform/window/window_chrome_port.dart';
import '../localization/app_strings.dart';
import '../shell/widgets/window_controls.dart';
import 'startup_brand_logo.dart';
import 'startup_session.dart';

/// Real boot status, with the approved logo choreography as a removable layer.
class StartupLoadingPage extends StatefulWidget {
  const StartupLoadingPage({
    required this.session,
    required this.windowChrome,
    required this.preferencesConfirmed,
    required this.reduceMotion,
    required this.onRetry,
    this.lowPerformance = false,
    super.key,
  });

  final StartupSession session;
  final WindowChromePort windowChrome;
  final bool preferencesConfirmed;
  final bool reduceMotion;
  final bool lowPerformance;
  final Future<void> Function() onRetry;

  @override
  State<StartupLoadingPage> createState() => _StartupLoadingPageState();
}

class _StartupLoadingPageState extends State<StartupLoadingPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _spin;
  late final AnimationController _assembly;
  late final AnimationController _handoff;
  Timer? _pause;
  bool _visible = true;
  bool _tickerEnabled = true;
  bool _systemReduced = false;
  bool _quiet = false;
  bool _retrying = false;
  bool _enterScheduled = false;
  int _slowFrames = 0;

  bool get _still =>
      widget.reduceMotion || _systemReduced || widget.lowPerformance || _quiet;
  bool get _active => _visible && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    final spec = widget.session.spec;
    _spin = AnimationController(vsync: this, duration: spec.spinDuration)
      ..addStatusListener(_spinStatus);
    _assembly =
        AnimationController(vsync: this, duration: spec.assemblyDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _handoff.forward();
          });
    _handoff = AnimationController(vsync: this, duration: spec.handoffDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _enterSoon();
      });
    widget.session.addListener(_phaseChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_measureFrames);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _visible = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.session.markPresented();
      _syncMotion();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant StartupLoadingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(identical(widget.session, oldWidget.session));
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _measureFrames(List<FrameTiming> timings) {
    if (!mounted || !_active || _still || !_spin.isAnimating) return;
    for (final timing in timings) {
      if (timing.buildDuration.inMilliseconds > 48 ||
          timing.rasterDuration.inMilliseconds > 48) {
        _slowFrames++;
      }
    }
    if (_slowFrames >= 3) {
      setState(() => _quiet = true);
      _syncMotion();
    }
  }

  void _phaseChanged() {
    if (!mounted) return;
    setState(() {});
    _syncMotion();
  }

  void _stop() {
    _pause?.cancel();
    _pause = null;
    _spin.stop();
    _assembly.stop();
    _handoff.stop();
  }

  void _syncMotion() {
    final phase = widget.session.value;
    if (phase.failed || phase == StartupPhase.complete) {
      _stop();
      return;
    }
    if (_still || !_active) {
      _stop();
      if (phase == StartupPhase.ready) _enterSoon();
      return;
    }
    if (phase == StartupPhase.ready) {
      _pause?.cancel();
      _pause = null;
      // Finish an in-flight turn, never add another turn just to fill time.
      if (!_spin.isAnimating) {
        if (_assembly.isCompleted) {
          _handoff.forward();
        } else {
          _assembly.forward();
        }
      }
    } else if (widget.preferencesConfirmed &&
        !_spin.isAnimating &&
        _pause == null) {
      _assembly.value = 0;
      _handoff.value = 0;
      _spin.forward(from: 0);
    }
    // Unknown preferences: hold the center star still until motion is allowed.
  }

  void _spinStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (widget.session.value == StartupPhase.ready) {
      _assembly.forward();
    } else if (!widget.session.value.failed && _active && !_still) {
      _pause = Timer(widget.session.spec.spinPause, () {
        _pause = null;
        if (mounted) _syncMotion();
      });
    }
  }

  void _enterSoon() {
    if (_enterScheduled) return;
    _enterScheduled = true;
    void enterIfReady() {
      _enterScheduled = false;
      if (mounted && widget.session.value == StartupPhase.ready) {
        widget.session.enter();
      }
    }

    // Hidden desktop windows may not receive another frame until restored.
    if (!_active) {
      scheduleMicrotask(enterIfReady);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => enterIfReady());
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final phase = widget.session.value;
    final hostReady =
        phase == StartupPhase.preferences ||
        phase == StartupPhase.preferencesUnavailable ||
        phase == StartupPhase.account ||
        phase == StartupPhase.accountUnavailable ||
        phase == StartupPhase.ready;
    final settingsReady =
        phase == StartupPhase.account ||
        phase == StartupPhase.accountUnavailable ||
        phase == StartupPhase.ready;
    final title = strings.text('startup.${phase.name}');
    return Scaffold(
      key: const Key('startup-loading-page'),
      body: Column(
        children: [
          SizedBox(
            height: tokens.density.topBarHeight,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) =>
                        unawaited(widget.windowChrome.beginDrag()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'StarBridge',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  ),
                ),
                WindowControls(windowChrome: widget.windowChrome),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_assembly, _handoff]),
                            builder: (context, _) => Opacity(
                              key: const Key('startup-handoff'),
                              opacity: _still ? 1 : 1 - _handoff.value,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 216,
                                    height: 216,
                                    // Original white artwork stays readable in light mode.
                                    decoration:
                                        Theme.of(context).brightness ==
                                            Brightness.light
                                        ? BoxDecoration(
                                            color: tokens.colors.textPrimary,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          )
                                        : null,
                                    alignment: Alignment.center,
                                    child: FivePartBrandLogo(
                                      size: 168,
                                      revealProgress: 1,
                                      spin: _spin,
                                      spinTurns: 1,
                                      assemblyProgress: _assembly.value,
                                      direction: widget.session.spec.direction,
                                      reduceMotion: _still,
                                      lowPerformance: false,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: phase.failed
                                                ? tokens.colors.warning
                                                : tokens.colors.textPrimary,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    strings.text(
                                      phase.failed
                                          ? 'startup.failure'
                                          : 'startup.wait',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: tokens.colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _statusRow(
                                    context,
                                    'startup.host',
                                    hostReady
                                        ? 'done'
                                        : phase == StartupPhase.hostUnavailable
                                        ? 'failed'
                                        : 'loading',
                                  ),
                                  const SizedBox(height: 8),
                                  _statusRow(
                                    context,
                                    'startup.settings',
                                    settingsReady
                                        ? 'done'
                                        : phase ==
                                              StartupPhase
                                                  .preferencesUnavailable
                                        ? 'failed'
                                        : phase == StartupPhase.preferences
                                        ? 'loading'
                                        : 'waiting',
                                  ),
                                  const SizedBox(height: 8),
                                  _statusRow(
                                    context,
                                    'startup.accountLabel',
                                    settingsReady
                                        ? widget.session.accountStatus.name
                                        : 'waiting',
                                  ),
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      if (phase.failed || _retrying)
                                        FilledButton.icon(
                                          key: const Key('startup-retry'),
                                          onPressed: _retrying ? null : _retry,
                                          icon: _retrying && !_still && _active
                                              ? const SizedBox.square(
                                                  dimension: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const StarBridgeIcon(
                                                  StarBridgeIconSemantic
                                                      .refresh,
                                                  size: 16,
                                                ),
                                          label: Text(
                                            strings.text(
                                              _retrying
                                                  ? 'startup.retrying'
                                                  : 'startup.retry',
                                            ),
                                          ),
                                        ),
                                      OutlinedButton(
                                        key: const Key('startup-enter'),
                                        onPressed: widget.session.enter,
                                        child: Text(
                                          strings.text('startup.enter'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.preferencesConfirmed &&
                                      !_still &&
                                      !phase.failed &&
                                      phase != StartupPhase.ready)
                                    TextButton(
                                      onPressed: () {
                                        setState(() => _quiet = true);
                                        _syncMotion();
                                      },
                                      child: Text(
                                        strings.text('startup.pause'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(BuildContext context, String label, String state) {
    final strings = AppStrings.of(context);
    final colors = context.tokens.colors;
    final color = switch (state) {
      'done' || 'signedIn' => colors.success,
      'failed' || 'reauthorizationRequired' => colors.warning,
      'loading' => colors.accent,
      _ => colors.textSecondary,
    };
    return Row(
      children: [
        StarBridgeIcon(
          state == 'done' || state == 'signedIn' || state == 'signedOut'
              ? StarBridgeIconSemantic.connected
              : state == 'failed' || state == 'reauthorizationRequired'
              ? StarBridgeIconSemantic.warning
              : StarBridgeIconSemantic.pending,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(strings.text(label))),
        const SizedBox(width: 12),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            strings.text('startup.$state'),
            textAlign: TextAlign.end,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.session.removeListener(_phaseChanged);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_measureFrames);
    _pause?.cancel();
    _spin.dispose();
    _assembly.dispose();
    _handoff.dispose();
    super.dispose();
  }
}
