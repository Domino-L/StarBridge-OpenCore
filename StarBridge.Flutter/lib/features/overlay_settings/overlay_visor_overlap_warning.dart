import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_visor_sim_palette.dart';
import 'overlay_visor_arrange.dart';
import 'overlay_visor_layout.dart';
import 'overlay_workspace_models.dart';

/// The editors' warning where the events and the members would overlap on the
/// visor (11-18 user: "那就应该在编辑时出现重叠警告，如果无视就允许重叠"): the
/// overlap hatched red and a note beside the column saying how much room is
/// missing and what helps. A warning only: the layout saves as it is and the
/// visor draws the two over each other. Copy is a draft (11-18 preview).
class OverlayVisorOverlapWarning extends StatelessWidget {
  const OverlayVisorOverlapWarning({
    super.key,
    required this.overlap,
    required this.count,
    required this.missing,
    this.up = true,
  });

  /// The overlap in the parent's coordinates.
  final Rect overlap;

  /// The most events at once, and the room missing with the gap the events
  /// keep (pixels at 1080p; review CX-OVERLAY-M102-R1 P2-7).
  final int count, missing;

  /// The events gave way up (to the top of their column), else down (to the
  /// screen's bottom): the advice follows the way they went.
  final bool up;

  /// The warning for [layout] on [surface], drawn on a canvas [scale] times
  /// the surface; null off the visor or when nothing overlaps.
  static Widget? forLayout({
    required List<OverlayWorkspaceLayoutItem> layout,
    required OverlayWorkspaceSettings settings,
    required Size surface,
    Offset scale = const Offset(1, 1),
  }) {
    if (!OverlayVisorLayout.active(settings)) return null;
    final r = OverlayVisorArrange.eventsOverlap(layout, settings, surface);
    if (r == null) return null;
    final boxes = OverlayVisorArrange.all(layout, settings, surface);
    final up = boxes['Events']!.center.dy <= boxes['Members']!.center.dy;
    return Positioned.fill(
      child: IgnorePointer(
        child: OverlayVisorOverlapWarning(
          overlap: Rect.fromLTRB(
            r.left * scale.dx,
            r.top * scale.dy,
            r.right * scale.dx,
            r.bottom * scale.dy,
          ),
          count:
              (settings['eventNotificationMaxVisibleCount'] as num?)?.round() ??
              3,
          missing: ((r.height * 1080 / surface.height) + OverlayVisorLayout.gap)
              .ceil(),
          up: up,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    const red = OverlayVisorSimColors.bad;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = constraints.biggest;
        const width = 360.0;
        final left = (overlap.left - 16 - width)
            .clamp(4.0, math.max(4.0, canvas.width - width - 4))
            .toDouble();
        return Stack(
          key: const Key('overlay-visor-overlap-warning'),
          children: [
            Positioned.fromRect(
              rect: overlap,
              child: const CustomPaint(painter: _HatchPainter(red)),
            ),
            // beside the overlap, kept on the canvas: in its lower half it hangs
            // up from the overlap's bottom
            Positioned(
              left: left,
              width: width,
              top: overlap.center.dy > canvas.height / 2
                  ? null
                  : math.max(4.0, overlap.top - 10),
              bottom: overlap.center.dy > canvas.height / 2
                  ? math.max(4.0, canvas.height - overlap.bottom - 10)
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: OverlayVisorSimPalette.warningPlate,
                  border: Border.all(color: red, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.text('overlay.visor.overlapTitle'),
                        style: const TextStyle(
                          color: red,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings
                            .text(
                              up
                                  ? 'overlay.visor.overlapBody'
                                  : 'overlay.visor.overlapBodyDown',
                            )
                            .replaceAll('{count}', '$count')
                            .replaceAll('{gap}', '$missing'),
                        style: const TextStyle(
                          color: OverlayVisorSimPalette.warningText,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.22));
    canvas.save();
    canvas.clipRect(rect);
    final line = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    for (var x = -size.height; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
    }
    canvas.restore();
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}
