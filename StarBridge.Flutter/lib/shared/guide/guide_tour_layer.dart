import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'guide_copy.dart';
import 'guide_scope.dart';
import 'guide_tours.dart';

/// Dims the app, cuts a hole around the current anchor and shows the coach
/// card. Waiting steps let clicks through the hole only.
class GuideTourLayer extends StatefulWidget {
  const GuideTourLayer({required this.hub, super.key});
  final GuideHub hub;

  @override
  State<GuideTourLayer> createState() => _GuideTourLayerState();
}

class _GuideTourLayerState extends State<GuideTourLayer> {
  final _self = GlobalKey();
  Rect? _hole, _cardArea, _beside;

  /// Another route (e.g. a picker) sits above the step's anchor: the tour
  /// steps aside until it closes, so that dialog stays fully usable.
  bool _covered = false;

  /// False while the element is deactivated (e.g. a tree being replaced);
  /// measuring then would read a render object that is going away.
  bool _active = true;

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void initState() {
    super.initState();
    widget.hub.run.addListener(_changed);
    widget.hub.anchorsChanged.addListener(_changed);
    // Re-measure on frames the app draws anyway (scrolls, dialogs, layout);
    // never schedules frames of its own while nothing moves.
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (mounted && _active && widget.hub.run.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      }
    });
  }

  @override
  void dispose() {
    widget.hub.run.removeListener(_changed);
    widget.hub.anchorsChanged.removeListener(_changed);
    super.dispose();
  }

  // Anchors register while pages build, so never rebuild synchronously.
  void _changed() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_active) return;
      setState(() {});
      _measure();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _measure() {
    if (!mounted || !_active) return;
    final step = widget.hub.run.value?.step;
    final layer = _self.currentContext?.findRenderObject();
    Rect? rect(String? id) {
      final target = id == null
          ? null
          : widget.hub.anchor(id)?.currentContext?.findRenderObject();
      if (target is! RenderBox ||
          layer is! RenderBox ||
          !target.attached ||
          !target.hasSize) {
        return null;
      }
      final origin = target.localToGlobal(Offset.zero, ancestor: layer);
      final box = origin & target.size;
      return (Offset.zero & layer.size).overlaps(box) ? box : null;
    }

    final anchorContext = step?.anchor == null
        ? null
        : widget.hub.anchor(step!.anchor!)?.currentContext;
    final covered =
        anchorContext != null &&
        anchorContext.mounted &&
        ModalRoute.of(anchorContext)?.isCurrent == false;
    final hole = rect(step?.anchor)?.inflate(6);
    final area = rect(step?.card);
    final beside = rect(step?.beside);
    if (hole != _hole ||
        area != _cardArea ||
        beside != _beside ||
        covered != _covered) {
      setState(() {
        _covered = covered;
        _hole = hole;
        _cardArea = area;
        _beside = beside;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.hub.run.value;
    if (current == null || _covered) return SizedBox.shrink(key: _self);
    final t = context.tokens;
    final hole = _hole;
    final step = current.step;
    // Waiting steps let clicks through the hole only; interactive steps leave
    // the whole page (and its pickers) usable and only draw the ring.
    // A waiting step never offers "Next": only the business event moves it.
    // Without its anchor on screen it waits without blocking the page.
    final wait = step.waits;
    final open = step.interactive || (wait && hole == null);
    final ring = wait ? t.colors.warning : t.colors.accent;
    return SizedBox.expand(
      key: _self,
      child: Stack(
        children: [
          Positioned.fill(
            child: open
                ? IgnorePointer(
                    child: CustomPaint(
                      painter: _SpotPainter(hole: hole, dim: null, ring: ring),
                    ),
                  )
                : _HoleBarrier(
                    hole: wait ? hole : null,
                    child: CustomPaint(
                      painter: _SpotPainter(
                        hole: hole,
                        dim: t.colors.scrim.withValues(alpha: .72),
                        ring: ring,
                      ),
                    ),
                  ),
          ),
          CustomSingleChildLayout(
            delegate: _CardPlacement(hole, _cardArea, _beside),
            child: _CoachCard(hub: widget.hub, run: current, waiting: wait),
          ),
        ],
      ),
    );
  }
}

/// Absorbs pointers except inside [hole], which passes through to the app.
class _HoleBarrier extends SingleChildRenderObjectWidget {
  const _HoleBarrier({required this.hole, super.child});
  final Rect? hole;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHole(hole);
  @override
  void updateRenderObject(BuildContext context, _RenderHole render) =>
      render.hole = hole;
}

class _RenderHole extends RenderProxyBox {
  _RenderHole(this.hole);
  Rect? hole;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hole?.contains(position) ?? false) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter({required this.hole, required this.dim, required this.ring});
  final Rect? hole;

  /// Null on interactive steps: ring only, the page stays undimmed.
  final Color? dim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    final dim = this.dim;
    if (hole == null) {
      if (dim != null) canvas.drawPath(all, Paint()..color = dim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(10));
    if (dim != null) {
      canvas.drawPath(
        Path.combine(PathOperation.difference, all, Path()..addRRect(rrect)),
        Paint()..color = dim,
      );
    }
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..color = ring.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.hole != hole || old.dim != dim || old.ring != ring;
}

/// Below the hole, else above, else beside it; centred without a hole.
class _CardPlacement extends SingleChildLayoutDelegate {
  _CardPlacement(this.hole, this.area, this.beside);
  final Rect? hole;
  final Rect? area;
  final Rect? beside;
  static const _gap = 16.0, _edge = 12.0;

  /// Room on each side of [beside]; the wider side takes the card.
  (double, double) _sides(double width) =>
      (beside!.left - _gap - _edge, width - beside!.right - _gap - _edge);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    var width = area == null
        ? 360.0
        : (area!.width - _edge * 2).clamp(200.0, 360.0);
    if (beside != null) {
      final (left, right) = _sides(constraints.maxWidth);
      width = (left > right ? left : right).clamp(200.0, 360.0);
    }
    return BoxConstraints.loose(Size(width, constraints.maxHeight - _edge * 2));
  }

  @override
  Offset getPositionForChild(Size size, Size card) {
    if (area case final a?) return a.topLeft + const Offset(_edge, _edge);
    if (beside case final b?) {
      final (left, right) = _sides(size.width);
      final x = right >= left ? b.right + _gap : b.left - _gap - card.width;
      final y = (hole?.top ?? b.top).clamp(
        _edge,
        (size.height - card.height - _edge).clamp(_edge, double.infinity),
      );
      return Offset(x.clamp(_edge, size.width - card.width - _edge), y);
    }
    final h = hole;
    if (h == null) {
      return Offset(
        (size.width - card.width) / 2,
        (size.height - card.height) / 2,
      );
    }
    double x = h.left, y;
    if (h.bottom + _gap + card.height < size.height - _edge) {
      y = h.bottom + _gap;
    } else if (h.top - _gap - card.height > _edge) {
      y = h.top - _gap - card.height;
    } else if (h.right + _gap + card.width < size.width - _edge) {
      x = h.right + _gap;
      y = h.top;
    } else {
      x = h.left - _gap - card.width;
      y = h.top;
    }
    return Offset(
      x.clamp(
        _edge,
        (size.width - card.width - _edge).clamp(_edge, double.infinity),
      ),
      y.clamp(
        _edge,
        (size.height - card.height - _edge).clamp(_edge, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_CardPlacement old) =>
      old.hole != hole || old.area != area || old.beside != beside;
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.hub,
    required this.run,
    required this.waiting,
  });
  final GuideHub hub;
  final GuideTourRun run;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = GuideCopy.of(context);
    final text = Theme.of(context).textTheme;
    final tone = waiting ? t.colors.warning : t.colors.accent;
    final prefix = 'tour.${run.spec.id}.${run.index + 1}';
    final note = copy.maybe('$prefix.note');
    final finish = run.spec.kind == GuideTourKind.doIt
        ? 'tour.finishDo'
        : 'tour.finish';
    final counter = copy
        .text('tour.counter')
        .replaceAll('{title}', copy.text('tour.${run.spec.id}.name'))
        .replaceAll('{n}', '${run.index + 1}')
        .replaceAll('{total}', '${run.spec.steps.length}');
    Widget quiet(String key, String label, VoidCallback onTap) =>
        StarBridgeActionButton(
          controlKey: Key(key),
          kind: StarBridgeActionKind.quiet,
          onActivate: (_) => onTap(),
          child: Text(label),
        );
    // A soft cast shadow; Material elevation drew a hard dark rim on light
    // themes under the scrim.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.shape.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: t.colors.scrim.withValues(alpha: .35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        key: const Key('guide-tour-card'),
        color: t.surfaces.raised.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.shape.radiusLarge),
          side: BorderSide(color: tone.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.lg,
            t.space.md,
            t.space.lg,
            t.space.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(counter, style: text.labelMedium?.copyWith(color: tone)),
              SizedBox(height: t.space.xs),
              Text(copy.text('$prefix.title'), style: text.titleMedium),
              SizedBox(height: t.space.xs),
              Text(
                copy.text('$prefix.body'),
                style: text.bodyMedium?.copyWith(color: t.colors.textSecondary),
              ),
              if (note != null) ...[
                SizedBox(height: t.space.xs),
                Text(
                  note,
                  style: text.bodySmall?.copyWith(
                    color: t.colors.textSecondary,
                  ),
                ),
              ],
              SizedBox(height: t.space.sm),
              Row(
                children: [
                  if (waiting) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                      ),
                      child: const SizedBox.square(dimension: 8),
                    ),
                    SizedBox(width: t.space.xs),
                    Expanded(
                      child: Text(
                        copy.text('tour.waiting'),
                        key: const Key('guide-tour-waiting'),
                        style: text.bodySmall?.copyWith(color: tone),
                      ),
                    ),
                    quiet(
                      'guide-tour-exit',
                      copy.text('tour.exit'),
                      hub.finish,
                    ),
                  ] else ...[
                    for (var i = 0; i < run.spec.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == run.index
                                ? tone
                                : t.colors.textDisabled,
                          ),
                          child: const SizedBox.square(dimension: 6),
                        ),
                      ),
                    const Spacer(),
                    if (run.index == 0)
                      quiet(
                        'guide-tour-skip',
                        copy.text('tour.skip'),
                        hub.finish,
                      )
                    else ...[
                      quiet(
                        'guide-tour-skip',
                        copy.text('tour.skip'),
                        hub.finish,
                      ),
                      quiet(
                        'guide-tour-back',
                        copy.text('tour.back'),
                        hub.back,
                      ),
                    ],
                    StarBridgeActionButton(
                      controlKey: const Key('guide-tour-next'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: (_) => hub.next(),
                      child: Text(copy.text(run.last ? finish : 'tour.next')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
