import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pressable.dart';
import 'suite.dart';

/// A header that opens and closes a body (settings groups, details,
/// advanced options). Opening changes layout on purpose, so the height
/// animates; everything else is clip and paint.
///
/// The body stays mounted while collapsed (text being edited, scroll
/// position and form state are kept) but is excluded from focus and
/// semantics, and its tickers are muted.
///
/// Rail: a rail grows down the body's leading edge as it opens. Scan: a
/// line leads the reveal and the header brackets lock when fully open.
/// Glow: the body fades in under a soft header light. Standard: a plain
/// size change. Closing is shorter than opening. Keyboard and reduced
/// motion toggle instantly.
class SuiteExpander extends StatefulWidget {
  const SuiteExpander({
    required this.title,
    required this.expanded,
    required this.onChanged,
    required this.child,
    this.subtitle,
    this.maintainState = true,
    this.focusNode,
    this.titleStyle,
    this.subtitleStyle,
    this.headerPadding = const EdgeInsets.only(left: 12, right: 8),
    this.bodyPadding = const EdgeInsets.fromLTRB(14, 6, 8, 10),
    this.headerMinHeight = 40,
    this.headerBuilder,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool expanded;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final bool maintainState;
  final FocusNode? focusNode;
  final TextStyle? titleStyle, subtitleStyle;
  final EdgeInsetsGeometry headerPadding, bodyPadding;
  final double headerMinHeight;

  /// Presentation only, inside the existing press/focus/semantics owner.
  /// Do not add another tap target here. [open] is the current reveal progress.
  /// Omitting this keeps the original suite header unchanged.
  final Widget Function(
    BuildContext context,
    PressableVisual visual,
    double open,
  )?
  headerBuilder;

  @override
  State<SuiteExpander> createState() => _SuiteExpanderState();
}

class _SuiteExpanderState extends State<SuiteExpander>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
  );
  InteractionSource _source = InteractionSource.programmatic;
  final _headerFocus = FocusNode(debugLabel: 'suite-expander-header');
  final _bodyFocus = FocusNode(
    debugLabel: 'suite-expander-body',
    // Track descendant focus for collapse without making an inline body its
    // own traversal scope. An empty scope can otherwise become a dead Tab stop.
    skipTraversal: true,
  );

  @override
  void didUpdateWidget(SuiteExpander oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    if (!widget.expanded && _bodyFocus.hasFocus) {
      if (widget.onChanged != null) {
        (widget.focusNode ?? _headerFocus).requestFocus();
      } else {
        _bodyFocus.unfocus();
      }
    }
    final data = InteractionScope.of(context);
    final target = widget.expanded ? 1.0 : 0.0;
    if (!data.animates || _source == InteractionSource.keyboard) {
      _t.value = target;
    } else {
      _t.duration = widget.expanded
          ? (data.suite == InteractionSuite.scan
                ? const Duration(milliseconds: 300)
                : const Duration(milliseconds: 240))
          : const Duration(milliseconds: 150);
      _t.animateTo(target, curve: Curves.linear);
    }
    _source = InteractionSource.programmatic;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates) {
      _t.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _headerFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final theme = Theme.of(context).textTheme;
    final header = SuitePressable(
      kind: PressableKind.row,
      minHeight: widget.headerMinHeight,
      padding: widget.headerPadding,
      focusNode: widget.focusNode ?? _headerFocus,
      semanticLabel: widget.title,
      excludeChildSemantics: true,
      onActivate: widget.onChanged == null
          ? null
          : (s) {
              _source = s;
              widget.onChanged!(!widget.expanded);
            },
      builder: (context, v) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final open = _t.value;
          return CustomPaint(
            foregroundPainter: data.suite == InteractionSuite.scan && open >= 1
                ? _HeaderLock(p)
                : null,
            child:
                (widget.headerBuilder == null
                    ? null
                    : ExcludeFocus(
                        child: IgnorePointer(
                          child: widget.headerBuilder!(context, v, open),
                        ),
                      )) ??
                Row(
                  children: [
                    Transform.rotate(
                      angle:
                          -math.pi /
                          2 *
                          (1 - SuiteMotion.curve.transform(open)),
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: v.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style:
                                widget.titleStyle ??
                                theme.bodyMedium?.copyWith(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              style:
                                  widget.subtitleStyle ??
                                  theme.bodySmall?.copyWith(
                                    color: p.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
          );
        },
      ),
    );

    final body = AnimatedBuilder(
      animation: _t,
      child: Padding(
        padding: widget.bodyPadding,
        child: Focus(
          focusNode: _bodyFocus,
          // Skip only this tracking node, never its real child controls. The
          // containing page/dialog retains its original traversal boundary.
          skipTraversal: true,
          child: widget.child,
        ),
      ),
      builder: (context, child) {
        final v = _t.value;
        final opening = _t.status != AnimationStatus.reverse;
        final c = opening
            ? SuiteMotion.curve.transform(v)
            : SuiteMotion.exitCurve.transform(v);
        final closed = v <= 0;
        if (closed && !widget.maintainState) return const SizedBox.shrink();
        // Keep the body's element ancestry fixed at rest, during reversal,
        // and across suite changes. Inserting/removing Opacity only while
        // moving disposes native form fields despite maintainState=true.
        final opacity = !closed && v < 1
            ? switch (data.suite) {
                InteractionSuite.glow => c,
                InteractionSuite.rail => (c * 1.4).clamp(0.0, 1.0),
                InteractionSuite.scan || InteractionSuite.standard => 1.0,
              }
            : 1.0;
        final content = Opacity(opacity: opacity, child: child);
        return IgnorePointer(
          ignoring: !widget.expanded,
          child: Offstage(
            offstage: closed,
            child: ExcludeFocus(
              excluding: !widget.expanded,
              child: ExcludeSemantics(
                excluding: !widget.expanded,
                child: TickerMode(
                  enabled: widget.expanded,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: c,
                      child: CustomPaint(
                        foregroundPainter: _BodyMarks(
                          data,
                          c,
                          opening && v < 1,
                        ),
                        child: content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: widget.expanded,
          value: widget.subtitle,
          child: header,
        ),
        body,
      ],
    );
  }
}

class _BodyMarks extends CustomPainter {
  _BodyMarks(this.data, this.open, this.moving);
  final InteractionData data;
  final double open;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final visible = size.height * open;
    switch (data.suite) {
      case InteractionSuite.rail:
        // Rail along the leading edge, grown to the revealed height.
        canvas.drawRect(
          Rect.fromLTWH(2, 0, 2, visible),
          Paint()..color = p.edge(0.7),
        );
      case InteractionSuite.scan:
        if (moving) {
          canvas.drawRect(
            Rect.fromLTWH(0, visible - 1, size.width, 2),
            Paint()..color = p.edge(0.9),
          );
        }
      case InteractionSuite.glow:
        if (moving) {
          final r = Rect.fromLTWH(0, 0, size.width, math.min(visible, 40));
          canvas.drawRect(
            r,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.light(0.14 * (1 - open)), p.light(0)],
              ).createShader(r),
          );
        }
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_BodyMarks old) =>
      old.open != open || old.moving != moving || old.data != data;
}

class _HeaderLock extends CustomPainter {
  _HeaderLock(this.p);
  final InteractionPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    // Only the leading corners: the open group is "locked" without boxing
    // the whole header.
    final paint = Paint()..color = p.edge(0.8);
    canvas.drawRect(const Rect.fromLTWH(-6, -8, 6, 1.5), paint);
    canvas.drawRect(const Rect.fromLTWH(-6, -8, 1.5, 6), paint);
  }

  @override
  bool shouldRepaint(_HeaderLock old) => old.p != p;
}
