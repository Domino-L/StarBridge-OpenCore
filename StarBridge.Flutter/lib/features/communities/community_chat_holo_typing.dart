import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'community_chat_holo_effects.dart';

/// The holo send button "charges" from left to right once there is something
/// to send (220 ms) and drains when the draft empties (user 2026-10-29).
/// [idle] is the same button without an action, drawn underneath.
class CommunityChatSendCharge extends StatelessWidget {
  const CommunityChatSendCharge({
    required this.charged,
    required this.idle,
    required this.child,
    super.key,
  });

  final bool charged;
  final Widget idle, child;

  @override
  Widget build(BuildContext context) {
    final reduce = resolveStarBridgeInteraction(context).reduceMotion;
    final light = communityChatHoloLight(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: charged ? 1 : 0),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Stack(
        fit: StackFit.passthrough,
        children: [
          if (value < 1) ExcludeSemantics(child: IgnorePointer(child: idle)),
          ClipRect(clipper: _Charge(value), child: child),
          if (value > 0 && value < 1)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(width: 2, color: light),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Charge extends CustomClipper<Rect> {
  const _Charge(this.value);
  final double value;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * value, size.height);
  @override
  bool shouldReclip(_Charge old) => old.value != value;
}

/// While typing only: a faint light runs along the bottom edge of the
/// field, and stops 0.6 s after the last key.
class CommunityChatTypingFlow extends StatefulWidget {
  const CommunityChatTypingFlow({
    required this.controller,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  State<CommunityChatTypingFlow> createState() => _TypingFlowState();
}

class _TypingFlowState extends State<CommunityChatTypingFlow>
    with SingleTickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  Timer? _quiet;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CommunityChatTypingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _text = widget.controller.text;
    }
  }

  void _changed() {
    final text = widget.controller.text;
    if (text == _text) return;
    _text = text;
    if (text.isEmpty || resolveStarBridgeInteraction(context).reduceMotion) {
      _stop();
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    _quiet?.cancel();
    _quiet = Timer(const Duration(milliseconds: 600), _stop);
  }

  void _stop() {
    _quiet?.cancel();
    if (!mounted) return;
    _flow
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _quiet?.cancel();
    widget.controller.removeListener(_changed);
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = communityChatHoloLight(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 10,
          right: 10,
          bottom: 0,
          height: 1,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _flow,
              builder: (context, _) => _flow.isAnimating
                  ? CustomPaint(painter: _FlowPainter(_flow.value, light))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowPainter extends CustomPainter {
  const _FlowPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * .22;
    final left = progress * (size.width + width) - width;
    final rect = Rect.fromLTWH(left, 0, width, size.height);
    final soft = color.withValues(alpha: .6);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [soft.withValues(alpha: 0), soft, soft.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.progress != progress;
}
