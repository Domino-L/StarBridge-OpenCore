import 'package:flutter/material.dart';

import 'busy.dart';
import 'counter.dart';
import 'effect_host.dart';
import 'painters.dart';
import 'pressable.dart';
import 'selection_track.dart';
import 'suite.dart';
import 'surface_transition.dart';

// ---------------------------------------------------------------------------
// 17 · batch action bar
// ---------------------------------------------------------------------------

/// Bar that appears while rows are selected and offers batch actions. The
/// bar animates in/out once (not per selection change); the count updates
/// in place. Selecting or clearing all rows marks them all in the same frame
/// (no row-by-row stagger).
///
/// Rail: slides up with a lit top edge. Scan: forms from a line, corners
/// lock. Glow: fades in with a soft edge light. Standard: fades.
class SuiteBatchBar extends StatefulWidget {
  const SuiteBatchBar({
    required this.count,
    required this.actions,
    required this.onClear,
    this.noun = '项',
    super.key,
  });

  /// Selected count; 0 hides the bar.
  final int count;
  final List<Widget> actions;
  final VoidCallback onClear;
  final String noun;

  @override
  State<SuiteBatchBar> createState() => _SuiteBatchBarState();
}

class _SuiteBatchBarState extends State<SuiteBatchBar>
    with SingleTickerProviderStateMixin {
  late final _anim =
      AnimationController(vsync: this, value: widget.count > 0 ? 1 : 0)
        ..addStatusListener((s) {
          if (mounted) setState(() {});
        });
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.count;
  }

  @override
  void didUpdateWidget(SuiteBatchBar oldWidget) {
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
    return Semantics(
      container: true,
      liveRegion: true,
      label: '已选择 $_shown ${widget.noun}',
      child: SuiteSurfaceTransition(
        animation: _anim,
        kind: SurfaceKind.toast,
        alignment: Alignment.bottomCenter,
        radius: 8,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: p.raised,
            borderRadius: suiteRadius(data.suite, 8),
            border: Border.all(color: p.accent.withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            spacing: 8,
            children: [
              Text(
                '已选择',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary),
              ),
              SuiteCounter(
                value: _shown,
                style: TextStyle(
                  fontFamily: 'Source Code Pro',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              Text(
                widget.noun,
                style: TextStyle(fontSize: 12.5, color: p.textSecondary),
              ),
              const Spacer(),
              ...widget.actions,
              SuitePressable(
                kind: PressableKind.icon,
                minHeight: 28,
                padding: const EdgeInsets.all(5),
                semanticLabel: '取消选择',
                onPressed: widget.onClear,
                child: const Icon(Icons.close, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 18 · sorting, paging, load more
// ---------------------------------------------------------------------------

enum SortDirection { none, ascending, descending }

/// Sortable column header. The active column keeps a static mark (bold
/// label + arrow + suite mark) so the sort can always be read; changing the
/// direction swaps the arrow in the suite's manner. Rail: underline on the
/// active column. Scan: corner marks lock onto it. Glow: a point light.
class SuiteSortHeader extends StatefulWidget {
  const SuiteSortHeader({
    required this.label,
    required this.direction,
    required this.onTap,
    super.key,
  });

  final String label;
  final SortDirection direction;
  final VoidCallback onTap;

  @override
  State<SuiteSortHeader> createState() => _SuiteSortHeaderState();
}

class _SuiteSortHeaderState extends State<SuiteSortHeader>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, value: 1);
  final _fx = GlobalKey<EffectHostState>();
  bool _keyboard = false;

  @override
  void didUpdateWidget(SuiteSortHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction == widget.direction) return;
    final data = InteractionScope.of(context);
    if (!data.animates ||
        _keyboard ||
        data.suite == InteractionSuite.standard) {
      _turn.value = 1;
      _keyboard = false;
      return;
    }
    _turn
      ..duration = data.motion.select
      ..forward(from: 0);
    if (data.suite == InteractionSuite.scan &&
        widget.direction != SortDirection.none) {
      _fx.currentState?.play(
        TransientEffect.bracketFlash,
        duration: const Duration(milliseconds: 360),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _turn.isAnimating) {
      _turn.value = 1;
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final active = widget.direction != SortDirection.none;
    final sortLabel = switch (widget.direction) {
      SortDirection.ascending => '，升序',
      SortDirection.descending => '，降序',
      SortDirection.none => '',
    };
    return Semantics(
      label: '${widget.label}$sortLabel',
      button: true,
      enabled: true,
      // Screen reader activation: same action, instant arrow swap.
      onTap: () {
        _keyboard = true;
        widget.onTap();
      },
      excludeSemantics: true,
      child: EffectHost(
        key: _fx,
        bracketInset: 1,
        bracketLength: 5,
        child: CustomPaint(
          foregroundPainter: active ? _ActiveSortMark(data) : null,
          child: SuitePressable(
            kind: PressableKind.tab,
            minHeight: 30,
            baseRadius: 4,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onActivate: (s) {
              _keyboard = s == InteractionSource.keyboard;
              widget.onTap();
            },
            builder: (context, v) => Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? p.textPrimary : v.foreground,
                  ),
                ),
                AnimatedBuilder(
                  animation: _turn,
                  builder: (context, _) {
                    final c = SuiteMotion.curve.transform(_turn.value);
                    final icon = switch (widget.direction) {
                      SortDirection.ascending => Icons.arrow_upward,
                      SortDirection.descending => Icons.arrow_downward,
                      SortDirection.none => Icons.unfold_more,
                    };
                    final glyph = Icon(
                      icon,
                      size: 13,
                      color: active ? p.accent : p.textDisabled,
                    );
                    if (c >= 1) return glyph;
                    return switch (data.suite) {
                      // Rail: the arrow slides in along its own direction.
                      InteractionSuite.rail => FractionalTranslation(
                        translation: Offset(
                          0,
                          (widget.direction == SortDirection.ascending
                                  ? 0.6
                                  : -0.6) *
                              (1 - c),
                        ),
                        child: Opacity(opacity: c, child: glyph),
                      ),
                      InteractionSuite.glow => Transform.scale(
                        scale: 0.6 + 0.4 * c,
                        child: glyph,
                      ),
                      _ => Opacity(opacity: c, child: glyph),
                    };
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveSortMark extends CustomPainter {
  _ActiveSortMark(this.data);
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(6, size.height - 2, size.width - 12, 2),
          Paint()..color = p.edge(),
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.deflate(1),
          color: p.edge(0.8),
          length: 5,
          width: 1.5,
        );
      case InteractionSuite.glow:
        final r = Rect.fromCenter(
          center: Offset(size.width / 2, size.height),
          width: size.width,
          height: size.height,
        );
        canvas.drawOval(
          r,
          Paint()
            ..shader = RadialGradient(colors: [p.light(0.25), p.light(0)])
                .createShader(r),
        );
      case InteractionSuite.standard:
        canvas.drawRect(
          Rect.fromLTWH(6, size.height - 2, size.width - 12, 2),
          Paint()..color = p.accent,
        );
    }
  }

  @override
  bool shouldRepaint(_ActiveSortMark old) => old.data != data;
}

/// Page selector: ‹ 1 2 3 … › built on [SuiteSelectionTrack] so the current
/// page indicator moves like any other selection. Prev/next disable at the
/// ends.
class SuitePager extends StatelessWidget {
  const SuitePager({
    required this.page,
    required this.pageCount,
    required this.onChanged,
    super.key,
  });

  /// Zero-based page.
  final int page;
  final int pageCount;
  final void Function(int page, InteractionSource source) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, String label, int target) => SuitePressable(
      kind: PressableKind.icon,
      minHeight: 30,
      padding: const EdgeInsets.all(6),
      semanticLabel: label,
      onActivate: target >= 0 && target < pageCount
          ? (s) => onChanged(target, s)
          : null,
      child: Icon(icon, size: 16),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        arrow(Icons.chevron_left, '上一页', page - 1),
        SuiteSelectionTrack(
          style: TrackStyle.segmented,
          items: [
            for (var i = 0; i < pageCount; i++) TrackItem(label: '${i + 1}'),
          ],
          selected: page,
          onChanged: onChanged,
        ),
        arrow(Icons.chevron_right, '下一页', page + 1),
      ],
    );
  }
}

enum LoadMorePhase { idle, loading, failed, end }

/// "Load more" footer. Loading says what is happening; failure keeps the
/// loaded rows and offers retry; the end is stated plainly (no fake extra
/// content).
class SuiteLoadMore extends StatelessWidget {
  const SuiteLoadMore({required this.phase, required this.onLoad, super.key});

  final LoadMorePhase phase;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    return SizedBox(
      height: 40,
      child: Center(
        child: switch (phase) {
          LoadMorePhase.loading => const SuiteBusyLabel('正在加载更多…'),
          LoadMorePhase.end => Text(
            '已经到底了',
            style: TextStyle(fontSize: 12, color: p.textDisabled),
          ),
          LoadMorePhase.idle || LoadMorePhase.failed => Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (phase == LoadMorePhase.failed)
                Text('加载失败', style: TextStyle(fontSize: 12, color: p.danger)),
              SuitePressable(
                kind: PressableKind.secondary,
                minHeight: 28,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                onPressed: onLoad,
                child: Text(
                  phase == LoadMorePhase.failed ? '重试' : '加载更多',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// Plays a one-time entrance for content that is genuinely new (freshly
/// loaded rows). Pass [animate] = false for rows that were already there:
/// rebuilds, recycling and scrolling back never replay it. [order] staggers
/// the first few new rows a little (capped, so large pages don't queue).
class SuiteAppear extends StatefulWidget {
  const SuiteAppear({
    required this.child,
    this.animate = true,
    this.order = 0,
    super.key,
  });

  final Widget child;
  final bool animate;
  final int order;

  @override
  State<SuiteAppear> createState() => _SuiteAppearState();
}

class _SuiteAppearState extends State<SuiteAppear>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.animate) return;
      final data = InteractionScope.of(context);
      if (!data.animates || data.suite == InteractionSuite.standard) return;
      final delay = Duration(milliseconds: 30 * widget.order.clamp(0, 5));
      _t
        ..duration = const Duration(milliseconds: 220) + delay
        ..value = 0
        ..forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _t.isAnimating) {
      _t.value = 1;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        if (_t.value >= 1) return child!;
        final total = _t.duration!.inMilliseconds;
        final delay = 30 * widget.order.clamp(0, 5);
        final local = ((_t.value * total - delay) / (total - delay)).clamp(
          0.0,
          1.0,
        );
        final c = SuiteMotion.curve.transform(local);
        return switch (data.suite) {
          InteractionSuite.rail => Opacity(
            opacity: c,
            child: Transform.translate(
              offset: Offset(-8 * (1 - c), 0),
              child: child,
            ),
          ),
          InteractionSuite.scan => ClipRect(clipper: _Reveal(c), child: child),
          _ => Opacity(opacity: c, child: child),
        };
      },
    );
  }
}

class _Reveal extends CustomClipper<Rect> {
  _Reveal(this.f);
  final double f;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);

  @override
  bool shouldReclip(_Reveal old) => old.f != f;
}

// ---------------------------------------------------------------------------
// 21 · drag to reorder
// ---------------------------------------------------------------------------

/// Decoration for the dragged row of a [ReorderableListView]. The row
/// follows the pointer exactly (Flutter moves it); only its look changes:
/// rail lights the leading edge, scan frames it with brackets, glow lifts it
/// with a soft edge light, standard uses a plain shadow. Use as
/// `proxyDecorator: (child, i, a) => suiteReorderProxy(context, child, a)`.
Widget suiteReorderProxy(
  BuildContext context,
  Widget child,
  Animation<double> animation,
) {
  final data = InteractionScope.of(context);
  // The proxy is built in the overlay, which may sit outside the scope.
  return InteractionScope(
    data: data,
    child: AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = SuiteMotion.curve.transform(animation.value);
        return Material(
          type: MaterialType.transparency,
          child: CustomPaint(
            foregroundPainter: _DragMark(data, t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: data.palette.raised,
                borderRadius: suiteRadius(data.suite, 6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x66000000).withValues(alpha: 0.4 * t),
                    blurRadius: 14 * t,
                    offset: Offset(0, 6 * t),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}

class _DragMark extends CustomPainter {
  _DragMark(this.data, this.t);
  final InteractionData data;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    final rrect = suiteRadius(data.suite, 6).toRRect(rect);
    switch (data.suite) {
      case InteractionSuite.rail:
        paintSideBar(
          canvas,
          rect,
          p.edge(t),
          inset: 6,
          glow: p.isDark ? p.edge(t) : null,
        );
      case InteractionSuite.scan:
        paintBrackets(canvas, rect.inflate(2 * (1 - t)), color: p.edge(t));
      case InteractionSuite.glow:
        paintGlowStrokes(canvas, rrect, p.accent, 0.7 * t);
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_DragMark old) => old.t != t || old.data != data;
}

// ---------------------------------------------------------------------------
// 22 · scrollbar
// ---------------------------------------------------------------------------

/// Scrollbar in the suite's shape: rail is a slim lit bar that thickens on
/// hover/drag, scan a square-ended bar, glow a soft rounded bar. Scrolling
/// itself is untouched (native physics, no extra easing).
class SuiteScrollbar extends StatelessWidget {
  const SuiteScrollbar({
    required this.controller,
    required this.child,
    super.key,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final (thickness, radius, color) = switch (data.suite) {
      InteractionSuite.rail => (4.0, const Radius.circular(1), p.edge(0.7)),
      InteractionSuite.scan => (
        5.0,
        Radius.zero,
        p.accent.withValues(alpha: 0.75),
      ),
      InteractionSuite.glow => (
        6.0,
        const Radius.circular(3),
        p.accent.withValues(alpha: 0.6),
      ),
      InteractionSuite.standard => (
        6.0,
        const Radius.circular(3),
        p.textSecondary.withValues(alpha: 0.5),
      ),
    };
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: thickness,
      radius: radius,
      thumbColor: color,
      trackVisibility:
          data.suite == InteractionSuite.rail ||
          data.suite == InteractionSuite.scan,
      trackColor: p.border.withValues(alpha: 0.18),
      trackBorderColor: Colors.transparent,
      fadeDuration: data.timed(const Duration(milliseconds: 200)),
      child: child,
    );
  }
}
