import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../../features/overlay_settings/overlay_visor_arrange.dart';
import '../../features/overlay_settings/overlay_visor_layout.dart';
import '../../features/overlay_settings/overlay_visor_projection.dart';
import '../../features/overlay_settings/overlay_workspace_models.dart';

/// What one placement step on the visor changes.
sealed class MenuHudVisorEdit {
  const MenuHudVisorEdit();
}

/// A layout module moved (members, chat) or docked (the rally).
final class MenuHudVisorItem extends MenuHudVisorEdit {
  const MenuHudVisorItem(this.item);
  final OverlayWorkspaceLayoutItem item;
}

/// The events' side, height and place across (11-12 "应该允许事件随意调整位置
/// 了": [x] a screen fraction of the side's edge, -1 at that edge), as the
/// visor reads them.
final class MenuHudVisorEvents extends MenuHudVisorEdit {
  const MenuHudVisorEvents(this.right, this.y, [this.x = -1]);
  final bool right;
  final double y, x;
}

/// The DM badge: screen fractions, or -1 for its default spot.
final class MenuHudVisorBadge extends MenuHudVisorEdit {
  const MenuHudVisorBadge(this.x, this.y);
  final double x, y;
}

/// Alt+M placement on the visor (11-11 user: "Alt+M 按面罩排布"): every block
/// where the visor draws it, moved by the visor's own rules, as the client's
/// layout editor does (OverlayVisorLayout). Blocks are never resized here:
/// the visor sizes them itself ("面罩大小").
abstract final class MenuHudVisorPlacement {
  /// [settings] with the gesture in flight applied (events, badge).
  static OverlayWorkspaceSettings withLocal(
    OverlayWorkspaceSettings settings, {
    ({String side, double y})? events,
    double? eventsX,
    ({double x, double y})? badge,
  }) {
    var next = settings;
    if (events != null) {
      next = next
          .withValue('eventNotificationSide', events.side)
          .withValue('eventNotificationY', events.y);
      if (eventsX != null && next.values.containsKey('visorEventsX')) {
        next = next.withValue('visorEventsX', eventsX);
      }
    }
    if (badge != null) {
      next = next
          .withValue('visorBadgeX', badge.x)
          .withValue('visorBadgeY', badge.y);
    }
    return next;
  }

  /// Every block where the visor draws it: the rally at the top or bottom
  /// centre, members, chat and events as the visor arranges them, the DM
  /// badge, and the crosshair at the centre.
  /// [rally]: the rally's start and drag while it is dragged.
  static Map<String, Rect> rects(
    List<OverlayWorkspaceLayoutItem> items,
    OverlayWorkspaceSettings visor,
    bool Function(String key) visible,
    Size surface, {
    (OverlayWorkspaceLayoutItem, double)? rally,
  }) {
    final rects = <String, Rect>{};
    final notice = items.where((item) => item.key == 'Notice').firstOrNull;
    if (notice != null && visible('Notice')) {
      rects['Notice'] = switch (rally) {
        (final start, final dy) => rallyDragged(start, visor, surface, dy),
        null => OverlayVisorLayout.rallyBox(notice, visor, surface),
      };
    }
    for (final entry in OverlayVisorArrange.all(
      items,
      visor,
      surface,
    ).entries) {
      if (visible(entry.key)) rects[entry.key] = entry.value;
    }
    // the DM badge is gone (11-13 user: "私信角标 … 整个都不要")
    if (visible('Crosshair')) {
      rects['Crosshair'] = Rect.fromCenter(
        center: surface.center(Offset.zero),
        width: 80,
        height: 80,
      );
    }
    return rects;
  }

  /// One drag step from where the gesture began ([start] for a module,
  /// [startBox] for the events or the badge), [delta] the pointer's move on
  /// screen (surface pixels) since it grabbed at [grab]: the change to send
  /// (null when nothing changes) and the snap guides. A leaning block moves
  /// so the point grabbed stays under the pointer, and the events' side is
  /// where the pointer is on screen (review CX-VISOR-EVENTS3D-R1).
  static (MenuHudVisorEdit?, List<OverlayVisorGuide>) drag({
    required String key,
    required OverlayWorkspaceLayoutItem? start,
    required Rect? startBox,
    required Offset delta,
    required Offset pointer,
    required List<OverlayWorkspaceLayoutItem> items,
    required OverlayWorkspaceSettings visor,
    required Size surface,
    required bool snapping,
    Offset? grab,
  }) {
    final leans = OverlayVisorProjection.tilts(
      items,
      visor,
      surface,
    ).containsKey(key);
    final degrees = OverlayVisorProjection.degrees(visor);
    final distance = OverlayVisorProjection.distance(visor);
    // the block where it was when grabbed, and the grabbed point on it (flat)
    final from = switch (key) {
      'Members' || 'Chat' when start != null => OverlayVisorLayout.boxOf(
        start,
        visor,
        surface,
        [for (final i in items) i.key == key ? start : i],
      ),
      _ => startBox,
    };
    if (grab != null) {
      pointer = grab + delta;
      if (leans && degrees > 0 && from != null) {
        final flat = OverlayVisorProjection.unproject(
          grab,
          right: from.center.dx > surface.width / 2,
          degrees: degrees,
          surface: surface,
          distance: distance,
        );
        // worked out from where the pointer is each time, through the camera
        // of the side the block lands on (review CX-VISOR-EVENTS3D-R2); the
        // events too move anywhere now (11-12)
        delta = OverlayVisorProjection.follow(
          flat,
          from,
          pointer,
          degrees: degrees,
          surface: surface,
          distance: distance,
        );
      }
    }
    switch (key) {
      case 'Events':
        if (startBox == null) return (null, const []);
        return (
          _eventsAt(startBox.shift(delta), surface, snapping: snapping),
          const [],
        );
      case 'Badge':
        if (startBox == null) return (null, const []);
        var box = OverlayVisorLayout.onScreen(startBox.shift(delta), surface);
        var guides = const <OverlayVisorGuide>[];
        if (snapping) {
          (box, guides) = OverlayVisorLayout.snap(
            box,
            OverlayVisorLayout.others('badge', items, visor, surface),
            surface,
          );
        }
        final (x, y) = OverlayVisorLayout.badgeAt(box, surface);
        return (MenuHudVisorBadge(x, y), guides);
      case 'Notice':
        // the rally box follows the pointer and docks on release (rallyDrop)
        return (null, const []);
      case 'Members' || 'Chat':
        if (start == null) return (null, const []);
        final (next, guides) = OverlayVisorLayout.drag(
          start,
          delta,
          items,
          visor,
          surface,
          snapping: snapping,
        );
        return (MenuHudVisorItem(next), guides);
    }
    return (null, const []);
  }

  /// The rally block while dragged [dy] up or down from [start] (11-18 user:
  /// "框跟着手上下走，松手吸过去"): it follows the pointer, kept on screen.
  static Rect rallyDragged(
    OverlayWorkspaceLayoutItem start,
    OverlayWorkspaceSettings visor,
    Size surface,
    double dy,
  ) => OverlayVisorLayout.rallyFollow(
    OverlayVisorLayout.rallyBox(start, visor, surface),
    dy,
    surface,
  );

  /// On release: the rally docks at the spot nearer to where it was let go;
  /// null when that is where it already is.
  static MenuHudVisorEdit? rallyDrop(
    OverlayWorkspaceLayoutItem start,
    OverlayWorkspaceSettings visor,
    Size surface,
    double dy,
  ) {
    final box = rallyDragged(start, visor, surface, dy);
    final next = OverlayVisorLayout.dockRally(
      start,
      box.center.dy,
      surface,
      split: OverlayVisorLayout.rallySplit(start, visor, surface),
    );
    return next.verticalAnchor == start.verticalAnchor && next.y == start.y
        ? null
        : MenuHudVisorItem(next);
  }

  /// Arrow keys: blocks move without snapping; the rally docks up or down;
  /// the events change height; the badge moves.
  static MenuHudVisorEdit? nudge({
    required String key,
    required Map<String, Rect> rects,
    required Offset delta,
    required List<OverlayWorkspaceLayoutItem> items,
    required OverlayWorkspaceSettings visor,
    required Size surface,
  }) {
    final item = items.where((i) => i.key == key).firstOrNull;
    switch (key) {
      case 'Events':
        final rect = rects['Events'];
        if (rect == null || delta == Offset.zero) return null;
        return _eventsAt(rect.shift(delta), surface, snapping: false);
      case 'Badge':
        final rect = rects['Badge'];
        if (rect == null) return null;
        final (x, y) = OverlayVisorLayout.badgeAt(
          OverlayVisorLayout.onScreen(rect.shift(delta), surface),
          surface,
        );
        return MenuHudVisorBadge(x, y);
      case 'Notice':
        if (item == null || item.isLocked || delta.dy == 0) return null;
        return MenuHudVisorItem(
          OverlayVisorLayout.dockRally(
            item,
            delta.dy < 0 ? 0 : surface.height,
            surface,
          ),
        );
      case 'Members' || 'Chat':
        if (item == null || item.isLocked) return null;
        final (next, _) = OverlayVisorLayout.drag(
          item,
          delta,
          items,
          visor,
          surface,
          snapping: false,
        );
        return MenuHudVisorItem(next);
    }
    return null;
  }

  /// The events at [box] (kept on screen), saved as the visor reads them: the
  /// half its centre is in is the side; near that screen edge (and
  /// [snapping]) it goes back against the edge, saved as "at the edge".
  static MenuHudVisorEvents _eventsAt(
    Rect box,
    Size surface, {
    required bool snapping,
  }) {
    final unit = 1080 / surface.height;
    final margin = OverlayVisorLayout.screenMargin / unit;
    final left = box.left
        .clamp(margin, math.max(margin, surface.width - margin - box.width))
        .toDouble();
    final top = box.top
        .clamp(0.0, math.max(0.0, surface.height - box.height))
        .toDouble();
    final placed = Rect.fromLTWH(left, top, box.width, box.height);
    final right = placed.center.dx > surface.width / 2;
    final edge = OverlayVisorLayout.edge / unit;
    final edgeLeft = right ? surface.width - edge - box.width : edge;
    final atEdge =
        snapping &&
        (placed.left - edgeLeft).abs() <= OverlayVisorLayout.snapDistance;
    return MenuHudVisorEvents(
      right,
      OverlayVisorLayout.eventYFromTop(top, surface, right: right && atEdge),
      atEdge
          ? -1
          : ((right ? placed.right : placed.left) / surface.width)
                .clamp(0.0, 1.0)
                .toDouble(),
    );
  }
}
