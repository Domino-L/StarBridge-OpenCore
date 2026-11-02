import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import '../controls/semantic_action_style.dart';
import 'starbridge_dialog_surface.dart';
import 'starbridge_interaction_theme.dart';

/// The real ScaffoldMessenger retains its queue, timer, actions, swipe and
/// closed reason. Only the surface presentation changes; there is no new timer.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
showStarBridgeSnackBar(
  BuildContext context,
  SnackBar snackBar, {
  InteractionSource? source,
  ActionTone tone = ActionTone.info,
}) => ScaffoldMessenger.of(context).showSnackBar(
  starBridgeSnackBarFromContext(context, snackBar, source: source, tone: tone),
);

/// Capture presentation before an awaited native resize can unmount the opener.
/// The caller still owns its original mounted ScaffoldMessenger and queue.
SnackBar starBridgeSnackBarFromContext(
  BuildContext context,
  SnackBar snackBar, {
  InteractionSource? source,
  ActionTone tone = ActionTone.info,
}) => _SuiteSnackBar(
  original: snackBar,
  source: source ?? StarBridgeActivationOrigin.sourceOf(context),
  data:
      InteractionScope.maybeOf(context) ??
      resolveStarBridgeInteraction(context),
  link: InteractionScope.linkOf(context),
  tone: tone,
);

class _SuiteSnackBar extends SnackBar {
  _SuiteSnackBar({
    required this.original,
    required this.source,
    required this.data,
    required this.link,
    required this.tone,
    super.animation,
    super.key,
  }) : super(
         content: original.content,
         backgroundColor: original.backgroundColor,
         elevation: original.elevation,
         margin: original.margin,
         padding: original.padding,
         width: original.width,
         shape: original.shape,
         hitTestBehavior: original.hitTestBehavior,
         behavior: original.behavior,
         action: original.action,
         actionOverflowThreshold: original.actionOverflowThreshold,
         showCloseIcon: original.showCloseIcon,
         closeIconColor: original.closeIconColor,
         duration: original.duration,
         persist: original.persist,
         onVisible: original.onVisible,
         dismissDirection: original.dismissDirection,
         clipBehavior: original.clipBehavior,
       );

  final SnackBar original;
  final InteractionSource source;
  final InteractionData data;
  final ValueListenable<InteractionData>? link;
  final ActionTone tone;

  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) =>
      _SuiteSnackBar(
        original: original,
        source: source,
        data: data,
        link: link,
        animation: newAnimation,
        tone: tone,
        key: fallbackKey,
      );

  @override
  State<SnackBar> createState() => _SuiteSnackBarState();
}

class _SuiteSnackBarState extends State<SnackBar> {
  @override
  Widget build(BuildContext context) {
    final config = widget as _SuiteSnackBar;
    final body = _SnackBarBody(
      original: config.original,
      animation: config.animation! as AnimationController,
      source: config.source,
      tone: config.tone,
    );
    return config.link == null
        ? InteractionScope(data: config.data, child: body)
        : InteractionScope.follow(config.link!, child: body);
  }
}

class _SnackBarBody extends StatefulWidget {
  const _SnackBarBody({
    required this.original,
    required this.animation,
    required this.source,
    required this.tone,
  });
  final SnackBar original;
  final AnimationController animation;
  final InteractionSource source;
  final ActionTone tone;
  @override
  State<_SnackBarBody> createState() => _SnackBarBodyState();
}

class _SnackBarBodyState extends State<_SnackBarBody> {
  late final _steady = _SteadyAnimation(widget.animation);
  late final Duration? _originalDuration;
  late final Duration? _originalReverseDuration;
  InteractionData? _data;
  bool _queued = false;
  bool _retired = false;
  bool _started = false;
  bool _keyboardEvent = false;
  bool _pointerEvent = false;
  bool _instantExit = false;

  bool get _static =>
      _data!.reduceMotion ||
      widget.source == InteractionSource.keyboard ||
      _instantExit;

  @override
  void initState() {
    super.initState();
    // Capture before this entry changes the messenger's shared timing.
    _originalDuration = widget.animation.duration;
    _originalReverseDuration = widget.animation.reverseDuration;
    widget.animation.addListener(_restoreAtDismissal);
    widget.animation.addStatusListener(_status);
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  void _restoreAtDismissal() {
    final controller = widget.animation;
    if (controller.status == AnimationStatus.dismissed &&
        controller.value == 0) {
      // Value listeners run before status listeners. Restore before the
      // messenger's dismissed handler advances the next queued native entry.
      controller.duration = _originalDuration;
      controller.reverseDuration = _originalReverseDuration;
    }
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is KeyDownEvent &&
        [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.escape,
        ].contains(event.logicalKey)) {
      _keyboardEvent = true;
      scheduleMicrotask(() => _keyboardEvent = false);
    }
    return KeyEventResult.ignored;
  }

  void _status(AnimationStatus status) {
    if (_retired) return;
    if (status == AnimationStatus.dismissed) {
      _retired = true;
    } else if (status == AnimationStatus.reverse) {
      _instantExit =
          _static ||
          _keyboardEvent ||
          currentStarBridgeActivationSource == InteractionSource.keyboard;
      if (_instantExit) _schedule();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = InteractionScope.of(context);
    final previous = _data;
    _data = data;
    // Never use showSnackBar(animationStyle:) per entry: Flutter replaces the
    // shared controller there, invalidating entries already queued on it.
    // Non-zero timings also allow the next, non-reduced entry to animate.
    final durations = surfaceDurations(
      data.copyWith(reduceMotion: false),
      SurfaceKind.toast,
    );
    widget.animation.duration = durations.enter;
    widget.animation.reverseDuration = durations.exit;
    if (!_started || _static || previous?.suite != data.suite) _schedule();
  }

  void _schedule() {
    if (_queued || _retired) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || _retired) return;
      final controller = widget.animation;
      final first = !_started;
      _started = true;
      if (_static &&
          (controller.status == AnimationStatus.forward ||
              controller.status == AnimationStatus.reverse)) {
        final closing = controller.status == AnimationStatus.reverse;
        if (closing) _retired = true;
        // Complete, rather than cancel, ScaffoldMessenger's reverse future.
        // Its .then completes the original closed reason (including timeout).
        controller.stop(canceled: false);
        controller.value = closing ? 0 : 1;
      } else if (controller.status == AnimationStatus.forward) {
        // Restart only the unawaited entrance, never a pending exit future.
        controller.forward();
      }
      if (mounted && (!first || _instantExit)) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.animation.removeListener(_restoreAtDismissal);
    widget.animation.removeStatusListener(_status);
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    // The messenger owns this controller; never dispose it here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data!.copyWith(reduceMotion: _static);
    final o = widget.original;
    final action = o.action;
    final native = action == null
        ? o.withAnimation(_steady)
        : SnackBar(
            key: o.key,
            content: o.content,
            backgroundColor: o.backgroundColor,
            elevation: o.elevation,
            margin: o.margin,
            padding: o.padding,
            width: o.width,
            shape: o.shape,
            hitTestBehavior: o.hitTestBehavior,
            behavior: o.behavior,
            action: SnackBarAction(
              key: action.key,
              label: action.label,
              textColor: action.textColor,
              disabledTextColor: action.disabledTextColor,
              backgroundColor: action.backgroundColor,
              disabledBackgroundColor: action.disabledBackgroundColor,
              onPressed: () {
                final source = _pointerEvent && !_keyboardEvent
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard;
                _instantExit = source == InteractionSource.keyboard;
                runStarBridgeSynchronousActivation(source, action.onPressed);
              },
            ),
            actionOverflowThreshold: o.actionOverflowThreshold,
            showCloseIcon: o.showCloseIcon,
            closeIconColor: o.closeIconColor,
            duration: o.duration,
            persist: o.persist,
            animation: _steady,
            onVisible: o.onVisible,
            dismissDirection: o.dismissDirection,
            clipBehavior: o.clipBehavior,
          );
    return InteractionScope(
      data: data,
      child: Listener(
        onPointerUp: (_) {
          _pointerEvent = true;
          scheduleMicrotask(() => _pointerEvent = false);
        },
        child: StarBridgeMeasuredSurface(
          animation: widget.animation,
          kind: SurfaceKind.toast,
          tone: switch (widget.tone) {
            ActionTone.danger => data.palette.danger,
            ActionTone.warning => data.palette.warning,
            ActionTone.success => data.palette.success,
            ActionTone.info => data.palette.accent,
          },
          // Native layout, semantics, actions, dismiss, Hero and onVisible stay
          // mounted. Its value is 1 to avoid a second fade/height animation;
          // status still follows the messenger so onVisible runs exactly once.
          child: native,
        ),
      ),
    );
  }
}

class _SteadyAnimation extends ProxyAnimation {
  _SteadyAnimation(super.animation);
  @override
  double get value => 1;
}
