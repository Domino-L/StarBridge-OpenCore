import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'overlay_visor_layout.dart';
import 'overlay_workspace_models.dart';

/// The visor's arrangement of its blocks in the layout editor (StarBridge.Core
/// OverlayVisorLayout.Arrange step by step), used by [OverlayVisorLayout.arrange]
/// and [OverlayVisorLayout.eventsPlacement]. Split from overlay_visor_layout.dart
/// to keep each file within the architecture size gate.
abstract final class OverlayVisorArrange {
  static Map<String, Rect> all(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    final unit = 1080 / surface.height;
    final groups = _arrange(layout, settings, surface);
    return {
      for (final id in groups.keys)
        id: Rect.fromLTWH(
          groups[id]!.box.left / unit,
          groups[id]!.box.top / unit,
          groups[id]!.box.width / unit,
          groups[id]!.box.height / unit,
        ),
    };
  }

  /// Where the events and the members still overlap after the events gave way
  /// up as far as they may (surface pixels), or null (StarBridge.Core
  /// OverlayVisorLayout.EventsOverlap). The editors warn about it; the visor
  /// draws them as they are (11-18 user: "那就应该在编辑时出现重叠警告，如果无视就
  /// 允许重叠").
  static Rect? eventsOverlap(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    final boxes = all(layout, settings, surface);
    final events = boxes['Events'], members = boxes['Members'];
    if (events == null || members == null || !events.overlaps(members)) {
      return null;
    }
    return events.intersect(members);
  }

  /// The groups the visor tilts (OverlayVisorRenderer: a free group, or one in
  /// a side slot) and the side each leans to (true: the right edge). A group
  /// in a top or bottom slot is drawn flat and is left out.
  static Map<String, bool> tilts(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) => {
    for (final MapEntry(key: id, value: g) in _arrange(
      layout,
      settings,
      surface,
    ).entries)
      if (g.slot == null || g.slot![0] == 'L' || g.slot![0] == 'R')
        id: g.slot == null ? g.right : g.slot![0] == 'R',
  };

  static Map<String, _VisorGroup> _arrange(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    final unit = 1080 / surface.height;
    final width = surface.width * unit;
    final groups = <String, _VisorGroup>{};
    for (final item in layout) {
      final shown = switch (item.key) {
        'Members' => settings['showMembers'] != false,
        'Chat' => settings['showChat'] != false,
        _ => false,
      };
      if (!shown || groups.containsKey(item.key)) continue;
      final size = item.key == 'Members'
          ? OverlayVisorLayout.membersBoxSize(settings)
          : OverlayVisorLayout.chatBoxSize(settings);
      groups[item.key] = OverlayVisorLayout.unmoved(item, surface)
          ? _VisorGroup(
              item.key == 'Members' ? 'R-mid' : 'L-bottom',
              Offset.zero & size,
            )
          : _VisorGroup(
              null,
              _corner(item, size, surface, unit),
              right: _right(item, surface),
            );
    }
    if (OverlayVisorLayout.active(settings) &&
        settings['showEventNotifications'] != false) {
      final size = OverlayVisorLayout.eventsBoxSize(settings);
      final right = settings['eventNotificationSide'] != 'Left';
      // where across (11-12 "应该允许事件随意调整位置了"): the screen-edge side's
      // x as a screen fraction; unset, they hug that edge (OverlayVisorPlacement)
      final across = OverlayVisorLayout.eventsX(settings);
      final edgeX = across == null
          ? (right ? width - OverlayVisorLayout.edge : OverlayVisorLayout.edge)
          : across * width;
      groups['Events'] = _eventsOnDefaultSlot(settings)
          ? _VisorGroup('R-top', Offset.zero & size)
          : _VisorGroup(
              null,
              right: right,
              Offset(
                    right ? edgeX - size.width : edgeX,
                    (((settings['eventNotificationY'] as num?)?.toDouble() ??
                                0.34)
                            .clamp(0.0, 1.0)) *
                        (1080 - OverlayVisorLayout.eventPlacementHeight),
                  ) &
                  size,
            );
    }
    // a side column too tall for its OverlayVisorLayout.edge: its last default group moves to the
    // first free slot it may take on another OverlayVisorLayout.edge (review R7, as the visor)
    for (var depth = 0; depth < 3; depth++) {
      String? moved;
      for (final side in const ['L', 'R']) {
        final ids = _column(groups, side);
        if (ids.length < 2) continue;
        final (lo, hi) = side == 'L' ? (110.0, 877.0) : (150.0, 790.0);
        final total =
            ids.fold(0.0, (sum, id) => sum + groups[id]!.box.height) +
            OverlayVisorLayout.gap * (ids.length - 1);
        if (total <= hi - lo) continue;
        final mover = ids.last;
        // m102 (11-18 "成员不挪，事件让，让不开就重叠"): the members never change
        // sides, and the events above them stay to give way up
        if (mover == 'Members' ||
            mover == 'Events' && ids.contains('Members')) {
          continue;
        }
        final used = {for (final g in groups.values) ?g.slot};
        final free = _slotPreference
            .where(
              (slot) =>
                  slot[0] != side &&
                  !used.contains(slot) &&
                  (mover != 'Members' || slot[0] == 'L' || slot[0] == 'R'),
            )
            .firstOrNull;
        if (free == null) continue;
        groups[mover]!.slot = free;
        moved = mover;
        break;
      }
      if (moved == null) break;
    }
    // slots off the side columns sit where they are
    for (final g in groups.values) {
      final slot = g.slot;
      if (slot != null && slot[0] != 'L' && slot[0] != 'R') {
        g.box = OverlayVisorLayout.place(slot, g.box.size, width) & g.box.size;
      }
    }
    // default slots: each side column, a OverlayVisorLayout.gap apart, pulled up past its end
    for (final side in const ['L', 'R']) {
      final ids = _column(groups, side);
      if (ids.isEmpty) continue;
      final (lo, hi) = side == 'L' ? (110.0, 877.0) : (150.0, 790.0);
      var y = 0.0;
      final tops = <String, double>{};
      String? previous;
      for (final id in ids) {
        final size = groups[id]!.box.size;
        final at = OverlayVisorLayout.place(groups[id]!.slot!, size, width);
        // m102: the members are not pushed down by the events above them;
        // those give way up instead (below)
        y = id == 'Members' && previous == 'Events'
            ? at.dy
            : math.max(at.dy, y);
        tops[id] = y;
        groups[id]!.box = Offset(at.dx, y) & size;
        y += size.height + OverlayVisorLayout.gap;
        previous = id;
      }
      final over = math.max(0.0, y - OverlayVisorLayout.gap - hi);
      for (final id in ids) {
        final box = groups[id]!.box;
        groups[id]!.box = box.translate(
          0,
          math.max(lo, tops[id]! - over) - box.top,
        );
      }
    }
    // on screen
    for (final g in groups.values) {
      final b = g.box;
      g.box =
          Offset(
            b.left.clamp(
              OverlayVisorLayout.screenMargin,
              math.max(
                OverlayVisorLayout.screenMargin,
                width - OverlayVisorLayout.screenMargin - b.width,
              ),
            ),
            b.top.clamp(
              OverlayVisorLayout.screenMargin,
              math.max(
                OverlayVisorLayout.screenMargin,
                1080 - OverlayVisorLayout.screenMargin - b.height,
              ),
            ),
          ) &
          b.size;
    }
    // overlaps: moved groups first, then members, events, chat
    const priority = ['Members', 'Events', 'Chat'];
    final order = groups.keys.toList()
      ..sort((a, b) {
        final free = (groups[a]!.slot == null ? 0 : 1).compareTo(
          groups[b]!.slot == null ? 0 : 1,
        );
        return free != 0
            ? free
            : priority.indexOf(a).compareTo(priority.indexOf(b));
      });
    // m102 (11-18 "事件如果要向下和成员重叠时，应该自己向上避开"): the members
    // keep their place before the events, wherever either was put
    final e = order.indexOf('Events'), t = order.indexOf('Members');
    if (e >= 0 && t > e) order.insert(e, order.removeAt(t));
    for (var i = 1; i < order.length; i++) {
      final g = groups[order[i]]!;
      final placed = [for (final id in order.take(i)) groups[id]!.box];
      final h = g.box.height;
      final members = groups['Members']?.box;
      if (order[i] == 'Events' &&
          members != null &&
          order.take(i).contains('Members') &&
          Rect.fromLTWH(
            g.box.left,
            g.box.top - OverlayVisorLayout.gap,
            g.box.width,
            h + 2 * OverlayVisorLayout.gap,
          ).overlaps(members)) {
        // on (or within a gap of) the members, the events give way, the
        // members never: from above up to a gap above them, no higher than the
        // top of the side's column; placed lower down a gap below them, no
        // lower than the screen allows. Past that they overlap and the editors
        // warn (eventsOverlap). A spot that hits another group is left to the
        // usual rule below.
        final ceiling = g.box.center.dx > width / 2 ? 150.0 : 110.0;
        const gap = OverlayVisorLayout.gap;
        // they only ever move away from the members: a ceiling or floor
        // never pushes them closer (review CX-OVERLAY-M102-R1 P2-1)
        final up = Rect.fromLTWH(
          g.box.left,
          g.box.center.dy <= members.center.dy
              ? math.min(g.box.top, math.max(ceiling, members.top - gap - h))
              : math.max(
                  g.box.top,
                  math.min(
                    1080 - OverlayVisorLayout.screenMargin - h,
                    members.bottom + gap,
                  ),
                ),
          g.box.width,
          h,
        );
        if (!placed.where((o) => o != members).any(up.overlaps)) {
          g.box = up;
          continue;
        }
      }
      if (!placed.any(g.box.overlaps)) continue;
      final options =
          placed
              .expand(
                (o) => [
                  o.top - OverlayVisorLayout.gap - h,
                  o.bottom + OverlayVisorLayout.gap,
                ],
              )
              .where(
                (y) =>
                    y >= OverlayVisorLayout.screenMargin &&
                    y + h <= 1080 - OverlayVisorLayout.screenMargin,
              )
              .where(
                (y) => !placed.any(
                  Rect.fromLTWH(g.box.left, y, g.box.width, h).overlaps,
                ),
              )
              .toList()
            ..sort(
              (a, b) => (a - g.box.top).abs().compareTo((b - g.box.top).abs()),
            );
      if (options.isNotEmpty) {
        g.box = Rect.fromLTWH(g.box.left, options.first, g.box.width, h);
      }
    }
    return groups;
  }

  /// The default groups in a side column, top to bottom.
  static List<String> _column(Map<String, _VisorGroup> groups, String side) =>
      groups.keys
          .where((id) => groups[id]!.slot?.startsWith(side) ?? false)
          .toList()
        ..sort(
          (a, b) =>
              _slotOrder(groups[a]!.slot!)
                  .compareTo(_slotOrder(groups[b]!.slot!)),
        );

  /// Where a group from an overflowing column goes first (OverlayVisorLayout
  /// Pref).
  static const _slotPreference = [
    'B-mid',
    'T-left',
    'T-right',
    'R-top',
    'R-mid',
    'R-bottom',
    'L-top',
    'L-mid',
    'L-bottom',
  ];

  static int _slotOrder(String slot) => switch (slot.substring(2)) {
    'top' => 0,
    'mid' => 1,
    _ => 2,
  };

  /// Events never moved: the right side at the shipped height, at the edge.
  static bool _eventsOnDefaultSlot(OverlayWorkspaceSettings settings) =>
      OverlayVisorLayout.eventsX(settings) == null &&
      settings['eventNotificationSide'] != 'Left' &&
      (((settings['eventNotificationY'] as num?)?.toDouble() ?? 0.34) - 0.34)
              .abs() <=
          0.02;

  /// The side a moved module is anchored to (OverlayVisorPlacement.Spots).
  static bool _right(OverlayWorkspaceLayoutItem item, Size surface) =>
      switch (item.horizontalAnchor) {
        'Right' => true,
        'Left' => false,
        _ =>
          OverlayVisorLayout.resolve(item, surface).center.dx >
              surface.width / 2,
      };

  /// A moved block's box in layout units: its anchored corner where it was
  /// saved (as OverlayVisorSpot.Corner).
  static Rect _corner(
    OverlayWorkspaceLayoutItem item,
    Size size,
    Size surface,
    double unit,
  ) {
    final rect = OverlayVisorLayout.resolve(item, surface);
    final r = Rect.fromLTRB(
      rect.left * unit,
      rect.top * unit,
      rect.right * unit,
      rect.bottom * unit,
    );
    final right = _right(item, surface);
    final bottom = switch (item.verticalAnchor) {
      'Bottom' => true,
      'Top' => false,
      _ => r.center.dy > 540,
    };
    return Offset(
          right ? r.right - size.width : r.left,
          bottom ? r.bottom - size.height : r.top,
        ) &
        size;
  }
}

/// A visor block while it is being arranged: its default slot (null when the
/// user moved it), its box in layout units, and for a moved block the side it
/// is anchored to (OverlayVisorSpot.RightAligned).
final class _VisorGroup {
  _VisorGroup(this.slot, this.box, {this.right = false});
  String? slot;
  Rect box;
  final bool right;
}
