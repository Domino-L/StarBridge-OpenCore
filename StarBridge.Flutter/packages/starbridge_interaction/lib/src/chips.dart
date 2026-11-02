import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'effect_host.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

@immutable
class SuiteChipData {
  const SuiteChipData({
    required this.id,
    required this.label,
    this.selected = false,
    this.removable = false,
    this.side,
    this.backgroundColor,
    this.foregroundColor,
    this.removeLabel,
    this.fullLabel,
  });

  final String id;
  final String label;
  final bool selected;
  final bool removable;
  final BorderSide? side;
  final Color? backgroundColor;

  /// Optional domain label colour; does not recolour remove icons or actions.
  final Color? foregroundColor;
  final String? removeLabel;

  /// The whole text when [label] is shortened: shown on hover and read by
  /// screen readers instead of the short form.
  final String? fullLabel;
}

/// Hover text and reader name for a chip whose label is shortened.
Widget suiteChipLabel(SuiteChipData c, Widget text) => c.fullLabel == null
    ? text
    : Tooltip(
        message: c.fullLabel,
        excludeFromSemantics: true,
        child: Semantics(
          label: c.fullLabel,
          excludeSemantics: true,
          child: text,
        ),
      );

/// Filter chips: multi-select, optionally removable. Chips are identified
/// by [SuiteChipData.id], so additions, removals and reordering keep each
/// chip's state.
///
/// Selected marks stay static and readable in every suite (a tick plus a
/// suite mark), so the active filter set can always be read at a glance.
/// Rail: a lit underline. Scan: corner brackets lock on. Glow: a quiet
/// filled light. Toggling plays a short suite cue (rail line grows, scan
/// brackets close in, glow ring) for pointer input only.
///
/// Removal shrinks the chip's width so neighbours slide over instead of
/// jumping; focus moves to the next chip (or the previous one). Delete or
/// Backspace on a focused removable chip removes it instantly.
class SuiteChipGroup extends StatefulWidget {
  const SuiteChipGroup({
    required this.chips,
    required this.onToggle,
    this.onRemove,
    this.onRemoveWithSource,
    this.changeSource,
    this.focusNodeForId,
    this.fallbackFocus,
    super.key,
  }) : assert(onRemove == null || onRemoveWithSource == null);

  final List<SuiteChipData> chips;
  final ValueChanged<String>? onToggle;
  final ValueChanged<String>? onRemove;
  final void Function(String, InteractionSource)? onRemoveWithSource;
  final InteractionSource? changeSource;
  final FocusNode Function(String)? focusNodeForId;

  /// Receives focus when the last chip is removed.
  final FocusNode? fallbackFocus;

  @override
  State<SuiteChipGroup> createState() => _SuiteChipGroupState();
}

class _SuiteChipGroupState extends State<SuiteChipGroup>
    with TickerProviderStateMixin {
  final _focus = <String, FocusNode>{};

  /// Chips that left the data but are still shrinking out, with the index
  /// they had.
  final _leaving = <String, ({SuiteChipData chip, int index})>{};

  /// One size controller per chip id while it is shrinking out or growing
  /// back. Restoring a leaving chip reverses this same controller from its
  /// current width, so there is only ever one element (and focus node) per
  /// id and a stale completion can never remove the restored chip.
  final _size = <String, AnimationController>{};
  late List<SuiteChipData> _shown = widget.chips;

  FocusNode _nodeFor(String id) =>
      widget.focusNodeForId?.call(id) ??
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'chip-$id'));

  InteractionSource? _removalSource;
  void _remove(String id, InteractionSource source) {
    _removalSource = source;
    widget.onRemoveWithSource?.call(id, source);
    widget.onRemove?.call(id);
  }

  @override
  void didUpdateWidget(SuiteChipGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final data = InteractionScope.of(context);
    final now = {for (final c in widget.chips) c.id};
    // Restored before the exit finished: grow back from where it is.
    for (final id in now) {
      if (_leaving.remove(id) == null) continue;
      final anim = _size[id];
      if (anim == null) continue;
      if (!data.animates ||
          widget.changeSource == InteractionSource.keyboard ||
          _removalSource == InteractionSource.keyboard) {
        _dropSize(id);
        continue;
      }
      anim.duration = const Duration(milliseconds: 160);
      anim.forward().whenComplete(() {
        if (!mounted || _size[id] != anim || _leaving.containsKey(id)) return;
        setState(() => _dropSize(id));
      });
    }
    for (var i = 0; i < oldWidget.chips.length; i++) {
      final c = oldWidget.chips[i];
      if (now.contains(c.id) || _leaving.containsKey(c.id)) continue;
      final hadFocus = _nodeFor(c.id).hasFocus;
      if (hadFocus) _moveFocusAfterRemoval(i, oldWidget.chips, now);
      if (!data.animates ||
          widget.changeSource == InteractionSource.keyboard ||
          _removalSource == InteractionSource.keyboard) {
        _dropSize(c.id);
        _disposeNode(c.id);
        continue;
      }
      final anim = _size.putIfAbsent(
        c.id,
        () => AnimationController(vsync: this, value: 1),
      );
      anim.reverseDuration = const Duration(milliseconds: 160);
      _leaving[c.id] = (chip: c, index: i);
      anim.reverse().whenComplete(() {
        if (!mounted || _size[c.id] != anim || !_leaving.containsKey(c.id)) {
          return;
        }
        setState(() {
          _leaving.remove(c.id);
          _dropSize(c.id);
        });
        _disposeNode(c.id);
      });
    }
    _shown = widget.chips;
    _removalSource = null;
  }

  void _moveFocusAfterRemoval(
    int index,
    List<SuiteChipData> old,
    Set<String> remaining,
  ) {
    String? next;
    for (var j = index + 1; j < old.length && next == null; j++) {
      if (remaining.contains(old[j].id)) next = old[j].id;
    }
    for (var j = index - 1; j >= 0 && next == null; j--) {
      if (remaining.contains(old[j].id)) next = old[j].id;
    }
    final target = next == null ? widget.fallbackFocus : _nodeFor(next);
    WidgetsBinding.instance.addPostFrameCallback((_) => target?.requestFocus());
  }

  /// Disposes after the frame: the transition still listens until rebuilt.
  void _dropSize(String id) {
    final anim = _size.remove(id);
    if (anim == null) return;
    anim.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) => anim.dispose());
  }

  void _disposeNode(String id) {
    final node = _focus.remove(id);
    if (node != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-exit: settle every chip right away.
    if (!InteractionScope.of(context).animates && _size.isNotEmpty) {
      for (final id in _size.keys.toList()) {
        _dropSize(id);
      }
      for (final id in _leaving.keys.toList()) {
        _leaving.remove(id);
        _disposeNode(id);
      }
    }
  }

  @override
  void dispose() {
    for (final a in _size.values) {
      a.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    final ordered = [..._shown];
    final leaving = _leaving.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final l in leaving) {
      ordered.insert(l.index.clamp(0, ordered.length), l.chip);
    }
    for (final c in ordered) {
      final out = _leaving.containsKey(c.id);
      final anim = _size[c.id];
      // Same structure whether settled, leaving or restoring, so the
      // element and its focus node survive a quick remove → restore.
      items.add(
        KeyedSubtree(
          key: ValueKey(c.id),
          child: SizeTransition(
            axis: Axis.horizontal,
            sizeFactor: anim ?? kAlwaysCompleteAnimation,
            child: FadeTransition(
              opacity: anim ?? kAlwaysCompleteAnimation,
              child: ExcludeFocus(
                excluding: out,
                child: IgnorePointer(
                  ignoring: out,
                  child: _Chip(
                    data: c,
                    focusNode: _nodeFor(c.id),
                    onToggle: out || widget.onToggle == null
                        ? null
                        : () => widget.onToggle!(c.id),
                    onRemove:
                        !out &&
                            c.removable &&
                            (widget.onRemove != null ||
                                widget.onRemoveWithSource != null)
                        ? (source) => _remove(c.id, source)
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: items);
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.data,
    required this.focusNode,
    required this.onToggle,
    required this.onRemove,
  });

  final SuiteChipData data;
  final FocusNode focusNode;
  final VoidCallback? onToggle;
  final ValueChanged<InteractionSource>? onRemove;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  final _fx = GlobalKey<EffectHostState>();
  bool _keyboard = false;

  @override
  void didUpdateWidget(_Chip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.selected == widget.data.selected || _keyboard) {
      _keyboard = false;
      return;
    }
    final data = InteractionScope.of(context);
    if (!data.animates) return;
    switch (data.suite) {
      case InteractionSuite.scan:
        if (widget.data.selected) {
          _fx.currentState?.play(
            TransientEffect.bracketFlash,
            duration: const Duration(milliseconds: 360),
          );
        }
      case InteractionSuite.glow:
        _fx.currentState?.play(TransientEffect.ring, ringScale: 2);
      case InteractionSuite.rail || InteractionSuite.standard:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final c = widget.data;
    if (widget.onToggle == null && c.removable) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.backgroundColor ?? p.raised,
          border: Border.fromBorderSide(c.side ?? BorderSide(color: p.border)),
          borderRadius: suiteRadius(data.suite, 14),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Flexible(
                child: suiteChipLabel(
                  c,
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: c.foregroundColor ?? p.textPrimary,
                    ),
                  ),
                ),
              ),
              CallbackShortcuts(
                bindings: {
                  if (widget.onRemove != null) ...{
                    const SingleActivator(LogicalKeyboardKey.delete): () =>
                        widget.onRemove!(InteractionSource.keyboard),
                    const SingleActivator(LogicalKeyboardKey.backspace): () =>
                        widget.onRemove!(InteractionSource.keyboard),
                  },
                },
                child: SuitePressable(
                  key: ValueKey<Object>(('chip-remove', c.id)),
                  kind: PressableKind.icon,
                  focusNode: widget.focusNode,
                  minHeight: 28,
                  padding: const EdgeInsets.all(4),
                  semanticLabel: c.removeLabel ?? '移除${c.label}',
                  excludeChildSemantics: true,
                  onActivate: widget.onRemove,
                  child: Icon(Icons.close, size: 13, color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      selected: c.selected,
      child: CallbackShortcuts(
        bindings: {
          if (widget.onRemove != null) ...{
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                widget.onRemove!(InteractionSource.keyboard),
            const SingleActivator(LogicalKeyboardKey.backspace): () =>
                widget.onRemove!(InteractionSource.keyboard),
          },
        },
        child: EffectHost(
          key: _fx,
          borderRadius: suiteRadius(data.suite, 14),
          bracketInset: -3,
          bracketLength: 5,
          child: _SelectedMarks(
            selected: c.selected,
            data: data,
            child: SuitePressable(
              kind: PressableKind.tab,
              focusNode: widget.focusNode,
              selected: c.selected,
              baseRadius: 14,
              minHeight: 28,
              padding: EdgeInsets.only(
                left: 10,
                right: widget.onRemove != null ? 4 : 10,
              ),
              semanticLabel: c.label,
              onActivate: widget.onToggle == null
                  ? null
                  : (s) {
                      _keyboard = s == InteractionSource.keyboard;
                      widget.onToggle!();
                    },
              builder: (context, v) => Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  if (c.selected) Icon(Icons.check, size: 14, color: p.accent),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color:
                          widget.onToggle != null && c.foregroundColor != null
                          ? c.foregroundColor
                          : c.selected
                          ? p.textPrimary
                          : v.foreground,
                      fontWeight: c.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (widget.onRemove != null)
                    Semantics(
                      button: true,
                      label: '移除${c.label}',
                      child: GestureDetector(
                        onTap: () =>
                            widget.onRemove!(InteractionSource.pointer),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: v.foreground,
                          ),
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

/// Controlled single-choice target using the same face, edge and press recipe
/// as [SuiteChipGroup]. The caller owns selection, validation and persistence;
/// this target has no optimistic state, removal lifecycle or input queue.
class SuiteChoiceChip extends StatelessWidget {
  const SuiteChoiceChip({
    required this.label,
    required this.selected,
    this.onActivate,
    this.focusNode,
    this.trailing,
    this.selectionKey,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<InteractionSource>? onActivate;
  final FocusNode? focusNode;

  /// An independent trailing action, not nested in the selection target's
  /// gesture/focus/semantics tree. The caller still owns both actions.
  final Widget? trailing;
  final Key? selectionKey;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final enabled = onActivate != null;
    final target = _SelectedMarks(
      selected: selected,
      data: data,
      child: SuitePressable(
        key: selectionKey,
        kind: PressableKind.tab,
        focusNode: focusNode,
        selected: selected,
        baseRadius: 14,
        minHeight: 28,
        padding: EdgeInsets.only(left: 10, right: trailing == null ? 10 : 38),
        semanticLabel: label,
        semanticSelected: selected,
        excludeChildSemantics: true,
        onActivate: onActivate,
        builder: (context, v) => Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (selected)
              Icon(
                Icons.check,
                size: 14,
                color: enabled ? p.accent : p.textDisabled,
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: !enabled
                    ? p.textDisabled
                    : selected
                    ? p.textPrimary
                    : v.foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
    return trailing == null
        ? target
        : Stack(
            children: [
              target,
              Positioned(
                right: 2,
                top: 0,
                bottom: 0,
                child: Center(child: trailing!),
              ),
            ],
          );
  }
}

/// Static selected look per suite, drawn behind/around the chip.
class _SelectedMarks extends StatelessWidget {
  const _SelectedMarks({
    required this.selected,
    required this.data,
    required this.child,
  });
  final bool selected;
  final InteractionData data;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ChipFace(selected, data),
    foregroundPainter: _ChipEdge(selected, data),
    child: child,
  );
}

class _ChipFace extends CustomPainter {
  _ChipFace(this.selected, this.data);
  final bool selected;
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rrect = suiteRadius(data.suite, 14).toRRect(Offset.zero & size);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = selected ? p.selectedFill : p.raised.withValues(alpha: 0.6),
    );
    if (selected && data.suite == InteractionSuite.glow) {
      paintSideGlow(canvas, rrect, p.accent, 0.22);
    }
  }

  @override
  bool shouldRepaint(_ChipFace old) =>
      old.selected != selected || old.data != data;
}

class _ChipEdge extends CustomPainter {
  _ChipEdge(this.selected, this.data);
  final bool selected;
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    final rrect = suiteRadius(data.suite, 14).toRRect(rect);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = selected
            ? p.accent.withValues(alpha: 0.7)
            : p.border.withValues(alpha: 0.6),
    );
    if (!selected) return;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.save();
        canvas.clipRRect(rrect);
        paintEdgeLine(canvas, rect.deflate(0), p.edge());
        canvas.restore();
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(2),
          color: p.edge(),
          length: 5,
          width: 1.5,
        );
      case InteractionSuite.glow:
        if (p.isDark) paintGlowStrokes(canvas, rrect, p.accent, 0.35);
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_ChipEdge old) =>
      old.selected != selected || old.data != data;
}
