import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

VoidCallback showStarBridgeNotificationToast(
  BuildContext context, {
  required Alignment alignment,
  required String title,
  required String message,
  Duration duration = const Duration(seconds: 4),
  InteractionSource? source,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final link = InteractionScope.linkOf(context);
  final data =
      InteractionScope.maybeOf(context) ??
      resolveStarBridgeInteraction(context);
  final origin = source ?? StarBridgeActivationOrigin.sourceOf(context);
  late final OverlayEntry entry;
  var removed = false;

  void remove() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) {
      final child = _StarBridgeNotificationOverlay(
        alignment: alignment,
        title: title,
        message: message,
        duration: duration,
        source: origin,
        onDismissed: remove,
      );
      return link == null
          ? InteractionScope(data: data, child: child)
          : InteractionScope.follow(link, child: child);
    },
  );
  overlay.insert(entry);
  return remove;
}

class _StarBridgeNotificationOverlay extends StatefulWidget {
  const _StarBridgeNotificationOverlay({
    required this.alignment,
    required this.title,
    required this.message,
    required this.duration,
    required this.source,
    required this.onDismissed,
  });

  final Alignment alignment;
  final String title;
  final String message;
  final Duration duration;
  final InteractionSource source;
  final VoidCallback onDismissed;

  @override
  State<_StarBridgeNotificationOverlay> createState() =>
      _StarBridgeNotificationOverlayState();
}

class _StarBridgeNotificationOverlayState
    extends State<_StarBridgeNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;
  var _closing = false;
  var _started = false;
  var _closeInstant = false;
  var _settleQueued = false;
  late InteractionData _data;

  bool get _instant =>
      !(_data.animates) ||
      widget.source == InteractionSource.keyboard ||
      _closeInstant;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_statusChanged);
    _dismissTimer = Timer(
      widget.duration,
      () => _dismiss(InteractionSource.programmatic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data = InteractionScope.of(context);
    final durations = surfaceDurations(
      _data.copyWith(reduceMotion: false),
      SurfaceKind.toast,
    );
    _controller.duration = durations.enter;
    _controller.reverseDuration = durations.exit;
    if (!_started) {
      _started = true;
      if (_instant) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (_instant && !_settleQueued) {
      // Dependency changes can arrive while the overlay is being built.
      // Settle after that frame, without restarting the timer or reverse.
      _settleQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _settleQueued = false;
        if (!mounted || !_instant) return;
        _controller.stop(canceled: false);
        _controller.value = _closing ? 0 : 1;
      });
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (_closing && status == AnimationStatus.dismissed && mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.removeStatusListener(_statusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _dismiss(InteractionSource source) {
    if (_closing || !mounted) {
      return;
    }
    _closing = true;
    _closeInstant = source == InteractionSource.keyboard;
    _dismissTimer?.cancel();
    if (_instant || _controller.isDismissed) {
      _controller.stop(canceled: false);
      widget.onDismissed();
    } else {
      // Status owns completion; changing reduced motion cannot cancel an
      // awaited reverse and strand the entry. External cancellation stays
      // immediate through the original returned remove callback.
      setState(() {});
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final safePadding = MediaQuery.paddingOf(context);
    final entersFromRight = widget.alignment.x > 0;
    final entersFromBottom = widget.alignment.y > 0;
    return Positioned(
      left: entersFromRight ? null : safePadding.left + tokens.space.md,
      right: entersFromRight ? safePadding.right + tokens.space.md : null,
      top: entersFromBottom ? null : safePadding.top + tokens.space.md,
      bottom: entersFromBottom ? safePadding.bottom + tokens.space.md : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            360,
            math.max(
              0,
              MediaQuery.sizeOf(context).width -
                  safePadding.horizontal -
                  tokens.space.md * 2,
            ),
          ),
        ),
        child: InteractionScope(
          data: _data.copyWith(reduceMotion: _instant),
          child: SuiteSurfaceTransition(
            animation: _controller,
            kind: SurfaceKind.toast,
            alignment: widget.alignment,
            toastFromLeft: !entersFromRight,
            radius: tokens.shape.radiusMedium,
            tone: _data.palette.success,
            child: IgnorePointer(
              ignoring: _closing,
              child: ExcludeFocus(
                excluding: _closing,
                child: ExcludeSemantics(
                  excluding: _closing,
                  child: _StarBridgeNotificationCard(
                    title: widget.title,
                    message: widget.message,
                    onDismiss: _dismiss,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarBridgeNotificationCard extends StatelessWidget {
  const _StarBridgeNotificationCard({
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final ValueChanged<InteractionSource> onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title。$message',
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: StarBridgeSurface(
            key: const Key('starbridge-notification-toast'),
            role: SurfaceRole.floating,
            padding: EdgeInsets.zero,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: tokens.colors.success),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(tokens.space.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: tokens.colors.successSoft,
                              borderRadius: tokens.shape.small,
                            ),
                            alignment: Alignment.center,
                            child: StarBridgeIcon(
                              StarBridgeIconSemantic.notifications,
                              size: tokens.icons.medium,
                              color: tokens.colors.success,
                            ),
                          ),
                          SizedBox(width: tokens.space.sm),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                SizedBox(height: tokens.space.xxs),
                                Text(
                                  message,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: tokens.colors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: tokens.space.xs),
                          StarBridgeIconAction(
                            controlKey: const Key(
                              'starbridge-notification-close',
                            ),
                            label: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onActivate: onDismiss,
                            icon: StarBridgeIcon(
                              StarBridgeIconSemantic.windowClose,
                              size: tokens.icons.small,
                              color: tokens.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
