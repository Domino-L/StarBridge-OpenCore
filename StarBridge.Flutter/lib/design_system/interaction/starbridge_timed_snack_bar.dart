import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';

/// How long a transient message ("已复制", "已取消关注 · 撤销") stays up.
const starBridgeTransientDuration = Duration(milliseconds: 2500);

/// QualityPass ② (user 2026-10-29): transient bars leave on their own after
/// [duration], with a thin line showing the time left. Pointing at the bar
/// pauses the countdown, so an "撤销" can still be reached; leaving resumes it.
///
/// The bar itself is marked `persist` so ScaffoldMessenger's own timer never
/// closes it; [StarBridgeTimedSnackBarContent] closes it with
/// [SnackBarClosedReason.timeout]. With accessible navigation on, the bar
/// stays until dismissed, like Flutter's own bars.
SnackBar starBridgeTimedSnackBar({
  required Widget content,
  Key? key,
  SnackBarAction? action,
  Duration duration = starBridgeTransientDuration,
  SnackBarBehavior? behavior,
  double? width,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool? showCloseIcon,
  VoidCallback? onVisible,
  DismissDirection? dismissDirection,
}) => SnackBar(
  key: key,
  persist: true,
  content: StarBridgeTimedSnackBarContent(duration: duration, child: content),
  action: action,
  behavior: behavior,
  width: width,
  margin: margin,
  padding: padding,
  backgroundColor: backgroundColor,
  shape: shape,
  showCloseIcon: showCloseIcon,
  onVisible: onVisible,
  dismissDirection: dismissDirection,
);

class StarBridgeTimedSnackBarContent extends StatefulWidget {
  const StarBridgeTimedSnackBarContent({
    required this.duration,
    required this.child,
    super.key,
  });

  final Duration duration;
  final Widget child;

  @override
  State<StarBridgeTimedSnackBarContent> createState() =>
      _StarBridgeTimedSnackBarContentState();
}

class _StarBridgeTimedSnackBarContentState
    extends State<StarBridgeTimedSnackBarContent> {
  // A plain periodic timer, not a ticker: the line steps every [_tick], so
  // the bar never keeps the frame pipeline busy while it waits.
  static const _tick = Duration(milliseconds: 50);
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _hovered = false;
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  bool get _holds => _hovered || MediaQuery.accessibleNavigationOf(context);

  void _sync() {
    if (_closed) return;
    if (_holds) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(_tick, (_) => _step());
    }
  }

  void _step() {
    if (!mounted || _closed) return;
    setState(() => _elapsed += _tick);
    if (_elapsed < widget.duration) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    ScaffoldMessenger.maybeOf(context)
        ?.hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
  }

  void _hover(bool value) {
    if (_hovered == value) return;
    _hovered = value;
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bars can be shown from a context without the StarBridge theme (some
    // dialogs and tests); fall back to the Material colour scheme there.
    final tokens = Theme.of(context).extension<StarBridgeTokens>();
    final accent =
        tokens?.colors.accent ?? Theme.of(context).colorScheme.primary;
    final gap = tokens?.space.xs ?? 8;
    final reduced =
        InteractionScope.maybeOf(context)?.reduceMotion ??
        MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      // The line sits in the bar's own bottom padding, so the bar keeps the
      // same size and position as before (no layout shift).
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          // A shrinking line is motion; with reduced motion the bar still
          // times out, it just does not draw the countdown.
          if (!reduced)
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: -gap,
              height: 2,
              child: SizedBox(
                key: const Key('timed-snack-bar-remaining'),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor:
                      (1 -
                              _elapsed.inMicroseconds /
                                  widget.duration.inMicroseconds)
                          .clamp(0.0, 1.0),
                  child: ColoredBox(color: accent.withValues(alpha: 0.7)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
