import 'package:flutter/material.dart';

import 'attachments.dart';
import 'counter.dart';
import 'pressable.dart';
import 'suite.dart';
import 'surface_transition.dart';

enum MessageStatus { sent, sending, failed }

/// One chat message. Only a genuinely new message ([fresh]) plays an
/// entrance, from its own side: rail slides in a short way, scan reveals
/// from its edge, glow fades in with a brief soft light. History, rebuilds
/// and scrolling never replay it. Text is never animated character by
/// character.
///
/// Own messages show their real send state: sending (quiet), failed (danger
/// text plus retry; the message stays so nothing typed is lost), sent.
class SuiteMessageBubble extends StatefulWidget {
  const SuiteMessageBubble({
    required this.text,
    required this.mine,
    this.author,
    this.status = MessageStatus.sent,
    this.fresh = false,
    this.onRetry,
    this.attachments = const [],
    super.key,
  });

  final String text;

  /// Sent files, shown under the text as static rows.
  final List<SuiteAttachment> attachments;
  final bool mine;
  final String? author;
  final MessageStatus status;
  final bool fresh;
  final VoidCallback? onRetry;

  @override
  State<SuiteMessageBubble> createState() => _SuiteMessageBubbleState();
}

class _SuiteMessageBubbleState extends State<SuiteMessageBubble>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    if (!widget.fresh) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final data = InteractionScope.of(context);
      if (!data.animates || data.suite == InteractionSuite.standard) return;
      _t
        ..duration = const Duration(milliseconds: 240)
        ..value = 0
        ..forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) _t.value = 1;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final mine = widget.mine;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: mine ? p.selectedFill : p.raised,
        borderRadius: suiteRadius(data.suite, 8),
        border: Border.all(
          color: widget.status == MessageStatus.failed
              ? p.danger
              : p.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 5,
        children: [
          if (widget.text.isNotEmpty)
            Text(
              widget.text,
              style: TextStyle(fontSize: 13, color: p.textPrimary, height: 1.35),
            ),
          for (final a in widget.attachments) SuiteAttachmentTile(attachment: a),
        ],
      ),
    );
    final status = switch (widget.status) {
      MessageStatus.sent => null,
      MessageStatus.sending => Text(
        '发送中…',
        style: TextStyle(fontSize: 11, color: p.textDisabled),
      ),
      MessageStatus.failed => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Icons.error_outline, size: 13, color: p.danger),
          Text('发送失败', style: TextStyle(fontSize: 11, color: p.danger)),
          SuitePressable(
            kind: PressableKind.icon,
            minHeight: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            onPressed: widget.onRetry,
            child: Text('重试', style: TextStyle(fontSize: 11, color: p.accent)),
          ),
        ],
      ),
    };
    final column = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      spacing: 2,
      children: [
        if (widget.author != null && !mine)
          Text(
            widget.author!,
            style: TextStyle(fontSize: 11, color: p.textSecondary),
          ),
        bubble,
        ?status,
      ],
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _t,
        child: column,
        builder: (context, child) {
          if (_t.value >= 1) return child!;
          final c = SuiteMotion.curve.transform(_t.value);
          final side = mine ? 1.0 : -1.0;
          return switch (data.suite) {
            InteractionSuite.rail => Opacity(
              opacity: c,
              child: Transform.translate(
                offset: Offset(12 * side * (1 - c), 0),
                child: child,
              ),
            ),
            InteractionSuite.scan => ClipRect(
              clipper: _SideReveal(c, fromRight: mine),
              child: child,
            ),
            _ => CustomPaint(
              painter: _SoftLight(p, mine, 0.3 * (1 - c)),
              child: Opacity(opacity: c, child: child),
            ),
          };
        },
      ),
    );
  }
}

class _SideReveal extends CustomClipper<Rect> {
  _SideReveal(this.f, {required this.fromRight});
  final double f;
  final bool fromRight;

  @override
  Rect getClip(Size size) {
    final w = size.width * f;
    return fromRight
        ? Rect.fromLTWH(size.width - w, 0, w, size.height)
        : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_SideReveal old) => old.f != f;
}

class _SoftLight extends CustomPainter {
  _SoftLight(this.p, this.mine, this.alpha);
  final InteractionPalette p;
  final bool mine;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(mine ? size.width : 0, size.height / 2),
      width: size.width,
      height: size.height * 1.6,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [p.light(alpha), p.light(0)])
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SoftLight old) => old.alpha != alpha;
}

/// "↓ N new messages" pill shown while the user reads history. New messages
/// never yank the scroll position; this pill offers the jump instead. It
/// appears once (toast entrance), the count updates in place and, being
/// passive data, coalesces when messages pour in.
class SuiteNewMessagesPill extends StatefulWidget {
  const SuiteNewMessagesPill({
    required this.count,
    required this.onTap,
    super.key,
  });

  final int count;
  final VoidCallback onTap;

  @override
  State<SuiteNewMessagesPill> createState() => _SuiteNewMessagesPillState();
}

class _SuiteNewMessagesPillState extends State<SuiteNewMessagesPill>
    with SingleTickerProviderStateMixin {
  late final _anim =
      AnimationController(vsync: this, value: widget.count > 0 ? 1 : 0)
        ..addStatusListener((_) {
          if (mounted) setState(() {});
        });
  late int _shown = widget.count;

  @override
  void didUpdateWidget(SuiteNewMessagesPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0) _shown = widget.count;
    final show = widget.count > 0;
    if (show == oldWidget.count > 0) return;
    final data = InteractionScope.of(context);
    final d = surfaceDurations(data, SurfaceKind.toast);
    _anim
      ..duration = d.enter
      ..reverseDuration = d.exit;
    if (!data.animates) {
      _anim.value = show ? 1 : 0;
    } else {
      show ? _anim.forward() : _anim.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_anim.isDismissed) return const SizedBox.shrink();
    final data = InteractionScope.of(context);
    final p = data.palette;
    return SuiteSurfaceTransition(
      animation: _anim,
      kind: SurfaceKind.toast,
      alignment: Alignment.bottomCenter,
      radius: 14,
      child: SuitePressable(
        kind: PressableKind.primary,
        baseRadius: 14,
        minHeight: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        semanticLabel: '$_shown 条新消息，跳到最新',
        onPressed: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            const Icon(Icons.arrow_downward, size: 14),
            SuiteCounter(
              value: _shown,
              coalesceDataUpdates: true,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: p.onAccent,
              ),
            ),
            Text('条新消息', style: TextStyle(fontSize: 12.5, color: p.onAccent)),
          ],
        ),
      ),
    );
  }
}
