import 'dart:math' as math;
import 'dart:ui';

import 'overlay_visor_layout.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_visor_specs.dart';

/// RowsFor in visor design units: title, counts, page inset, then member rows.
abstract final class OverlayMembersSize {
  static final width = overlayWorkspaceVisorFieldSpecs.singleWhere(
    (s) => s.field == 'visorMembersWidth',
  );
  static final height = overlayWorkspaceVisorFieldSpecs.singleWhere(
    (s) => s.field == 'visorMembersHeight',
  );
  static const overhead = 51 + 20 + 3;
  static const rowHeight = 35;
  static int get maxRows => math.min(
    overlayWorkspaceVisorMembersMaxRows,
    math.max(1, (height.maximum - overhead) ~/ rowHeight),
  );
  static int rows(num value) =>
      // Match Desktop RowsFor, retaining the old capacity at old heights.
      ((value - overhead) / rowHeight)
          .floor()
          .clamp(1, value <= 554 ? 12 : maxRows)
          .toInt();
  static int stepHeight(num value, int direction) {
    final current = rows(value);
    final next = (current + direction).clamp(1, maxRows);
    if (next == current) {
      return value.clamp(height.minimum, height.maximum).round();
    }
    // A thirteenth row must cross the preserved legacy height range.
    final target = math.max(overhead + next * rowHeight, next > 12 ? 555 : 0);
    return target.clamp(height.minimum, height.maximum).round();
  }

  static int stepWidth(num value, int direction) =>
      (value + direction * 10).clamp(width.minimum, width.maximum).round();
}

enum OverlayMembersHandle { top, bottom, side, topCorner, bottomCorner }

/// A fixed gesture snapshot; deltas are surface pixels, not viewport pixels.
final class OverlayMembersResize {
  OverlayMembersResize(
    this.item,
    this.settings,
    this.box,
    this.surface,
    this.handle,
  ) : right = OverlayVisorLayout.membersAnchor(item, surface).$1;
  final OverlayWorkspaceLayoutItem item;
  final OverlayWorkspaceSettings settings;
  final Rect box;
  final Size surface;
  final OverlayMembersHandle handle;
  final bool right;
  bool get changesWidth =>
      handle != OverlayMembersHandle.top &&
      handle != OverlayMembersHandle.bottom;
  bool get changesHeight => handle != OverlayMembersHandle.side;
  bool get top =>
      handle == OverlayMembersHandle.top ||
      handle == OverlayMembersHandle.topCorner;

  ({int width, int height, Rect box, OverlayWorkspaceLayoutItem item}) at(
    Offset delta,
  ) {
    final scale =
        OverlayVisorLayout.designUnit *
        OverlayVisorLayout.sizeFactor(settings) *
        surface.height /
        1080;
    final margin = OverlayVisorLayout.screenMargin * surface.height / 1080;
    final maxWidth = math.min(
      OverlayMembersSize.width.maximum,
      (right ? box.right - margin : surface.width - margin - box.left) / scale,
    );
    final maxHeight = math.min(
      OverlayMembersSize.height.maximum,
      (top ? box.bottom - margin : surface.height - margin - box.top) / scale,
    );
    int dimension(double value, double minimum, double maximum) => value
        .round()
        .clamp(minimum.ceil(), math.max(minimum.ceil(), maximum.floor()))
        .toInt();
    final width = changesWidth
        ? dimension(
            OverlayVisorLayout.membersWidth(settings) +
                (right ? -delta.dx : delta.dx) / scale,
            OverlayMembersSize.width.minimum,
            maxWidth,
          )
        : OverlayVisorLayout.membersWidth(settings).round();
    final height = changesHeight
        ? dimension(
            OverlayVisorLayout.membersHeight(settings) +
                (top ? -delta.dy : delta.dy) / scale,
            OverlayMembersSize.height.minimum,
            maxHeight,
          )
        : OverlayVisorLayout.membersHeight(settings).round();
    final next = Rect.fromLTWH(
      right ? box.right - width * scale : box.left,
      top ? box.bottom - height * scale : box.top,
      width * scale,
      height * scale,
    );
    return (
      width: width,
      height: height,
      box: next,
      item: OverlayVisorLayout.save(item, next, surface, rightAnchor: right),
    );
  }
}
