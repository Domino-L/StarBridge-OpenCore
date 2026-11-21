import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'overlay_members_size.dart';

/// Edges are ten viewport pixels wide; corners are twenty, independent of zoom.
///
/// [project] takes a flat point (surface pixels) to where the visor shows it
/// (OverlayVisorProjection.point) while the members lean; null draws on the
/// flat box. Leaning, the handles sit on the shown panel: the corners on its
/// shown corners, the side on its shown edge (still upright, the lean turns
/// about a vertical axis) and the top and bottom along its slanting shown
/// edges (11-15 user screenshot, "15度 右边": the handles were drawn on the flat
/// box beside the tilted panel).
List<Widget> overlayMembersResizeHandles({
  required Rect box,
  required double sx,
  required double sy,
  required bool right,
  required Color color,
  required Color background,
  required void Function(OverlayMembersHandle handle, Offset globalPosition)
  onStart,

  /// The pointer's global position at each step of the drag.
  required ValueChanged<Offset> onUpdate,
  required VoidCallback onEnd,
  Offset Function(Offset flat)? project,
}) {
  Offset shown(Offset flat) {
    final p = project == null ? flat : project(flat);
    return Offset(p.dx * sx, p.dy * sy);
  }

  final topLeft = shown(box.topLeft), topRight = shown(box.topRight);
  final bottomLeft = shown(box.bottomLeft);
  final bottomRight = shown(box.bottomRight);
  final sideTop = right ? topLeft : topRight;
  final sideBottom = right ? bottomLeft : bottomRight;

  Widget body(OverlayMembersHandle kind, Size hit, MouseCursor cursor) =>
      MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => onStart(kind, details.globalPosition),
          // the pointer's global position, not the delta: inside a turned
          // band the delta is in the band's own turned axes (review
          // CX-HANDLES-PROJ-073-R1 P2)
          onPanUpdate: (details) => onUpdate(details.globalPosition),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: color, width: 2),
              ),
              child: SizedBox(
                width: kind == OverlayMembersHandle.side ? 2 : hit.width,
                height:
                    kind == OverlayMembersHandle.top ||
                        kind == OverlayMembersHandle.bottom
                    ? 2
                    : hit.height,
              ),
            ),
          ),
        ),
      );

  Widget handle(
    OverlayMembersHandle kind,
    Rect hit,
    MouseCursor cursor,
    String name,
  ) => Positioned.fromRect(
    rect: hit,
    key: Key('overlay-visor-members-resize-$name'),
    child: body(kind, hit.size, cursor),
  );

  // A top or bottom edge from [a] to [b]: flat, a 10 px band over the edge;
  // leaning, the band turns with the shown edge (hit testing follows it).
  Widget edge(OverlayMembersHandle kind, Offset a, Offset b, String name) {
    if (project == null) {
      return handle(
        kind,
        Rect.fromLTWH(a.dx, a.dy - 5, b.dx - a.dx, 10),
        SystemMouseCursors.resizeUpDown,
        name,
      );
    }
    final length = (b - a).distance;
    final centre = (a + b) / 2;
    return Positioned(
      key: Key('overlay-visor-members-resize-$name'),
      left: centre.dx - length / 2,
      top: centre.dy - 5,
      width: length,
      height: 10,
      child: Transform.rotate(
        angle: (b - a).direction,
        child: body(kind, Size(length, 10), SystemMouseCursors.resizeUpDown),
      ),
    );
  }

  return [
    edge(OverlayMembersHandle.top, topLeft, topRight, 'top'),
    edge(OverlayMembersHandle.bottom, bottomLeft, bottomRight, 'bottom'),
    handle(
      OverlayMembersHandle.side,
      Rect.fromLTWH(sideTop.dx - 5, sideTop.dy, 10, sideBottom.dy - sideTop.dy),
      SystemMouseCursors.resizeLeftRight,
      right ? 'left' : 'right',
    ),
    handle(
      OverlayMembersHandle.topCorner,
      Rect.fromCenter(center: sideTop, width: 20, height: 20),
      right
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft,
      right ? 'top-left' : 'top-right',
    ),
    handle(
      OverlayMembersHandle.bottomCorner,
      Rect.fromCenter(center: sideBottom, width: 20, height: 20),
      right
          ? SystemMouseCursors.resizeUpRightDownLeft
          : SystemMouseCursors.resizeUpLeftDownRight,
      right ? 'bottom-left' : 'bottom-right',
    ),
  ];
}
