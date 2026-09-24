import 'dart:async';

import 'package:flutter/material.dart';

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
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var removed = false;

  void remove() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _StarBridgeNotificationOverlay(
      alignment: alignment,
      title: title,
      message: message,
      duration: duration,
      onDismissed: remove,
    ),
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
    required this.onDismissed,
  });

  final Alignment alignment;
  final String title;
  final String message;
  final Duration duration;
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.tokens.motion;
    _controller.duration = motion.surfaceEnter;
    _controller.reverseDuration = motion.surfaceExit;
    if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) {
      return;
    }
    _closing = true;
    _dismissTimer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
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
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _controller,
          curve: tokens.motion.enterCurve,
          reverseCurve: tokens.motion.exitCurve,
        ),
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: Offset(
                  entersFromRight ? 0.08 : -0.08,
                  entersFromBottom ? 0.06 : -0.06,
                ),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: tokens.motion.enterCurve,
                  reverseCurve: tokens.motion.exitCurve,
                ),
              ),
          child: _StarBridgeNotificationCard(
            title: widget.title,
            message: widget.message,
            onDismiss: _dismiss,
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
  final VoidCallback onDismiss;

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
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed: onDismiss,
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
