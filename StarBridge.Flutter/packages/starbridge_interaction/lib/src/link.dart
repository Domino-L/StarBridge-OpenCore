import 'package:flutter/material.dart';

import 'painters.dart';
import 'suite.dart';

/// Inline text link ("查看规则", "组织官网 ↗"). Links never get a press
/// ripple or a celebration: they are text, and the hover cue says "this goes
/// somewhere".
///
/// Standard: underline on hover. Rail: the underline draws in from the left.
/// Scan: small corner marks lock onto the text. Glow: a soft light under the
/// text. [external] adds an ↗ that nudges toward its direction on hover
/// (rail/glow). Focus shows a static ring; keyboard activation (Enter) has
/// no transition. A null [onTap] disables the link (not focusable).
class SuiteLink extends StatefulWidget {
  const SuiteLink({
    required this.label,
    required this.onTap,
    this.external = false,
    this.fontSize = 13,
    this.semanticLabel,
    super.key,
  });

  final String label;

  /// Reports pointer or keyboard so the target can open instantly for keys.
  final ValueChanged<InteractionSource>? onTap;
  final bool external;
  final double fontSize;
  final String? semanticLabel;

  @override
  State<SuiteLink> createState() => _SuiteLinkState();
}

class _SuiteLinkState extends State<SuiteLink>
    with SingleTickerProviderStateMixin {
  late final _hover = AnimationController(vsync: this);
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  void _setHover(bool on) {
    final data = InteractionScope.of(context);
    if (!data.animates || data.suite == InteractionSuite.standard) {
      _hover.value = on ? 1 : 0;
      return;
    }
    _hover.duration = data.motion.hover;
    on ? _hover.forward() : _hover.reverse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _hover.isAnimating) {
      _hover.value = _hover.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(SuiteLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _hover.value = 0;
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final color = !_enabled
        ? p.textDisabled
        : _pressed
        ? p.accent.withValues(alpha: 0.75)
        : p.accentBright;
    return Semantics(
      link: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      onTap: _enabled ? () => widget.onTap!(InteractionSource.keyboard) : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call(InteractionSource.keyboard);
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => _enabled ? _setHover(true) : null,
          onExit: (_) => _setHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTap: _enabled
                ? () => widget.onTap!(InteractionSource.pointer)
                : null,
            child: AnimatedBuilder(
              animation: _hover,
              builder: (context, _) {
                final h = _hover.value;
                final ext = widget.external
                    ? Transform.translate(
                        offset:
                            data.suite == InteractionSuite.rail ||
                                data.suite == InteractionSuite.glow
                            ? Offset(1.5 * h, -1.5 * h)
                            : Offset.zero,
                        child: Icon(
                          Icons.north_east,
                          size: widget.fontSize - 1,
                          color: color,
                        ),
                      )
                    : null;
                return CustomPaint(
                  painter: _LinkUnder(data, h, enabled: _enabled),
                  foregroundPainter: _LinkMarks(data, h, focused: _focused),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        ?ext,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Behind the text: glow's soft light.
class _LinkUnder extends CustomPainter {
  _LinkUnder(this.data, this.h, {required this.enabled});
  final InteractionData data;
  final double h;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || h <= 0 || data.suite != InteractionSuite.glow) return;
    final r = Rect.fromLTWH(0, size.height * 0.35, size.width, size.height);
    canvas.drawOval(
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [data.palette.light(0.22 * h), data.palette.light(0)],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_LinkUnder old) =>
      old.h != h || old.data != data || old.enabled != enabled;
}

/// Over the text: underline (standard/rail/glow), corner marks (scan) and
/// the static focus ring.
class _LinkMarks extends CustomPainter {
  _LinkMarks(this.data, this.h, {required this.focused});
  final InteractionData data;
  final double h;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    if (h > 0) {
      final line = Rect.fromLTWH(2, size.height - 3, size.width - 4, 1.2);
      switch (data.suite) {
        case InteractionSuite.standard:
          canvas.drawRect(line, Paint()..color = p.accentBright);
        case InteractionSuite.rail:
          paintEdgeLine(canvas, line, p.edge(), scale: h, height: 1.2);
        case InteractionSuite.scan:
          paintBrackets(
            canvas,
            rect.inflate(1 + 2 * (1 - h)),
            color: p.edge(h),
            length: 4,
            width: 1.2,
          );
        case InteractionSuite.glow:
          canvas.drawRect(
            line,
            Paint()..color = p.accentBright.withValues(alpha: 0.6 * h),
          );
      }
    }
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectXY(rect.inflate(1), 3, 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  @override
  bool shouldRepaint(_LinkMarks old) =>
      old.h != h || old.data != data || old.focused != focused;
}
