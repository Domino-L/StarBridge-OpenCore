import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_visor_sim_palette.dart';
import 'overlay_visor_layout.dart';
import 'overlay_visor_sim_panel.dart';
import 'overlay_workspace_models.dart';

/// A sample rally drawn the visor's way (StarBridge.Desktop OverlayVisorDraw.Top,
/// the rally look), so the editors show the rally block as the game shows it
/// (11-18 user: "还有浮层编辑里的召集", "照真实召集的样子"): the amber head with
/// the minutes left, the body in large warm text, the hotkeys in dim text and
/// the amber rule under them, all centred, at about 60%. Still: no opening
/// frame and no sweep. A small amber "sample" mark sits at the top right.
///
/// The box is the rally's band (OverlayVisorLayout.rallyBox), which starts at
/// [boxTop] in the Top layer's design units; [unit] is surface pixels per
/// design unit (the box width / [OverlayVisorLayout] rally width).
class OverlayVisorRallySample extends StatelessWidget {
  const OverlayVisorRallySample({super.key, required this.unit});

  final double unit;

  /// Where the editor's rally box starts inside the visor's Top layer, and
  /// the layer's width (design units, OverlayVisorDraw.TopWidth).
  static const boxTop = 52.0, width = 1100.0;

  /// The sample's opacity: plainly a sample over the game.
  static const opacity = 0.6;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Stack(
      key: const Key('overlay-visor-rally-sample'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: CustomPaint(
              painter: OverlayVisorRallyPainter(
                head: strings.text('overlay.sample.rallyHead'),
                body: strings.text('overlay.sample.rallyBody'),
                hint: strings.text('overlay.sample.rallyHint'),
                unit: unit,
              ),
            ),
          ),
        ),
        // "示例": this is not a real rally
        Positioned(
          top: 6 * unit,
          right: 12 * unit,
          child: DecoratedBox(
            key: const Key('overlay-visor-rally-sample-mark'),
            decoration: BoxDecoration(
              color: OverlayVisorSimColors.warn.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(2 * unit),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 6 * unit,
                vertical: 1.5 * unit,
              ),
              child: Text(
                strings.text('overlay.sample.rallyMark'),
                style: TextStyle(
                  fontFamily: OverlayVisorSimPainter.hanFamily,
                  fontSize: OverlayVisorSimPainter.drawnSize(13) * unit,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: OverlayVisorSimPalette.markText,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rally lines of OverlayVisorDraw.Top in its design units: centred at
/// x 550; the head at y 60 (14, semibold, warn), the body at 82 (30,
/// semibold, warm), the hint at 134 (14, medium, dim), and the rule at 164.5
/// (560 wide, the rally colour from clear to half).
class OverlayVisorRallyPainter extends CustomPainter {
  const OverlayVisorRallyPainter({
    required this.head,
    required this.body,
    required this.hint,
    required this.unit,
  });

  final String head, body, hint;
  final double unit;

  static const _cx = OverlayVisorRallySample.width / 2, _ry = 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(unit);
    canvas.translate(0, -OverlayVisorRallySample.boxTop);
    void centre(
      String text,
      double y,
      FontWeight weight,
      double size,
      Color color,
    ) {
      if (text.isEmpty) return;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: OverlayVisorSimPainter.hanFamily,
            fontFamilyFallback: const [OverlayVisorSimPainter.hanFamily],
            fontSize: OverlayVisorSimPainter.drawnSize(size),
            fontWeight: weight,
            color: color,
            shadows: const [
              Shadow(color: OverlayVisorSimPalette.textEdge, blurRadius: 1.2),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(canvas, Offset(_cx - painter.width / 2, y));
    }

    const warn = OverlayVisorSimColors.warn;
    centre(head, _ry, FontWeight.w600, 14, warn);
    centre(body, _ry + 22, FontWeight.w600, 30, OverlayVisorSimColors.warm);
    centre(hint, _ry + 74, FontWeight.w500, 14, OverlayVisorSimColors.dim);
    const bw = 560.0, bx = _cx - bw / 2, by = _ry + 104;
    final rule = Rect.fromLTWH(bx, by + 0.5, bw, 1.4);
    canvas.drawRect(
      rule,
      Paint()
        ..shader = LinearGradient(
          colors: [warn.withValues(alpha: 0), warn.withValues(alpha: 0.5)],
        ).createShader(rule),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OverlayVisorRallyPainter old) =>
      old.head != head ||
      old.body != body ||
      old.hint != hint ||
      old.unit != unit;
}

/// The rally's other dock while its block is selected or dragged (11-18
/// "照真实召集的样子", section 2): a faint amber dashed slot at the other
/// spot ("也可以放在底部"); while dragging, both spots, the one the block
/// would go to brighter ("松手放在这里 · 底部"). Nothing otherwise. [top] and
/// [bottom] are the two rally boxes, [split] the height past which the block
/// docks at the bottom (OverlayVisorLayout.dockRally), all in the parent's
/// coordinates; [dragged] is where the block shows while dragged. A slot the
/// dragged block covers by more than a third shows no words, only its brighter
/// outline and ground (11-18, section 2: the words read through the sample).
class OverlayVisorRallySlots extends StatelessWidget {
  const OverlayVisorRallySlots({
    super.key,
    required this.top,
    required this.bottom,
    required this.atBottom,
    required this.split,
    this.dragged,
  });

  final Rect top, bottom;
  final bool atBottom;
  final double split;
  final Rect? dragged;

  /// The slots for the rally block in [layout] on [surface], drawn on a canvas
  /// [scale] times the surface; null unless the block is on the visor and
  /// [selected] or dragged ([dragDy]: how far it is dragged up or down,
  /// OverlayVisorLayout.rallyFollow).
  static Widget? forLayout({
    required List<OverlayWorkspaceLayoutItem> layout,
    required OverlayWorkspaceSettings settings,
    required Size surface,
    required Offset scale,
    required bool selected,
    double? dragDy,
  }) {
    final notice = layout.where((item) => item.key == 'Notice').firstOrNull;
    if (notice == null || !OverlayVisorLayout.active(settings)) return null;
    if (!selected && dragDy == null) return null;
    Rect scaled(Rect r) => Rect.fromLTRB(
      r.left * scale.dx,
      r.top * scale.dy,
      r.right * scale.dx,
      r.bottom * scale.dy,
    );
    final docked = OverlayVisorLayout.rallyBox(notice, settings, surface);
    final dragging = dragDy != null;
    final shown = dragging
        ? OverlayVisorLayout.rallyFollow(docked, dragDy, surface)
        : docked;
    return Positioned.fill(
      child: OverlayVisorRallySlots(
        top: scaled(
          OverlayVisorLayout.rallyBox(notice, settings, surface, bottom: false),
        ),
        bottom: scaled(
          OverlayVisorLayout.rallyBox(notice, settings, surface, bottom: true),
        ),
        atBottom: notice.verticalAnchor == 'Bottom',
        split:
            OverlayVisorLayout.rallySplit(notice, settings, surface) * scale.dy,
        dragged: dragging ? scaled(shown) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final box = dragged;
    final centre = box?.center.dy;
    bool covered(Rect slot) =>
        box != null &&
        box.overlaps(slot) &&
        box.intersect(slot).height > slot.height / 3;
    final slots = <(Rect, String, bool, String)>[
      if (centre == null)
        atBottom
            ? (top, 'overlay.visor.rallyAlsoTop', false, 'top')
            : (bottom, 'overlay.visor.rallyAlsoBottom', false, 'bottom')
      else ...[
        centre > split
            ? (top, 'overlay.workspace.anchor.Top', false, 'top')
            : (top, 'overlay.visor.rallyDropTop', true, 'top'),
        centre > split
            ? (bottom, 'overlay.visor.rallyDropBottom', true, 'bottom')
            : (bottom, 'overlay.workspace.anchor.Bottom', false, 'bottom'),
      ],
    ];
    return IgnorePointer(
      child: Stack(
        children: [
          for (final (rect, label, near, id) in slots)
            Positioned.fromRect(
              rect: rect,
              child: CustomPaint(
                key: Key('overlay-visor-rally-slot-$id${near ? '-near' : ''}'),
                painter: _RallySlotPainter(near: near),
                child: covered(rect)
                    ? null
                    : Center(
                        child: Text(
                          strings.text(label),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: near
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: OverlayVisorSimColors.warn.withValues(
                              alpha: near ? 1 : 0.7,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RallySlotPainter extends CustomPainter {
  const _RallySlotPainter({required this.near});

  final bool near;

  @override
  void paint(Canvas canvas, Size size) {
    const warn = OverlayVisorSimColors.warn;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = warn.withValues(alpha: near ? 0.16 : 0.05),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = near ? 1.5 : 1
      ..color = warn.withValues(alpha: near ? 0.95 : 0.45);
    const dash = 6.0, gap = 4.0;
    for (final metric
        in (Path()..addRect(rect.deflate(0.5))).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), line);
      }
    }
  }

  @override
  bool shouldRepaint(_RallySlotPainter old) => old.near != near;
}
