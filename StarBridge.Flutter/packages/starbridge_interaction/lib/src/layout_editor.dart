import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'suite.dart';

/// One movable, resizable box in a [SuiteLayoutEditor] (an in-game overlay
/// widget: player list, voice indicator, mission timer…). [rect] is in the
/// editor's virtual canvas coordinates.
@immutable
class LayoutBox {
  const LayoutBox({
    required this.id,
    required this.label,
    required this.rect,
    this.minSize = const Size(60, 30),
  });

  final String id;
  final String label;
  final Rect rect;
  final Size minSize;

  LayoutBox withRect(Rect r) =>
      LayoutBox(id: id, label: label, rect: r, minSize: minSize);

  @override
  bool operator ==(Object other) =>
      other is LayoutBox &&
      other.id == id &&
      other.label == label &&
      other.rect == rect &&
      other.minSize == minSize;

  @override
  int get hashCode => Object.hash(id, label, rect, minSize);
}

/// What produced a committed change (for undo grouping: callers usually
/// merge consecutive [nudge]s on the same box into one step).
enum LayoutEditKind { move, resize, nudge }

/// Overlay layout editor. Boxes follow the pointer exactly while dragged
/// or resized — no easing, no lag; snapping only moves them onto a nearby
/// line (window edges and centre, other boxes' edges and centres) within
/// [snapDistance] screen pixels. Hold Alt to place freely.
///
/// Snap guides are information and always show (statically under reduced
/// motion); how a newly acquired guide appears follows the suite. Rail: the
/// guide line draws out from the box. Scan: the box's corners lock with a
/// short bracket flash. Glow: the guide fades in with a soft light.
/// Standard: a plain line. The selected box keeps a static suite mark.
///
/// Keyboard: Tab between boxes, arrows move 1 (Shift: 10), Ctrl+arrows
/// resize from the right/bottom edge; no guides animate. The editor commits
/// once per drag / resize / key press through [onChanged]; the caller owns
/// the boxes (and undo).
class SuiteLayoutEditor extends StatefulWidget {
  const SuiteLayoutEditor({
    required this.boxes,
    required this.onChanged,
    this.canvasSize = const Size(1280, 720),
    this.snapDistance = 6,
    this.background,
    this.onSelectionChanged,
    super.key,
  });

  final List<LayoutBox> boxes;
  final void Function(List<LayoutBox> boxes, LayoutEditKind kind) onChanged;
  final Size canvasSize;
  final double snapDistance;
  final Widget? background;
  final ValueChanged<String?>? onSelectionChanged;

  @override
  State<SuiteLayoutEditor> createState() => SuiteLayoutEditorState();
}

/// Which edges a gesture moves.
@immutable
class _Edges {
  const _Edges(this.l, this.t, this.r, this.b);
  final bool l, t, r, b;
  static const move = _Edges(true, true, true, true);
  bool get isMove => l && t && r && b;
}

@immutable
class _Guide {
  const _Guide(this.vertical, this.pos, this.from, this.to);
  final bool vertical;
  final double pos, from, to;
  String get key => '${vertical ? 'v' : 'h'}${pos.toStringAsFixed(1)}';
}

class SuiteLayoutEditorState extends State<SuiteLayoutEditor>
    with SingleTickerProviderStateMixin {
  final _focus = <String, FocusNode>{};
  String? _selected;

  // Gesture in progress.
  String? _dragId;
  Rect? _startRect;
  Offset _startPointer = Offset.zero;
  _Edges _edges = _Edges.move;
  Rect? _live;
  List<_Guide> _guides = const [];
  Set<String> _guideKeys = const {};
  bool _keyboard = false;

  /// Entrance of newly acquired guides (0 → 1).
  late final _cue = AnimationController(vsync: this, value: 1);

  String? get selectedId => _selected;

  /// Rects committed but not yet echoed back through [widget.boxes] (key
  /// repeats can outrun the caller's rebuild).
  final _latest = <String, Rect>{};

  /// Room around each box so its edge handles (half outside) take hits.
  static const _pad = 9.0;

  FocusNode _nodeFor(String id) =>
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'layout-$id'));

  @override
  void didUpdateWidget(SuiteLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _latest.clear();
    final ids = {for (final b in widget.boxes) b.id};
    for (final id in _focus.keys.toList()) {
      if (!ids.contains(id)) {
        final n = _focus.remove(id)!;
        WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
      }
    }
    if (_selected != null && !ids.contains(_selected)) _select(null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _cue.isAnimating) {
      _cue.value = 1;
    }
  }

  @override
  void dispose() {
    _cue.dispose();
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _select(String? id) {
    if (_selected == id) return;
    setState(() => _selected = id);
    widget.onSelectionChanged?.call(id);
  }

  LayoutBox _box(String id) {
    final b = widget.boxes.firstWhere((b) => b.id == id);
    final r = _latest[id];
    return r == null ? b : b.withRect(r);
  }

  void _commit(String id, Rect r, LayoutEditKind kind) {
    if (_box(id).rect == r) return;
    _latest[id] = r;
    widget.onChanged([for (final b in widget.boxes) _box(b.id)], kind);
  }

  // ---- pointer ------------------------------------------------------------

  void _start(String id, Offset global, _Edges edges, double scale) {
    _select(id);
    _nodeFor(id).requestFocus();
    setState(() {
      _keyboard = false;
      _dragId = id;
      _startRect = _box(id).rect;
      _startPointer = global / scale;
      _edges = edges;
      _live = _startRect;
    });
  }

  void _update(Offset global, double scale) {
    final id = _dragId, start = _startRect;
    if (id == null || start == null) return;
    final d = global / scale - _startPointer;
    final box = _box(id);
    var r = _edges.isMove
        ? start.shift(d)
        : Rect.fromLTRB(
            _edges.l ? start.left + d.dx : start.left,
            _edges.t ? start.top + d.dy : start.top,
            _edges.r ? start.right + d.dx : start.right,
            _edges.b ? start.bottom + d.dy : start.bottom,
          );
    final free = HardwareKeyboard.instance.isAltPressed;
    final guides = <_Guide>[];
    if (!free) r = _snap(id, r, widget.snapDistance / scale, guides);
    r = _limit(r, box.minSize);
    final keys = {for (final g in guides) g.key};
    final fresh = keys.difference(_guideKeys).isNotEmpty;
    setState(() {
      _live = r;
      _guides = guides;
      _guideKeys = keys;
    });
    if (fresh) _playCue();
  }

  void _end() {
    final id = _dragId, r = _live;
    setState(() {
      _dragId = null;
      _live = null;
      _guides = const [];
      _guideKeys = const {};
    });
    if (id != null && r != null) {
      _commit(
        id,
        r,
        _edges.isMove ? LayoutEditKind.move : LayoutEditKind.resize,
      );
    }
  }

  void _playCue() {
    final data = InteractionScope.of(context);
    if (!data.animates || data.suite == InteractionSuite.standard) {
      _cue.value = 1;
      return;
    }
    _cue
      ..duration = data.suite == InteractionSuite.scan
          ? const Duration(milliseconds: 220)
          : const Duration(milliseconds: 140)
      ..forward(from: 0);
  }

  /// Keeps [r] inside the canvas and at least [min] large.
  Rect _limit(Rect r, Size min) {
    final c = widget.canvasSize;
    var w = math.max(r.width, min.width), h = math.max(r.height, min.height);
    w = math.min(w, c.width);
    h = math.min(h, c.height);
    // Resizing past the minimum keeps the fixed edge where it is.
    var left = r.width < min.width && _edges.l && !_edges.isMove
        ? r.right - w
        : r.left;
    var top = r.height < min.height && _edges.t && !_edges.isMove
        ? r.bottom - h
        : r.top;
    left = left.clamp(0.0, c.width - w);
    top = top.clamp(0.0, c.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  Rect _snap(String id, Rect r, double threshold, List<_Guide> out) {
    final c = widget.canvasSize;
    final others = [
      for (final b in widget.boxes)
        if (b.id != id) b.rect,
    ];
    final xs = <double>[0, c.width / 2, c.width];
    final ys = <double>[0, c.height / 2, c.height];
    for (final o in others) {
      xs.addAll([o.left, o.center.dx, o.right]);
      ys.addAll([o.top, o.center.dy, o.bottom]);
    }

    // Candidate edges of the moving rect (offset from its left / top).
    final move = _edges.isMove;
    final xEdges = <double>[
      if (move || _edges.l) r.left,
      if (move) r.center.dx,
      if (move || _edges.r) r.right,
    ];
    final yEdges = <double>[
      if (move || _edges.t) r.top,
      if (move) r.center.dy,
      if (move || _edges.b) r.bottom,
    ];

    double? bestDx, bestX, edgeX;
    for (final e in xEdges) {
      for (final t in xs) {
        final d = t - e;
        if (d.abs() <= threshold &&
            (bestDx == null || d.abs() < bestDx.abs())) {
          bestDx = d;
          bestX = t;
          edgeX = e;
        }
      }
    }
    double? bestDy, bestY, edgeY;
    for (final e in yEdges) {
      for (final t in ys) {
        final d = t - e;
        if (d.abs() <= threshold &&
            (bestDy == null || d.abs() < bestDy.abs())) {
          bestDy = d;
          bestY = t;
          edgeY = e;
        }
      }
    }

    if (bestDx != null) {
      if (move) {
        r = r.shift(Offset(bestDx, 0));
      } else if (edgeX == r.left) {
        r = Rect.fromLTRB(bestX!, r.top, r.right, r.bottom);
      } else {
        r = Rect.fromLTRB(r.left, r.top, bestX!, r.bottom);
      }
    }
    if (bestDy != null) {
      if (move) {
        r = r.shift(Offset(0, bestDy));
      } else if (edgeY == r.top) {
        r = Rect.fromLTRB(r.left, bestY!, r.right, r.bottom);
      } else {
        r = Rect.fromLTRB(r.left, r.top, r.right, bestY!);
      }
    }
    // Guides span the box and whatever it lines up with.
    if (bestX != null) {
      var from = r.top, to = r.bottom;
      final x = bestX;
      final matches = others.where(
        (o) => [o.left, o.center.dx, o.right].any((v) => (v - x).abs() < 0.01),
      );
      if (matches.isEmpty) {
        from = 0;
        to = c.height;
      }
      for (final o in matches) {
        from = math.min(from, o.top);
        to = math.max(to, o.bottom);
      }
      out.add(_Guide(true, x, from, to));
    }
    if (bestY != null) {
      var from = r.left, to = r.right;
      final y = bestY;
      final matches = others.where(
        (o) => [o.top, o.center.dy, o.bottom].any((v) => (v - y).abs() < 0.01),
      );
      if (matches.isEmpty) {
        from = 0;
        to = c.width;
      }
      for (final o in matches) {
        from = math.min(from, o.left);
        to = math.max(to, o.right);
      }
      out.add(_Guide(false, y, from, to));
    }
    return r;
  }

  // ---- keyboard -----------------------------------------------------------

  KeyEventResult _key(String id, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = HardwareKeyboard.instance;
    final step = k.isShiftPressed ? 10.0 : 1.0;
    final d = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (d == null) return KeyEventResult.ignored;
    final box = _box(id);
    final r = box.rect;
    _edges = k.isControlPressed
        ? const _Edges(false, false, true, true)
        : _Edges.move;
    final next = k.isControlPressed
        ? Rect.fromLTWH(r.left, r.top, r.width + d.dx, r.height + d.dy)
        : r.shift(d);
    setState(() => _keyboard = true);
    _commit(id, _limit(next, box.minSize), LayoutEditKind.nudge);
    _edges = _Edges.move;
    return KeyEventResult.handled;
  }

  /// Drag surface for a box body or one of its handles. Pressing selects
  /// and focuses the box; releasing without movement changes nothing.
  Widget _dragArea(
    String id,
    _Edges edges,
    double scale, {
    required Widget child,
  }) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
        _EagerPan.new,
        (r) => r
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = ((d) => _start(id, d.globalPosition, edges, scale))
          ..onUpdate = ((d) => _update(d.globalPosition, scale))
          ..onEnd = ((_) => _end())
          ..onCancel = _end,
      ),
    },
    child: child,
  );

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    // The aspect ratio is declared up front so the editor reports intrinsic
    // sizes without running its layout callback.
    return AspectRatio(
      aspectRatio: widget.canvasSize.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final c = widget.canvasSize;
          final scale = math.min(
            constraints.maxWidth / c.width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight / c.height
                : double.infinity,
          );
          final size = c * scale;
          return Center(
            child: SizedBox.fromSize(
              size: size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _select(null),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: p.border),
                        ),
                        child: widget.background,
                      ),
                    ),
                    for (final b in widget.boxes) _boxWidget(data, b, scale),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _cue,
                          builder: (context, _) => CustomPaint(
                            painter: _GuidePainter(
                              data,
                              _guides,
                              scale,
                              _cue.value,
                              _dragId == null ? null : _scaled(_live!, scale),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _boxWidget(InteractionData data, LayoutBox b, double scale) {
    final p = data.palette;
    final dragging = _dragId == b.id;
    final r = _scaled(dragging ? _live! : _box(b.id).rect, scale);
    final selected = _selected == b.id;
    final node = _nodeFor(b.id);
    final rr = r.size;
    final readout = dragging || (selected && _keyboard && node.hasFocus);
    final shown = dragging ? _live! : _box(b.id).rect;
    final label =
        'x ${shown.left.round()} · y ${shown.top.round()} · '
        '${shown.width.round()} × ${shown.height.round()}';
    const pad = _pad;
    return Positioned(
      left: r.left - pad,
      top: r.top - pad,
      width: rr.width + 2 * pad,
      height: rr.height + 2 * pad,
      child: Semantics(
        label: '${b.label}，$label',
        hint: '方向键移动，Shift 加大步长，Ctrl 加方向键调整大小',
        selected: selected,
        child: Focus(
          focusNode: node,
          onFocusChange: (has) {
            if (has) _select(b.id);
            setState(() {});
          },
          onKeyEvent: (_, e) => _key(b.id, e),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: pad,
                top: pad,
                right: pad,
                bottom: pad,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: _dragArea(
                    b.id,
                    _Edges.move,
                    scale,
                    child: CustomPaint(
                      painter: _BoxPainter(
                        data,
                        selected: selected,
                        focused: node.hasFocus && _keyboard,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            b.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: selected ? p.textPrimary : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected) ..._handles(data, b, rr, scale),
              if (readout)
                Positioned(
                  // Near the canvas's right edge, align to the box's right.
                  left: r.left + 150 > widget.canvasSize.width * scale
                      ? null
                      : pad,
                  right: r.left + 150 > widget.canvasSize.width * scale
                      ? pad
                      : null,
                  bottom: rr.height + pad + 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: p.raised,
                        borderRadius: suiteRadius(data.suite, 3),
                        border: Border.all(color: p.border),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: p.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _handles(
    InteractionData data,
    LayoutBox b,
    Size size,
    double scale,
  ) {
    final p = data.palette;
    const hit = 18.0;
    final spots = <(Alignment, _Edges, MouseCursor)>[
      (
        Alignment.topLeft,
        const _Edges(true, true, false, false),
        SystemMouseCursors.resizeUpLeftDownRight,
      ),
      (
        Alignment.topCenter,
        const _Edges(false, true, false, false),
        SystemMouseCursors.resizeUpDown,
      ),
      (
        Alignment.topRight,
        const _Edges(false, true, true, false),
        SystemMouseCursors.resizeUpRightDownLeft,
      ),
      (
        Alignment.centerRight,
        const _Edges(false, false, true, false),
        SystemMouseCursors.resizeLeftRight,
      ),
      (
        Alignment.bottomRight,
        const _Edges(false, false, true, true),
        SystemMouseCursors.resizeUpLeftDownRight,
      ),
      (
        Alignment.bottomCenter,
        const _Edges(false, false, false, true),
        SystemMouseCursors.resizeUpDown,
      ),
      (
        Alignment.bottomLeft,
        const _Edges(true, false, false, true),
        SystemMouseCursors.resizeUpRightDownLeft,
      ),
      (
        Alignment.centerLeft,
        const _Edges(true, false, false, false),
        SystemMouseCursors.resizeLeftRight,
      ),
    ];
    return [
      for (final (a, edges, cursor) in spots)
        Positioned(
          left: _pad + (a.x + 1) / 2 * size.width - hit / 2,
          top: _pad + (a.y + 1) / 2 * size.height - hit / 2,
          width: hit,
          height: hit,
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: cursor,
              child: _dragArea(
                b.id,
                edges,
                scale,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.raised,
                      shape: data.suite == InteractionSuite.scan
                          ? BoxShape.rectangle
                          : BoxShape.circle,
                      border: Border.all(color: p.accentBright, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

Rect _scaled(Rect r, double s) =>
    Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);

/// A pan that claims the pointer as soon as it lands on a box or handle,
/// so a surrounding scroll view (whose drag would win first with a mouse)
/// never steals the drag.
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() : super(debugOwner: null);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.data, {required this.selected, required this.focused});
  final InteractionData data;
  final bool selected;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    final rrect = suiteRadius(data.suite, 4).toRRect(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = (selected ? p.selectedFill : p.raised).withValues(
          alpha: 0.82,
        ),
    );
    if (selected) {
      switch (data.suite) {
        case InteractionSuite.rail:
          paintSideBar(canvas, rect, p.edge(), inset: 3, width: 2.5);
        case InteractionSuite.glow:
          paintSideGlow(canvas, rrect, p.accent, 0.25);
        case InteractionSuite.scan || InteractionSuite.standard:
          break;
      }
    }
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.5 : 1
        ..color = selected ? p.accent : p.border,
    );
    if (selected && data.suite == InteractionSuite.scan) {
      paintBrackets(canvas, rect.inflate(3), color: p.edge(), length: 7);
    }
    if (selected && data.suite == InteractionSuite.glow && p.isDark) {
      paintGlowStrokes(canvas, rrect, p.accent, 0.35);
    }
    if (focused) {
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.focusRing,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.data != data || old.selected != selected || old.focused != focused;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.data, this.guides, this.scale, this.t, this.box);
  final InteractionData data;
  final List<_Guide> guides;
  final double scale;
  final double t;
  final Rect? box;

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    final p = data.palette;
    final suite = data.animates ? data.suite : InteractionSuite.standard;
    final c = SuiteMotion.curve.transform(t.clamp(0.0, 1.0));
    for (final g in guides) {
      final pos = g.pos * scale;
      var a = g.from * scale, b = g.to * scale;
      if (suite == InteractionSuite.rail && box != null && c < 1) {
        // Draw out from the box's centre along the guide.
        final mid = g.vertical ? box!.center.dy : box!.center.dx;
        a = mid + (a - mid) * c;
        b = mid + (b - mid) * c;
      }
      final line = g.vertical
          ? Rect.fromLTRB(pos - 0.5, a, pos + 0.5, b)
          : Rect.fromLTRB(a, pos - 0.5, b, pos + 0.5);
      final alpha = suite == InteractionSuite.glow ? c : 1.0;
      if (suite == InteractionSuite.glow) {
        final band = line.inflate(3);
        canvas.drawRect(band, Paint()..color = p.light(0.18 * alpha));
      }
      canvas.drawRect(line, Paint()..color = p.edge(0.95 * alpha));
    }
    if (suite == InteractionSuite.scan && box != null && t < 1) {
      paintBrackets(
        canvas,
        box!.inflate(2 + 6 * (1 - c)),
        color: p.edge(1 - t * 0.6),
        length: 8,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => true;
}
