import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

part 'selection_track_paint.dart';

enum TrackStyle { navigation, tabs, segmented }

@immutable
class TrackItem {
  const TrackItem({
    required this.label,
    this.icon,
    this.enabled = true,
    this.id,
  });

  final String label;
  final IconData? icon;
  final bool enabled;

  /// Required and unique for a client-owned tracked layout.
  final String? id;
}

/// Geometry/focus only. Content, capability and confirmed selection stay with
/// the host; the approved painter is shared with the default track.
class SelectionTrackLayout {
  const SelectionTrackLayout._(this._state);
  final SuiteSelectionTrackState _state;
  int _index(String id) =>
      _state.widget.items.indexWhere((item) => item.id == id);
  Widget anchor(String id, Widget child) =>
      KeyedSubtree(key: _state._keys[_index(id)], child: child);
  FocusNode focusNode(String id) => _state._focus[_index(id)];
  void activate(String id, InteractionSource source) =>
      _state._select(_index(id), source);
}

/// A group of mutually exclusive options with one shared selection
/// indicator: side navigation, tabs or a segmented control.
///
/// Rail stretches the indicator over the old and new item, then settles.
/// Scan fades the old indicator, locks onto the new item and sweeps it.
/// Glow slides and drops one ripple on landing. Standard jumps.
/// Keyboard changes and reduced motion always jump; a new target retargets
/// from wherever the indicator currently is.
///
/// Rapid changes keep the same suite feedback, without queueing. Rail
/// retargets its stretch from the current rect. An interrupted scan locks
/// and sweeps the latest target immediately; an interrupted glow starts
/// its one replacement ring immediately, so frequent input cannot starve
/// the feedback by repeatedly restarting an entrance delay.
class SuiteSelectionTrack extends StatefulWidget {
  const SuiteSelectionTrack({
    required this.style,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.layoutBuilder,
    this.changeSource,
    super.key,
  });

  final TrackStyle style;
  final List<TrackItem> items;
  final int selected;
  final void Function(int index, InteractionSource source) onChanged;

  /// An intrinsic-size host layout. Register each stable item id once with
  /// layout.anchor; the host publishes one accessible action per item.
  final Widget Function(BuildContext, SelectionTrackLayout)? layoutBuilder;

  /// Input that produced the confirmed selection (including async guards).
  final InteractionSource? changeSource;

  @override
  State<SuiteSelectionTrack> createState() => SuiteSelectionTrackState();
}

class SuiteSelectionTrackState extends State<SuiteSelectionTrack>
    with TickerProviderStateMixin {
  final _stackKey = GlobalKey();
  late List<GlobalKey> _keys;
  late List<FocusNode> _focus;
  final _hostKeys = <String, GlobalKey>{};
  final _hostFocus = <String, FocusNode>{};
  InteractionSuite? _lastSuite;
  final _rects = <Rect?>[];
  late final _move = AnimationController(vsync: this)
    ..addListener(_onMoveTick)
    ..addStatusListener(_onMoveStatus);
  late final _sweep = AnimationController(vsync: this);
  late final _ring = AnimationController(vsync: this);

  final _layout = ValueNotifier<int>(0);

  Rect? _from;
  late int _target = widget.selected;
  InteractionSource _pendingSource = InteractionSource.programmatic;
  bool _ringFired = true;
  _Mode _mode = _Mode.idle;

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  void _syncKeys() {
    if (widget.layoutBuilder != null) {
      assert(widget.items.every((item) => item.id != null));
      assert(
        widget.items.map((item) => item.id).toSet().length ==
            widget.items.length,
      );
      _keys = [
        for (final item in widget.items)
          _hostKeys.putIfAbsent(item.id!, GlobalKey.new),
      ];
      _focus = [
        for (final item in widget.items)
          _hostFocus.putIfAbsent(
            item.id!,
            () =>
                FocusNode(debugLabel: 'track-${item.id}')
                  ..addListener(_updateFocus),
          ),
      ];
      return;
    }
    _keys = List.generate(widget.items.length, (_) => GlobalKey());
    _focus = List.generate(
      widget.items.length,
      (i) => FocusNode(debugLabel: 'track-$i')..addListener(_updateFocus),
    );
  }

  void _updateFocus() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SuiteSelectionTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hostChanged =
        (oldWidget.layoutBuilder == null) != (widget.layoutBuilder == null);
    if (hostChanged) {
      if (oldWidget.layoutBuilder == null) {
        for (final node in _focus) {
          node.dispose();
        }
      }
      _syncKeys();
      _rects.clear();
      _target = widget.selected;
      _settle();
    } else if (widget.layoutBuilder != null) {
      final orderChanged =
          oldWidget.items.length != widget.items.length ||
          !List.generate(
            widget.items.length,
            (i) => oldWidget.items[i].id == widget.items[i].id,
          ).every((v) => v);
      _syncKeys();
      if (orderChanged) {
        _rects.clear();
        _target = widget.selected;
        _settle();
      }
    } else if (oldWidget.items.length != widget.items.length) {
      for (final f in _focus) {
        f.dispose();
      }
      _syncKeys();
    }
    if (widget.selected != _target) {
      _retarget(widget.selected, widget.changeSource ?? _pendingSource);
    } else if (widget.changeSource == InteractionSource.keyboard &&
        oldWidget.changeSource != widget.changeSource) {
      _settle();
    }
    _pendingSource = InteractionSource.programmatic;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = InteractionScope.of(context);
    if (!data.animates ||
        data.suite == InteractionSuite.standard ||
        (_lastSuite != null && _lastSuite != data.suite)) {
      _settle();
    }
    _lastSuite = data.suite;
  }

  @override
  void dispose() {
    _move.dispose();
    _sweep.dispose();
    _ring.dispose();
    _layout.dispose();
    for (final f in {..._focus, ..._hostFocus.values}) {
      f.dispose();
    }
    super.dispose();
  }

  /// Stops everything and shows the final state.
  void _settle() {
    _move.stop();
    _sweep.reset();
    _ring.reset();
    _from = null;
    _mode = _Mode.idle;
    _layout.value++;
  }

  void _retarget(int index, InteractionSource source) {
    final data = InteractionScope.of(context);
    final current = _currentRect();
    _target = index;
    if (!data.animates ||
        source == InteractionSource.keyboard ||
        data.suite == InteractionSuite.standard ||
        current == null) {
      _settle();
      return;
    }
    final m = data.motion;
    final interrupted =
        _move.isAnimating || _sweep.isAnimating || _ring.isAnimating;
    _from = current;
    _sweep.reset();
    _ring.reset();
    switch (data.suite) {
      case InteractionSuite.rail:
        _mode = _Mode.stretch;
        _move.duration = m.stretch + _slide(m);
      case InteractionSuite.scan:
        if (interrupted) {
          // Do not restart a fade on every click and postpone the sweep
          // forever. Replace the old effect with one on the latest item.
          _move.stop();
          _from = null;
          _mode = _Mode.locked;
          _sweep
            ..duration = m.sweep
            ..forward(from: 0);
          return;
        }
        _mode = _Mode.fade;
        _move.duration = m.fade;
      case InteractionSuite.glow:
        _mode = _Mode.slide;
        _ringFired = interrupted;
        _move.duration = _slide(m);
        if (interrupted) {
          _ring
            ..duration = m.ring
            ..forward(from: 0);
        }
      case InteractionSuite.standard:
        break;
    }
    _move.forward(from: 0);
  }

  Duration _slide(SuiteMotion m) =>
      widget.style == TrackStyle.navigation ? m.navigate : m.select;

  void _onMoveTick() {
    if (_mode == _Mode.slide && !_ringFired) {
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
  }

  void _onMoveStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_mode == _Mode.fade) {
      final data = InteractionScope.of(context);
      _from = null;
      _mode = _Mode.locked;
      _sweep
        ..duration = data.motion.sweep
        ..forward(from: 0);
    } else {
      _from = null;
      _mode = _Mode.idle;
    }
  }

  Rect? _rectOf(int i) => i >= 0 && i < _rects.length ? _rects[i] : null;

  /// The indicator rect right now, including mid-animation positions.
  Rect? _currentRect() {
    final to = _rectOf(_target);
    final from = _from;
    if (to == null) return null;
    if (from == null) return to;
    final t = _move.value;
    switch (_mode) {
      case _Mode.stretch:
        final m = InteractionScope.of(context).motion;
        final total = (m.stretch + _slide(m)).inMicroseconds;
        final split = total == 0 ? 0.0 : m.stretch.inMicroseconds / total;
        final union = from.expandToInclude(to);
        if (t < split) {
          return Rect.lerp(from, union, SuiteMotion.curve.transform(t / split));
        }
        return Rect.lerp(
          union,
          to,
          SuiteMotion.curve.transform((t - split) / (1 - split)),
        );
      case _Mode.slide:
        return Rect.lerp(from, to, SuiteMotion.curve.transform(t));
      case _Mode.fade:
        return from;
      case _Mode.idle || _Mode.locked:
        return to;
    }
  }

  /// The indicator rect right now (tests and lab inspection).
  @visibleForTesting
  Rect? get indicatorRect => _currentRect();

  /// Measured rect of item [i] in track coordinates.
  @visibleForTesting
  Rect? itemRect(int i) => _rectOf(i);

  /// Characteristic feedback remains available even during rapid input.
  @visibleForTesting
  bool get isStretching => _mode == _Mode.stretch && _move.isAnimating;

  @visibleForTesting
  bool get isSweeping => _sweep.isAnimating;

  @visibleForTesting
  bool get isRinging => _ring.isAnimating;

  double get _opacity => _mode == _Mode.fade ? 1 - _move.value : 1;

  void _measure() {
    RenderBox? boxOf(GlobalKey key) {
      final element = key.currentContext;
      final object = element is Element ? element.renderObject : null;
      return object is RenderBox && object.attached && object.hasSize
          ? object
          : null;
    }

    final stack = boxOf(_stackKey);
    if (stack == null) return;
    var changed = _rects.length != _keys.length;
    _rects.length = _keys.length;
    for (var i = 0; i < _keys.length; i++) {
      final box = boxOf(_keys[i]);
      RenderObject? ancestor = box;
      while (ancestor != null && ancestor != stack) {
        ancestor = ancestor.parent;
      }
      final r = box == null || ancestor != stack
          ? null
          : box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
      if (_rects[i] != r) {
        _rects[i] = r;
        changed = true;
      }
    }
    if (changed) _layout.value++;
  }

  void _select(int index, InteractionSource source) {
    if (index < 0 ||
        index >= widget.items.length ||
        !widget.items[index].enabled) {
      return;
    }
    if (source == InteractionSource.keyboard) _settle();
    if (index == widget.selected && widget.layoutBuilder == null) return;
    _pendingSource = source;
    widget.onChanged(index, source);
  }

  void _step(int delta) {
    if (!widget.items.any((item) => item.enabled)) return;
    final focused = _focus.indexWhere((node) => node.hasFocus);
    var i = widget.layoutBuilder != null && focused >= 0
        ? focused
        : widget.selected;
    for (var n = 0; n < widget.items.length; n++) {
      i = (i + delta) % widget.items.length;
      if (i < 0) i += widget.items.length;
      if (widget.items[i].enabled) break;
    }
    _focus[i].requestFocus();
    final targetContext = _keys[i].currentContext;
    if (widget.layoutBuilder != null && targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        targetContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
    _select(i, InteractionSource.keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final vertical = widget.style == TrackStyle.navigation;
    final items = widget.layoutBuilder != null
        ? <Widget>[]
        : [
            for (var i = 0; i < widget.items.length; i++)
              _item(context, data, i),
          ];
    final flex =
        widget.layoutBuilder?.call(context, SelectionTrackLayout._(this)) ??
        (vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: items,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                spacing: widget.style == TrackStyle.tabs ? 2 : 0,
                children: items,
              ));
    final repaint = Listenable.merge([_move, _sweep, _ring, _layout]);
    Widget track = Stack(
      key: _stackKey,
      children: [
        if (widget.layoutBuilder == null ||
            data.suite != InteractionSuite.standard)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _IndicatorPainter(this, data, repaint, front: false),
              ),
            ),
          ),
        _LayoutWatcher(
          onLayout: () {
            if (mounted) _measure();
          },
          child: flex,
        ),
        if (widget.layoutBuilder == null ||
            data.suite != InteractionSuite.standard)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _IndicatorPainter(this, data, repaint, front: true),
                ),
              ),
            ),
          ),
      ],
    );
    track = Shortcuts(
      shortcuts: {
        SingleActivator(
          vertical
              ? LogicalKeyboardKey.arrowDown
              : LogicalKeyboardKey.arrowRight,
        ): const _StepIntent(
          1,
        ),
        SingleActivator(
          vertical ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowLeft,
        ): const _StepIntent(
          -1,
        ),
      },
      child: Actions(
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(
            onInvoke: (i) {
              _step(
                vertical || Directionality.of(context) == TextDirection.ltr
                    ? i.delta
                    : -i.delta,
              );
              return null;
            },
          ),
        },
        child: track,
      ),
    );
    if (widget.layoutBuilder != null) return track;
    return switch (widget.style) {
      TrackStyle.navigation => track,
      TrackStyle.tabs => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: data.palette.border)),
        ),
        child: track,
      ),
      TrackStyle.segmented => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: data.palette.surface,
          border: Border.all(color: data.palette.border),
          borderRadius: suiteRadius(data.suite, 7),
        ),
        child: track,
      ),
    };
  }

  Widget _item(BuildContext context, InteractionData data, int i) {
    final item = widget.items[i];
    final selected = i == widget.selected;
    final theme = Theme.of(context).textTheme;
    final (kind, padding, height) = switch (widget.style) {
      TrackStyle.navigation => (
        PressableKind.navItem,
        const EdgeInsets.only(left: 14, right: 10),
        40.0,
      ),
      TrackStyle.tabs => (
        PressableKind.tab,
        const EdgeInsets.symmetric(horizontal: 12),
        36.0,
      ),
      TrackStyle.segmented => (
        PressableKind.tab,
        const EdgeInsets.symmetric(horizontal: 12),
        28.0,
      ),
    };
    final p = data.palette;
    final control = SuitePressable(
      kind: kind,
      selected: selected,
      focusNode: _focus[i],
      minHeight: height,
      padding: padding,
      baseRadius: widget.style == TrackStyle.segmented ? 5 : 6,
      semanticLabel: item.label,
      onActivate: item.enabled ? (s) => _select(i, s) : null,
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
        final glowIcon = selected && data.suite == InteractionSuite.glow;
        final label = Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (widget.style == TrackStyle.segmented
                      ? theme.bodySmall
                      : theme.bodyMedium)
                  ?.copyWith(
                    color: v.foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
        );
        final content = Row(
          mainAxisSize: widget.style == TrackStyle.navigation
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Transform.translate(
                offset: Offset(
                  data.suite == InteractionSuite.rail ? 4 * v.hover : 0,
                  0,
                ),
                child: Icon(
                  item.icon,
                  size: 18,
                  color: iconColor,
                  shadows: glowIcon
                      ? [Shadow(color: p.edge(0.6), blurRadius: 4)]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (widget.style == TrackStyle.navigation)
              Expanded(child: label)
            else
              label,
          ],
        );
        return Align(
          alignment: widget.style == TrackStyle.navigation
              ? Alignment.centerLeft
              : Alignment.center,
          widthFactor: widget.style == TrackStyle.navigation ? null : 1,
          child: content,
        );
      },
    );
    return KeyedSubtree(
      key: _keys[i],
      child: Semantics(
        button: true,
        enabled: item.enabled,
        selected: selected,
        focusable: item.enabled,
        focused: _focus[i].hasFocus,
        label: item.label,
        onTap: item.enabled
            ? () => _select(i, InteractionSource.keyboard)
            : null,
        excludeSemantics: true,
        child: item.enabled
            ? control
            : IgnorePointer(child: ExcludeFocus(child: control)),
      ),
    );
  }
}

enum _Mode { idle, stretch, slide, fade, locked }

class _StepIntent extends Intent {
  const _StepIntent(this.delta);
  final int delta;
}
