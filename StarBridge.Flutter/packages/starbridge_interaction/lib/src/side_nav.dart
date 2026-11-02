import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';
import 'tooltip.dart';

@immutable
class SideNavItem {
  const SideNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badge,
    this.trailing,
  });

  /// Geometry-only entry for a client-owned layout. Never renders a glyph.
  const SideNavItem.anchor(this.id)
    : label = '',
      icon = null,
      badge = null,
      trailing = null;

  final String id;
  final String label;
  final IconData? icon;

  /// Attention count shown as a static badge (0 / null hides it).
  final int? badge;

  /// Short text on the right (e.g. "即将推出").
  final String? trailing;
}

@immutable
class SideNavSection {
  const SideNavSection({required this.items, this.title, this.nested = false});

  final String? title;
  final List<SideNavItem> items;

  /// Indented shortcut rows (e.g. organisation shortcuts under 社区组织).
  final bool nested;
}

/// Geometry and focus hooks; commands, content and selection remain owned by
/// the host. Register each id exactly once, inside the corresponding region.
class SideNavLayout {
  const SideNavLayout._(this._state);
  final SuiteSideNavState _state;
  ScrollController get scrollController => _state._scroll;
  Key get viewportKey => _state._viewportKey;
  Widget anchor(String id, Widget child) =>
      KeyedSubtree(key: _state._keyFor(id), child: child);
  FocusNode focusNode(String id) => _state._focusFor(id);
  void finishMotion() => _state._settle();
  void focus(String id) {
    focusNode(id).requestFocus();
    final context = _state._keys[id]?.currentContext;
    if (context != null && _state._inScroll(id)) {
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }
}

/// The client's side navigation: a home row, a scrolling primary region
/// (with optional nested shortcut sections) and a pinned personal region,
/// all sharing ONE selection indicator.
///
/// - The indicator travels between regions (primary ↔ shortcuts ↔
///   personal) in the suite's manner: rail stretches over both rows then
///   settles, scan fades and locks with one sweep, glow slides and ripples
///   once on landing, standard jumps.
/// - It follows the target while the primary region scrolls (no animation)
///   and is clipped to that region while the target is inside it.
/// - Selecting home fades the indicator out where it is (home has its own
///   selected row); leaving home fades it in on the target, never sliding in
///   from nowhere.
/// - [compact] narrows the bar to icons (labels become tooltips); the width
///   change animates, the indicator re-measures every frame and does not
///   replay a selection effect.
/// - ↑/↓ move through every row in order and select instantly; keyboard and
///   reduced motion never animate. New targets retarget from the current
///   position without queueing.
class SuiteSideNav extends StatefulWidget {
  const SuiteSideNav({
    required this.home,
    required this.primary,
    required this.personal,
    required this.selectedId,
    required this.onSelect,
    this.compact = false,
    this.personalTitle = '个人空间',
    super.key,
  }) : layoutBuilder = null,
       changeSource = null;

  /// Reuses the approved indicator without replacing client-owned rows,
  /// breakpoints, glyphs, badges, nested panels or asynchronous navigation.
  /// [selectedId] is the confirmed business projection, never an optimistic
  /// clicked id. An unregistered id hides the indicator (e.g. a nested panel
  /// with its own selection). Standard keeps the host's original chrome.
  factory SuiteSideNav.tracked({
    required String homeId,
    required List<String> primaryIds,
    required List<String> personalIds,
    required String selectedId,
    required InteractionSource changeSource,
    required Widget Function(BuildContext, SideNavLayout) layoutBuilder,
    Key? key,
  }) => SuiteSideNav._tracked(
    home: SideNavItem.anchor(homeId),
    primary: [
      SideNavSection(items: primaryIds.map(SideNavItem.anchor).toList()),
    ],
    personal: personalIds.map(SideNavItem.anchor).toList(),
    selectedId: selectedId,
    changeSource: changeSource,
    layoutBuilder: layoutBuilder,
    key: key,
  );

  const SuiteSideNav._tracked({
    required this.home,
    required this.primary,
    required this.personal,
    required this.selectedId,
    required this.changeSource,
    required this.layoutBuilder,
    super.key,
  }) : onSelect = _noSelection,
       compact = false,
       personalTitle = '';

  static void _noSelection(String id, InteractionSource source) {}

  final SideNavItem home;
  final List<SideNavSection> primary;
  final List<SideNavItem> personal;
  final String selectedId;
  final void Function(String id, InteractionSource source) onSelect;
  final bool compact;
  final String personalTitle;
  final Widget Function(BuildContext, SideNavLayout)? layoutBuilder;
  final InteractionSource? changeSource;

  @override
  State<SuiteSideNav> createState() => SuiteSideNavState();
}

enum _Mode { idle, stretch, slide, fade, fadeIn, fadeOut }

class SuiteSideNavState extends State<SuiteSideNav>
    with TickerProviderStateMixin {
  final _navKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _keys = <String, GlobalKey>{};
  final _focus = <String, FocusNode>{};
  final _scroll = ScrollController();
  final _repaint = _Repaint();

  late final _move = AnimationController(vsync: this)
    ..addListener(_onMoveTick)
    ..addStatusListener(_onMoveStatus);
  late final _sweep = AnimationController(vsync: this);
  late final _ring = AnimationController(vsync: this);
  late final _width = AnimationController(
    vsync: this,
    value: widget.compact ? 1 : 0,
  );

  late String _target = widget.selectedId;
  Rect? _from;
  bool _fromInScroll = false;
  _Mode _mode = _Mode.idle;
  bool _ringFired = true;
  InteractionSource _pending = InteractionSource.programmatic;
  InteractionSuite? _previousSuite;

  static const _wide = 208.0;
  static const _narrow = 60.0;

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);
  FocusNode _focusFor(String id) =>
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'nav-$id'));

  List<SideNavItem> get _order => [
    widget.home,
    for (final s in widget.primary) ...s.items,
    ...widget.personal,
  ];

  bool _isHome(String id) => id == widget.home.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_repaint.ping);
    _width.addListener(_repaint.ping);
    for (final c in [_move, _sweep, _ring]) {
      c.addListener(_repaint.ping);
    }
  }

  @override
  void didUpdateWidget(SuiteSideNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _retarget(widget.selectedId, widget.changeSource ?? _pending);
    } else if (widget.changeSource == InteractionSource.keyboard &&
        oldWidget.changeSource != widget.changeSource) {
      _settle();
    }
    _pending = InteractionSource.programmatic;
    if (oldWidget.compact != widget.compact) {
      final data = InteractionScope.of(context);
      final to = widget.compact ? 1.0 : 0.0;
      if (!data.animates) {
        _width.value = to;
      } else {
        _width.duration = const Duration(milliseconds: 220);
        _width.animateTo(to, curve: SuiteMotion.curve);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = InteractionScope.of(context);
    if (!data.animates || _previousSuite != data.suite) {
      _settle();
      _width.value = widget.compact ? 1 : 0;
    }
    _previousSuite = data.suite;
  }

  @override
  void dispose() {
    _move.dispose();
    _sweep.dispose();
    _ring.dispose();
    _width.dispose();
    _scroll.dispose();
    _repaint.dispose();
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _settle() {
    _move.stop();
    _sweep.reset();
    _ring.reset();
    _from = null;
    _mode = _Mode.idle;
    _repaint.ping();
  }

  /// Rect of row [id] in nav coordinates (live: follows scrolling/resizing).
  Rect? rectOf(String id) {
    final nav = _attachedBox(_navKey);
    final box = _attachedBox(_keys[id]);
    if (nav == null ||
        box == null ||
        !box.attached ||
        !box.hasSize ||
        !nav.hasSize) {
      return null;
    }
    // A recycled/sliver row can retain its GlobalKey context during the frame
    // in which it leaves the render tree. Never measure detached or reparented
    // rows against the old navigation ancestor.
    RenderObject? ancestor = box;
    while (ancestor != null && ancestor != nav) {
      ancestor = ancestor.parent;
    }
    if (ancestor != nav) return null;
    return box.localToGlobal(Offset.zero, ancestor: nav) & box.size;
  }

  static RenderBox? _attachedBox(GlobalKey? key) {
    final element = key?.currentContext;
    // findRenderObject asserts on inactive Elements, which can still be
    // mounted until end-of-frame cleanup. The public renderObject getter lets
    // us reject their detached render tree before reading its geometry.
    final object = element is Element ? element.renderObject : null;
    return object is RenderBox && object.attached ? object : null;
  }

  Rect? get _viewport {
    final nav = _attachedBox(_navKey);
    final vp = _attachedBox(_viewportKey);
    if (nav == null || vp == null || !vp.hasSize) return null;
    return vp.localToGlobal(Offset.zero, ancestor: nav) & vp.size;
  }

  bool _inScroll(String id) =>
      !_isHome(id) && !widget.personal.any((p) => p.id == id);

  void _retarget(String id, InteractionSource source) {
    final data = InteractionScope.of(context);
    final current = indicatorRect;
    final wasHome = _isHome(_target);
    final previous = _target;
    _target = id;
    if (!_order.any((entry) => entry.id == id) ||
        !data.animates ||
        source == InteractionSource.keyboard ||
        data.suite == InteractionSuite.standard) {
      _settle();
      return;
    }
    _sweep.reset();
    _ring.reset();
    if (_isHome(id)) {
      // Fade out where the indicator is; home shows its own selected row.
      if (current == null) return _settle();
      _from = current;
      _fromInScroll = _inScroll(previous);
      _mode = _Mode.fadeOut;
      _move.duration = const Duration(milliseconds: 160);
      _move.forward(from: 0);
      return;
    }
    if (wasHome || current == null) {
      _from = null;
      _mode = _Mode.fadeIn;
      _move.duration = const Duration(milliseconds: 180);
      _move.forward(from: 0);
      return;
    }
    final m = data.motion;
    _from = current;
    _fromInScroll = _inScroll(previous);
    switch (data.suite) {
      case InteractionSuite.rail:
        _mode = _Mode.stretch;
        _move.duration = m.stretch + m.navigate;
      case InteractionSuite.scan:
        _mode = _Mode.fade;
        _move.duration = m.fade;
      case InteractionSuite.glow:
        _mode = _Mode.slide;
        _ringFired = false;
        _move.duration = m.navigate;
      case InteractionSuite.standard:
        break;
    }
    _move.forward(from: 0);
  }

  void _onMoveTick() {
    if (_mode != _Mode.slide || _ringFired || !mounted) return;
    final data = InteractionScope.of(context);
    final total = _move.duration!.inMicroseconds;
    if (total > 0 &&
        _move.value * total >= data.motion.ringDelay.inMicroseconds) {
      _ringFired = true;
      _ring
        ..duration = data.motion.ring
        ..forward(from: 0);
    }
  }

  void _onMoveStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_mode == _Mode.fade) {
      final data = InteractionScope.of(context);
      _sweep
        ..duration = data.motion.sweep
        ..forward(from: 0);
    }
    _from = null;
    _mode = _Mode.idle;
    _repaint.ping();
  }

  /// The indicator rect now (null when hidden, e.g. on home).
  Rect? get indicatorRect {
    final to = _isHome(_target) ? null : rectOf(_target);
    final from = _from;
    final t = _move.value;
    switch (_mode) {
      case _Mode.idle:
        return to;
      case _Mode.fadeIn:
        return to;
      case _Mode.fadeOut || _Mode.fade:
        return from;
      case _Mode.stretch:
        if (from == null || to == null) return to;
        final m = InteractionScope.of(context).motion;
        final total = (m.stretch + m.navigate).inMicroseconds;
        final split = total == 0 ? 0.0 : m.stretch.inMicroseconds / total;
        final union = from.expandToInclude(to);
        return t < split
            ? Rect.lerp(from, union, SuiteMotion.curve.transform(t / split))
            : Rect.lerp(
                union,
                to,
                SuiteMotion.curve.transform((t - split) / (1 - split)),
              );
      case _Mode.slide:
        if (from == null || to == null) return to;
        return Rect.lerp(from, to, SuiteMotion.curve.transform(t));
    }
  }

  double get _opacity => switch (_mode) {
    _Mode.fadeOut || _Mode.fade => 1 - _move.value,
    _Mode.fadeIn => _move.value,
    _ => _isHome(_target) ? 0 : 1,
  };

  /// Clip for the indicator: the scrolling region while both ends are in
  /// it (or the idle target is), otherwise the whole bar.
  Rect? get _clip {
    final vp = _viewport;
    if (vp == null) return null;
    final targetIn = _inScroll(_target);
    final moving = _from != null && _mode != _Mode.idle;
    if (moving ? (targetIn && _fromInScroll) : targetIn) return vp;
    return null;
  }

  void _activate(String id, InteractionSource source) {
    if (id == widget.selectedId) return;
    _pending = source;
    widget.onSelect(id, source);
  }

  void _step(int delta) {
    final order = _order;
    final i = order.indexWhere((e) => e.id == widget.selectedId);
    final next = (i + delta).clamp(0, order.length - 1);
    if (next == i) return;
    final id = order[next].id;
    _focusFor(id).requestFocus();
    final ctx = _keys[id]?.currentContext;
    if (ctx != null && _inScroll(id)) {
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
    _activate(id, InteractionSource.keyboard);
  }

  /// Scrolls the primary region (lab demos and tests).
  ScrollController get scrollController => _scroll;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    if (widget.layoutBuilder != null) {
      // The host supplies sizing and all commands. Paint-only siblings cannot
      // intercept pointer/focus/semantics or become a second navigation owner.
      return SizedBox(
        key: _navKey,
        child: _LayoutWatcher(
          onLayout: _repaint.ping,
          child: Stack(
            children: [
              if (data.suite != InteractionSuite.standard)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _NavIndicator(
                          this,
                          data,
                          _repaint,
                          front: false,
                        ),
                      ),
                    ),
                  ),
                ),
              widget.layoutBuilder!(context, SideNavLayout._(this)),
              if (data.suite != InteractionSuite.standard)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _NavIndicator(
                          this,
                          data,
                          _repaint,
                          front: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final p = data.palette;
    final theme = Theme.of(context).textTheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _NavStep(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _NavStep(-1),
      },
      child: Actions(
        actions: {
          _NavStep: CallbackAction<_NavStep>(
            onInvoke: (i) {
              _step(i.delta);
              return null;
            },
          ),
        },
        child: AnimatedBuilder(
          animation: _width,
          builder: (context, _) {
            final w = _wide + (_narrow - _wide) * _width.value;
            final labels = (1 - _width.value * 1.6).clamp(0.0, 1.0);
            final compact = _width.value > 0.5;
            Widget row(SideNavItem item, {bool nested = false}) => _row(
              context,
              data,
              item,
              labels: labels,
              compact: compact,
              nested: nested,
            );
            return SizedBox(
              key: _navKey,
              width: w,
              child: _LayoutWatcher(
                onLayout: _repaint.ping,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _NavIndicator(
                            this,
                            data,
                            _repaint,
                            front: false,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _homeRow(context, data, labels, compact),
                        Divider(
                          height: 9,
                          color: p.border.withValues(alpha: 0.5),
                        ),
                        Expanded(
                          child: ListView(
                            key: _viewportKey,
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            children: [
                              for (final s in widget.primary) ...[
                                if (s.title != null && labels > 0)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      0,
                                      3,
                                    ),
                                    child: Opacity(
                                      opacity: labels,
                                      child: Text(
                                        s.title!,
                                        maxLines: 1,
                                        style: theme.labelSmall?.copyWith(
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final item in s.items) ...[
                                  row(item, nested: s.nested),
                                  const SizedBox(height: 2),
                                ],
                              ],
                            ],
                          ),
                        ),
                        Divider(
                          height: 9,
                          color: p.border.withValues(alpha: 0.5),
                        ),
                        if (labels > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 0, 3),
                            child: Opacity(
                              opacity: labels,
                              child: Text(
                                widget.personalTitle,
                                maxLines: 1,
                                style: theme.labelSmall?.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 2,
                            children: [
                              for (final item in widget.personal) row(item),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _NavIndicator(
                              this,
                              data,
                              _repaint,
                              front: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _homeRow(
    BuildContext context,
    InteractionData data,
    double labels,
    bool compact,
  ) {
    final p = data.palette;
    final home = widget.home;
    final selected = _isHome(widget.selectedId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: KeyedSubtree(
        key: _keyFor(home.id),
        child: SuitePressable(
          kind: PressableKind.row,
          selected: selected,
          focusNode: _focusFor(home.id),
          minHeight: 44,
          padding: EdgeInsets.only(left: compact ? 0 : 12),
          semanticLabel: home.label,
          onActivate: (s) => _activate(home.id, s),
          builder: (context, v) => Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                home.icon,
                size: 20,
                color: selected ? p.edge() : v.foreground,
              ),
              if (labels > 0) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Opacity(
                    opacity: labels,
                    child: Text(
                      home.label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: selected ? p.textPrimary : v.foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    InteractionData data,
    SideNavItem item, {
    required double labels,
    required bool compact,
    required bool nested,
  }) {
    final p = data.palette;
    final selected = item.id == widget.selectedId;
    final badge = item.badge ?? 0;
    Widget content = SuitePressable(
      kind: PressableKind.navItem,
      selected: selected,
      focusNode: _focusFor(item.id),
      minHeight: nested ? 34 : 40,
      padding: EdgeInsets.only(
        left: compact ? 0 : (nested ? 30 : 14),
        right: compact ? 0 : 8,
      ),
      semanticLabel: badge > 0 ? '${item.label}，$badge 条未读' : item.label,
      onActivate: (s) => _activate(item.id, s),
      builder: (context, v) {
        final iconColor = selected
            ? (data.suite == InteractionSuite.standard
                  ? p.accent
                  : data.suite == InteractionSuite.scan
                  ? p.textPrimary
                  : p.edge())
            : data.suite == InteractionSuite.rail
            ? Color.lerp(v.foreground, p.edge(), v.hover)!
            : v.foreground;
        final icon = Transform.translate(
          offset: Offset(
            data.suite == InteractionSuite.rail && !compact ? 4 * v.hover : 0,
            0,
          ),
          child: Icon(
            item.icon,
            size: nested ? 16 : 18,
            color: iconColor,
            shadows: selected && data.suite == InteractionSuite.glow
                ? [Shadow(color: p.edge(0.6), blurRadius: 4)]
                : null,
          ),
        );
        final dot = badge > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.danger,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: p.onDanger,
                  ),
                ),
              )
            : null;
        if (compact) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Center(child: icon),
              if (dot != null) Positioned(right: 8, top: 4, child: dot),
            ],
          );
        }
        return Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: labels,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: nested ? 13 : 14,
                    color: v.foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (item.trailing != null && labels > 0.5)
              Text(
                item.trailing!,
                style: TextStyle(fontSize: 10.5, color: p.textDisabled),
              ),
            ?dot,
          ],
        );
      },
    );
    if (compact) content = SuiteTooltip(message: item.label, child: content);
    return KeyedSubtree(key: _keyFor(item.id), child: content);
  }
}

class _NavStep extends Intent {
  const _NavStep(this.delta);
  final int delta;
}

class _Repaint extends ChangeNotifier {
  bool _disposed = false;
  bool _queued = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void ping() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_queued) return;
      _queued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }
}

class _NavIndicator extends CustomPainter {
  _NavIndicator(this.s, this.data, Listenable repaint, {required this.front})
    : super(repaint: repaint);

  final SuiteSideNavState s;
  final InteractionData data;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = s.indicatorRect;
    final opacity = s._opacity;
    if (rect == null || opacity <= 0) return;
    final p = data.palette;
    final suite = data.suite;
    final rrect = suiteRadius(suite, 6).toRRect(rect);
    Color a(Color c) => c.withValues(alpha: c.a * opacity);
    canvas.save();
    final clip = s._clip;
    if (clip != null) canvas.clipRect(clip);
    if (!front) {
      switch (suite) {
        case InteractionSuite.standard:
          canvas.drawRRect(rrect, Paint()..color = a(p.selectedFill));
          paintSideBar(canvas, rect, a(p.accent));
        case InteractionSuite.rail:
          paintRailFace(
            canvas,
            rrect,
            p.accent,
            (p.isDark ? 0.30 : 0.20) * opacity,
          );
          paintSideBar(
            canvas,
            rect,
            a(p.edge()),
            glow: p.isDark && opacity > 0.5 ? p.edge() : null,
          );
        case InteractionSuite.scan:
          canvas.drawRRect(
            rrect,
            Paint()..color = a(p.selectedFill.withValues(alpha: 0.85)),
          );
          canvas.drawRect(
            Rect.fromLTWH(rect.left, rect.top + 8, 3, rect.height - 16),
            Paint()..color = a(p.accent),
          );
        case InteractionSuite.glow:
          paintSideGlow(
            canvas,
            rrect,
            p.accent,
            (p.isDark ? 0.38 : 0.26) * opacity,
          );
          if (p.isDark) {
            paintGlowStrokes(canvas, rrect, p.accent, 0.25 * opacity);
          }
          paintSideBar(
            canvas,
            rect,
            a(p.edge()),
            glow: opacity > 0.5 ? p.edge() : null,
          );
      }
    } else {
      if (suite == InteractionSuite.scan) {
        paintBrackets(canvas, rect.deflate(3), color: a(p.edge()));
        final sweep = s._sweep.value;
        if (sweep > 0 && sweep < 1) {
          canvas.save();
          canvas.clipRRect(rrect);
          final e = SuiteMotion.curve.transform(sweep);
          paintBeam(
            canvas,
            rect,
            e,
            p.isDark
                ? const Color(0xFFAAE4FF).withValues(alpha: 0.75)
                : p.accent.withValues(alpha: 0.3),
          );
          paintScanLine(canvas, rect, e, p.edge());
          canvas.restore();
        }
      }
      final ring = s._ring.value;
      if (suite == InteractionSuite.glow && ring > 0 && ring < 1) {
        final target = s.rectOf(s._target) ?? rect;
        paintRing(
          canvas,
          Offset(target.left + 2, target.center.dy),
          ring,
          p.edge(),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavIndicator old) => old.data != data;
}

/// Pings after every layout of its child so the indicator follows resizes.
class _LayoutWatcher extends SingleChildRenderObjectWidget {
  const _LayoutWatcher({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWatcher(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderWatcher r) =>
      r.onLayout = onLayout;
}

class _RenderWatcher extends RenderProxyBox {
  _RenderWatcher(this.onLayout);
  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    SchedulerBinding.instance.addPostFrameCallback((_) => onLayout());
  }
}
