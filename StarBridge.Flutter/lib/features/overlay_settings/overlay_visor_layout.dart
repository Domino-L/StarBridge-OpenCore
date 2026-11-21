import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'overlay_visor_arrange.dart';
import 'overlay_members_size.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_rules.dart';

/// A snap guide: a vertical (x) or horizontal (y) line in surface pixels.
typedef OverlayVisorGuide = ({bool vertical, double at});

/// The visor projection in the layout editor: the Dart side of StarBridge.Core
/// OverlayVisorLayout / OverlayVisorPlacement. Since 11-06 positions are free
/// (user: "可以像现在一样自由调整吗"; size stays the S/M/L setting): a block
/// stops where it is dropped, snapping only helps. A module still at a shipped
/// position was never moved and shows the visor default.
///
/// Units: the editor works in surface pixels; the visor's own numbers are in
/// 1080-high layout units (unit = 1080 / surface height).
abstract final class OverlayVisorLayout {
  static const double edge = 56;
  static const double gap = 18;
  static const double screenMargin = 8;
  static const double snapDistance = 12;

  /// Visor blocks backed by a layout module. Events keep their own side and
  /// height in the event settings; the rally stays at the top centre (its
  /// module docks to the screen edge); the DM badge stays above the key hints.
  static const keys = {'Members', 'Chat'};

  // A hidden appearance is shown as the visor (0.7.3 overlay v2).
  static bool active(OverlayWorkspaceSettings settings) =>
      overlayWorkspaceShownSkin(settings) == 'Visor';

  /// Blocks the visor sizes itself (the S/M/L setting): only their position
  /// is free (11-06 "先只自由位置尝试一下").
  static bool fixedSize(OverlayWorkspaceSettings settings, String key) =>
      active(settings) && (keys.contains(key) || key == 'Notice');

  /// The visor shows the fleet overview (online, in game, same server, your
  /// server) at the top of the members block, never as a block of its own.
  static bool mergedIntoMembers(
    OverlayWorkspaceSettings settings,
    String key,
  ) => active(settings) && key == 'Squads';

  static double sizeFactor(OverlayWorkspaceSettings settings) =>
      switch (settings['visorSize']) {
        'Small' => 0.86,
        'Large' => 1.36,
        _ => 1.0,
      };

  /// The block's outline in the editor, in layout units: the visor block
  /// (480 x 0.53 wide; members 11 rows) times the size setting, never smaller
  /// than the module editor's own minimum (240 x 140, chat 240 x 104), so the
  /// preview fits. The saved corner decides where the visor draws.
  static Size boxSize(String key, double factor) => Size(
    math.max(240, 254.4 * factor),
    key == 'Chat' ? 104 : math.max(140, 350 * factor),
  );

  /// The visor design unit in layout units at medium size (the visor's Compact).
  static const double designUnit = 0.53;

  /// The members box in layout units (11-07): its width and height settings
  /// (a maximum while adaptive, the fixed size otherwise) times the size
  /// setting, as the visor places the members.
  static Size membersBoxSize(OverlayWorkspaceSettings settings) {
    final factor = sizeFactor(settings);
    return Size(
      membersWidth(settings) * designUnit * factor,
      membersHeight(settings) * designUnit * factor,
    );
  }

  static double membersWidth(OverlayWorkspaceSettings settings) =>
      ((settings['visorMembersWidth'] as num?)?.toDouble() ?? 364)
          .clamp(
            OverlayMembersSize.width.minimum,
            OverlayMembersSize.width.maximum,
          )
          .toDouble();

  static double membersHeight(OverlayWorkspaceSettings settings) =>
      ((settings['visorMembersHeight'] as num?)?.toDouble() ?? 394)
          .clamp(
            OverlayMembersSize.height.minimum,
            OverlayMembersSize.height.maximum,
          )
          .toDouble();

  /// The members box shows its resize corner only while members are shown.
  static bool membersResizable(OverlayWorkspaceSettings settings) =>
      active(settings) && settings['showMembers'] == true;

  /// How the members box is anchored (as [_ownBox] places it): its screen-edge
  /// side, and vertically top (-1), centred on its default slot (0) or bottom
  /// (1). The box grows away from that anchor.
  static (bool, int) membersAnchor(
    OverlayWorkspaceLayoutItem item,
    Size surface,
  ) {
    if (unmoved(item, surface)) return (true, 0);
    final rect = resolve(item, surface);
    final right = switch (item.horizontalAnchor) {
      'Right' => true,
      'Left' => false,
      _ => rect.center.dx > surface.width / 2,
    };
    final vertical = switch (item.verticalAnchor) {
      'Bottom' => 1,
      'Top' => -1,
      _ => rect.center.dy > surface.height / 2 ? 1 : -1,
    };
    return (right, vertical);
  }

  /// A drag on the members box's resize corner, in surface pixels: the new
  /// width and height settings (visor design units, whole numbers, in range).
  /// The corner faces away from the [anchor] (taken when the drag starts), so
  /// dragging it outward makes the box bigger; a box centred on its slot grows
  /// away from the opposite edge; callers also save the new position.
  static (double, double) resizeMembers(
    OverlayWorkspaceSettings settings,
    (bool, int) anchor,
    Offset delta,
    Size surface,
  ) {
    final perDesignUnit = designUnit * sizeFactor(settings) / _unit(surface);
    final (right, vertical) = anchor;
    final width =
        membersWidth(settings) + (right ? -delta.dx : delta.dx) / perDesignUnit;
    final dy = switch (vertical) {
      1 => -delta.dy,
      0 => delta.dy,
      _ => delta.dy,
    };
    final height = membersHeight(settings) + dy / perDesignUnit;
    return (
      width
          .clamp(
            OverlayMembersSize.width.minimum,
            OverlayMembersSize.width.maximum,
          )
          .roundToDouble(),
      height
          .clamp(
            OverlayMembersSize.height.minimum,
            OverlayMembersSize.height.maximum,
          )
          .roundToDouble(),
    );
  }

  /// Default slots, in layout units (as OverlayVisorLayout.Place).
  static Offset place(String slot, Size size, double layoutWidth) {
    final w = size.width, h = size.height;
    return switch (slot) {
      'L-top' => const Offset(edge, 132),
      // m102 (11-18 "往下延长"): the middle slots keep their top, grow down
      'L-mid' => const Offset(edge, leftMidTop),
      'L-bottom' => Offset(edge, math.min(877 - h, math.max(668, 772 - h / 2))),
      'R-top' => Offset(layoutWidth - edge - w, 150),
      'R-bottom' => Offset(layoutWidth - edge - w, 790 - h),
      'T-left' => Offset(math.max(384, layoutWidth / 2 - 470 - w / 2), 250),
      'T-right' => Offset(
        math.min(
          layoutWidth / 2 + 470 - w / 2,
          layoutWidth - edge - w - 24 - w,
        ),
        250,
      ),
      'B-mid' => Offset(layoutWidth / 2 - w / 2, 846 - h),
      _ => Offset(layoutWidth - edge - w, rightMidTop),
    };
  }

  /// The top of the middle slots (StarBridge.Core OverlayVisorLayout
  /// LeftMidTop / RightMidTop): where the members' default 8 rows at medium
  /// sat centred on 520 and 490.
  static const leftMidTop = 520 - 394 * 0.53 / 2,
      rightMidTop = 490 - 394 * 0.53 / 2;

  /// The game's own HUD, measured from the user's screenshots (layout units).
  static List<Rect> gameHud(double layoutWidth) {
    final r = layoutWidth - 1920, c = r / 2;
    return [
      const Rect.fromLTWH(20, 0, 340, 390),
      Rect.fromLTWH(660 + c, 15, 600, 60),
      Rect.fromLTWH(1700 + r, 35, 185, 100),
      const Rect.fromLTWH(60, 420, 380, 230),
      const Rect.fromLTWH(0, 340, 45, 390),
      Rect.fromLTWH(layoutWidth - 45, 320, 45, 420),
      Rect.fromLTWH(570 + c, 440, 600, 320),
      Rect.fromLTWH(830 + c, 860, 260, 80),
      const Rect.fromLTWH(35, 895, 260, 150),
      Rect.fromLTWH(1660 + r, 845, 225, 200),
    ];
  }

  static double _unit(Size surface) => 1080 / surface.height;

  /// The 1080-high layout space the visor resolves modules in.
  static Size layoutSize(Size surface) =>
      Size(surface.width * _unit(surface), 1080);

  /// A module's rectangle as the visor resolves it (StarBridge.Core
  /// ResolveItemRect in the 1080-high layout space), in surface pixels: the
  /// module size limits are layout units, so a small window or editor canvas
  /// gives the same answer as the game (review CX-VISOR-EDITOR-B88-R1).
  static Rect resolve(OverlayWorkspaceLayoutItem item, Size surface) {
    final unit = _unit(surface);
    final r = OverlayWorkspaceLayoutGeometry.resolve(
      item,
      surfaceSize: layoutSize(surface),
    );
    return Rect.fromLTRB(
      r.left / unit,
      r.top / unit,
      r.right / unit,
      r.bottom / unit,
    );
  }

  /// A module's default position. On the visor the rally's dock is its
  /// only position, so it goes back to the top (review CX-VISOR-EDITOR-B88-R1:
  /// the shared reset keeps the anchor, and a bottom rally stayed down).
  static OverlayWorkspaceLayoutItem resetPosition(
    OverlayWorkspaceLayoutItem item,
    String presetId,
    OverlayWorkspaceSettings? settings,
  ) {
    final reset = OverlayWorkspaceLayoutGeometry.resetPosition(item, presetId);
    return settings != null && active(settings) && item.key == 'Notice'
        ? reset.copyWith(verticalAnchor: 'Top', y: 0)
        : reset;
  }

  /// Still within 2% of a position the client shipped: never moved.
  static bool unmoved(OverlayWorkspaceLayoutItem item, Size surface) {
    final centre = resolve(item, surface).center;
    for (final preset in const ['default', 'compact', 'command']) {
      final shipped = resolve(
        OverlayWorkspaceLayoutGeometry.resetPosition(item, preset),
        surface,
      ).center;
      if ((shipped.dx - centre.dx).abs() <= 0.02 * surface.width &&
          (shipped.dy - centre.dy).abs() <= 0.02 * surface.height) {
        return true;
      }
    }
    return false;
  }

  /// Where the visor draws this module's block, in surface pixels. With the
  /// whole [layout] the block is placed as the visor arranges the screen (see
  /// [arrange]); without it, at its own spot.
  static Rect boxOf(
    OverlayWorkspaceLayoutItem item,
    OverlayWorkspaceSettings settings,
    Size surface, [
    List<OverlayWorkspaceLayoutItem>? layout,
  ]) =>
      (layout == null ? null : arrange(layout, settings, surface)[item.key]) ??
      _ownBox(item, settings, surface);

  /// Every shown visor block as the visor arranges them in game
  /// (StarBridge.Core OverlayVisorLayout.Arrange), in layout units (1080
  /// high), returned in surface pixels (review R5):
  /// 1. each group has a default slot or the corner the user moved it to; the
  ///    events, while on, are a group of their three-line height, at the
  ///    right top or at the saved side and height (Y x 990);
  /// 2. default slots stack in their side column a gap apart, pulled up when
  ///    the column runs past its end;
  /// 3. every group stays on screen;
  /// 4. a group that overlaps one placed before it moves up or down just clear
  ///    of it, the shorter way; moved groups go first, then members, events,
  ///    chat.
  static Map<String, Rect> arrange(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) => {
    for (final entry in OverlayVisorArrange.all(
      layout,
      settings,
      surface,
    ).entries)
      if (entry.key != 'Events') entry.key: entry.value,
  };

  /// Where the events sit across (11-12): their screen-edge side's x as a
  /// screen fraction, or null at that edge (the saved -1, or a Host from
  /// before).
  static double? eventsX(OverlayWorkspaceSettings settings) =>
      switch (settings['visorEventsX']) {
        final num x when x >= 0 && x <= 1 => x.toDouble(),
        _ => null,
      };

  /// Where the visor shows the events while they are on (surface pixels): the
  /// events group's box after [arrange]'s steps (review R6: the editor's event
  /// preview sits there), or null when the events are off.
  static Rect? eventsPlacement(
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) => OverlayVisorArrange.all(layout, settings, surface)['Events'];

  /// A saved event height from the top of the event preview (surface
  /// pixels), as the visor reads it: the top in layout units over 990.
  /// On the right, a height within 0.02 of the shipped one reads as "never
  /// moved" (the right top); a drag there saves just outside that band, so the
  /// events stay (a few pixels off) instead of jumping (review R7).
  static double eventYFromTop(double top, Size surface, {bool right = true}) {
    final y = (top * _unit(surface) / (1080 - eventPlacementHeight)).clamp(
      0.0,
      1.0,
    );
    if (!right || (y - 0.34).abs() > 0.02) return y;
    // three decimals, so the value survives the settings' "0.###" saving and
    // stays outside the band after a reload (review R8)
    return y < 0.34 ? 0.319 : 0.361;
  }

  /// The events and chat boxes in layout units (11-07 "2放"): their width
  /// setting (a maximum while adaptive, the fixed width otherwise) and the
  /// height of their most lines (the existing line counts), as the visor
  /// places them (OverlayVisorDraw.EventsBoxHeight / ChatBoxHeight).
  static Size eventsBoxSize(OverlayWorkspaceSettings settings) {
    final factor = sizeFactor(settings);
    final lines =
        ((settings['eventNotificationMaxVisibleCount'] as num?)?.round() ?? 3)
            .clamp(1, 5);
    return Size(
      _width(settings, 'visorEventsWidth') * designUnit * factor,
      (22 + lines * 70) * designUnit * factor,
    );
  }

  static Size chatBoxSize(OverlayWorkspaceSettings settings) {
    final factor = sizeFactor(settings);
    final lines = ((settings['chatMaxVisibleCount'] as num?)?.round() ?? 4)
        .clamp(1, 8);
    // at least the chat preview's height, as the visor (OverlayVisorLayout.ChatMinHeight)
    return Size(
      _width(settings, 'visorChatWidth') * designUnit * factor,
      math.max(chatMinHeight, (22 + lines * 28) * designUnit * factor),
    );
  }

  /// The least height the chat is placed by (layout units).
  static const double chatMinHeight = 104;

  static double _width(OverlayWorkspaceSettings settings, String field) =>
      ((settings[field] as num?)?.toDouble() ?? 364).clamp(220, 480).toDouble();

  /// The height of the event preview the saved event position is measured in.
  static const double eventPlacementHeight = 90;

  static Rect _ownBox(
    OverlayWorkspaceLayoutItem item,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    final unit = _unit(surface);
    final size =
        (item.key == 'Members'
            ? membersBoxSize(settings)
            : chatBoxSize(settings)) /
        unit;
    if (unmoved(item, surface)) {
      final slot = item.key == 'Members' ? 'R-mid' : 'L-bottom';
      final at = place(slot, size * unit, surface.width * unit) / unit;
      return at & size;
    }
    final rect = resolve(item, surface);
    final right = switch (item.horizontalAnchor) {
      'Right' => true,
      'Left' => false,
      _ => rect.center.dx > surface.width / 2,
    };
    final bottom = switch (item.verticalAnchor) {
      'Bottom' => true,
      'Top' => false,
      _ => rect.center.dy > surface.height / 2,
    };
    final left = right ? rect.right - size.width : rect.left;
    final top = bottom ? rect.bottom - size.height : rect.top;
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  /// Saves a block at [box]: the module anchored to the screen half the block
  /// is in, its anchored corner exactly on the block's corner (module size
  /// limits can change the module's size, never that corner).
  static OverlayWorkspaceLayoutItem save(
    OverlayWorkspaceLayoutItem item,
    Rect box,
    Size surface, {
    bool? rightAnchor,
  }) {
    final right = rightAnchor ?? box.center.dx > surface.width / 2;
    final bottom = box.center.dy > surface.height / 2;
    // in the visor's layout space, as it reads the module back (review R1)
    final unit = _unit(surface);
    final next = OverlayWorkspaceLayoutGeometry.apply(
      item,
      Rect.fromLTRB(
        box.left * unit,
        box.top * unit,
        box.right * unit,
        box.bottom * unit,
      ),
      surfaceSize: layoutSize(surface),
    );
    final x = right ? box.right / surface.width - next.width : next.x;
    final y = bottom ? box.bottom / surface.height - next.height : next.y;
    return next.copyWith(
      x: x.clamp(0.0, math.max(0.0, 1 - next.width)).toDouble(),
      y: y.clamp(0.0, math.max(0.0, 1 - next.height)).toDouble(),
      horizontalAnchor: right ? 'Right' : 'Left',
      verticalAnchor: bottom ? 'Bottom' : 'Top',
    );
  }

  /// Keeps [box] on screen, [screenMargin] from the edge.
  static Rect onScreen(Rect box, Size surface) {
    final m = screenMargin / _unit(surface);
    return Rect.fromLTWH(
      box.left.clamp(m, math.max(m, surface.width - m - box.width)).toDouble(),
      box.top.clamp(m, math.max(m, surface.height - m - box.height)).toDouble(),
      box.width,
      box.height,
    );
  }

  /// Snaps an edge of [box] that is near the screen edge (or the visor's edge
  /// margin), another block (aligned, or [gap] apart) or the game's HUD edge.
  /// Only that one edge moves; returns the guides to draw.
  static (Rect, List<OverlayVisorGuide>) snap(
    Rect box,
    List<Rect> others,
    Size surface,
  ) {
    final unit = _unit(surface);
    final threshold = snapDistance / unit, g = gap / unit, e = edge / unit;
    final hud = gameHud(surface.width * unit).map(
      (z) => Rect.fromLTRB(
        z.left / unit,
        z.top / unit,
        z.right / unit,
        z.bottom / unit,
      ),
    );
    final xs = <double>[0, e, surface.width - e, surface.width];
    final ys = <double>[0, e, surface.height - e, surface.height];
    for (final o in [...others, ...hud]) {
      xs.addAll([o.left, o.right, o.left - g, o.right + g]);
      ys.addAll([o.top, o.bottom, o.top - g, o.bottom + g]);
    }
    // The nearest line within reach of either edge: (shift, line), or null.
    (double, double)? best(double a, double b, List<double> lines) {
      (double, double)? found;
      for (final l in lines) {
        for (final edgeAt in [a, b]) {
          final d = l - edgeAt;
          if (d.abs() <= threshold &&
              (found == null || d.abs() < found.$1.abs())) {
            found = (d, l);
          }
        }
      }
      return found;
    }

    final guides = <OverlayVisorGuide>[];
    var result = box;
    if (best(box.left, box.right, xs) case (final dx, final line)) {
      result = result.shift(Offset(dx, 0));
      guides.add((vertical: true, at: line));
    }
    if (best(box.top, box.bottom, ys) case (final dy, final line)) {
      result = result.shift(Offset(0, dy));
      guides.add((vertical: false, at: line));
    }
    return (onScreen(result, surface), guides);
  }

  /// A dropped block that overlaps another moves up or down just clear of it,
  /// the shorter way that stays on screen and hits nothing (as the visor does
  /// at runtime); if neither fits, it stays.
  static Rect clear(Rect box, List<Rect> others, Size surface) {
    if (!others.any(box.overlaps)) return box;
    final unit = _unit(surface);
    final g = gap / unit, m = screenMargin / unit;
    final options =
        others
            .expand((o) => [o.top - g - box.height, o.bottom + g])
            .where((y) => y >= m && y + box.height <= surface.height - m)
            .where(
              (y) => !others.any(
                Rect.fromLTWH(box.left, y, box.width, box.height).overlaps,
              ),
            )
            .toList()
          ..sort((a, b) => (a - box.top).abs().compareTo((b - box.top).abs()));
    return options.isEmpty
        ? box
        : Rect.fromLTWH(box.left, options.first, box.width, box.height);
  }

  /// The event height to show in the editor. Events never moved (right side,
  /// shipped height) sit at the top of the visor's right column, y = 150.
  static double eventDisplayY(OverlayWorkspaceSettings settings, Size surface) {
    final y = (settings['eventNotificationY'] as num?)?.toDouble() ?? 0.34;
    if (!active(settings) ||
        settings['eventNotificationSide'] == 'Left' ||
        (y - 0.34).abs() > 0.02) {
      return y;
    }
    final available =
        surface.height -
        OverlayWorkspaceLayoutGeometry.singleEventNotificationPlacementHeight;
    return (150 / _unit(surface) / math.max(1, available)).clamp(0.0, 1.0);
  }

  /// The rally band (11-06 "召集应该可以上下换位 但是固定两个预设位置"): top
  /// centre, or bottom centre just above the game's speed readout and below
  /// the crosshair area. The notice module's dock (top or bottom) chooses.
  static Rect rallyBox(
    OverlayWorkspaceLayoutItem notice,
    OverlayWorkspaceSettings settings,
    Size surface, {
    bool? bottom,
  }) {
    final unit = _unit(surface);
    final g = 0.53 * sizeFactor(settings);
    final w = 1100 * g, h = 128 * g;
    final atBottom = bottom ?? notice.verticalAnchor == 'Bottom';
    final top = atBottom ? 858 - h : 84 - 8 * g;
    return Rect.fromLTWH(
      (surface.width * unit / 2 - w / 2) / unit,
      top / unit,
      w / unit,
      h / unit,
    );
  }

  /// The notice module docked where the rally goes: the nearer of the two
  /// spots to [centreY] (surface pixels).
  static OverlayWorkspaceLayoutItem dockRally(
    OverlayWorkspaceLayoutItem notice,
    double centreY,
    Size surface, {
    double? split,
  }) {
    final bottom = centreY > (split ?? surface.height / 2);
    return notice.copyWith(
      verticalAnchor: bottom ? 'Bottom' : 'Top',
      y: bottom ? math.max(0.0, 1 - notice.height) : 0.0,
    );
  }

  /// Where a dragged rally block goes to the other spot: halfway between the
  /// two spots' centres, so it docks at the nearer one ("松手吸到近的那个";
  /// review CX-OVERLAY-M102-R1 P2-4: the screen's middle was off by ~70).
  static double rallySplit(
    OverlayWorkspaceLayoutItem notice,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) =>
      (rallyBox(notice, settings, surface, bottom: false).center.dy +
          rallyBox(notice, settings, surface, bottom: true).center.dy) /
      2;

  /// The rally block while dragged (11-18 user: "框跟着手上下走，松手吸过去"):
  /// from its spot [docked], up and down only by [dy] and kept on screen. It
  /// docks at the nearer spot on release ([dockRally] by its centre).
  static Rect rallyFollow(Rect docked, double dy, Size surface) =>
      Rect.fromLTWH(
        docked.left,
        (docked.top + dy)
            .clamp(0.0, math.max(0.0, surface.height - docked.height))
            .toDouble(),
        docked.width,
        docked.height,
      );

  /// The DM badge's outline in the editor (layout units): big enough to grab;
  /// in game it is as wide as its text.
  static Size badgeSize(double factor) =>
      Size(math.max(120, 140 * factor), math.max(24, 16 * factor));

  /// Where the DM badge sits (11-06 "角标自由"), in surface pixels. Unset
  /// (-1) is the default spot above the game's key hints; otherwise the saved
  /// fractions are its screen-edge side (right edge on the right half, else
  /// left edge) and its top, as StarBridge.Core OverlayVisorPlacement.Badge.
  static Rect badgeBox(OverlayWorkspaceSettings settings, Size surface) {
    final unit = _unit(surface);
    final factor = sizeFactor(settings);
    final size = badgeSize(factor) / unit;
    final x = (settings['visorBadgeX'] as num?)?.toDouble() ?? -1;
    final y = (settings['visorBadgeY'] as num?)?.toDouble() ?? -1;
    if (x < 0 || x > 1 || y < 0 || y > 1) {
      final top = (845 - 30 * 0.53 * factor - 14) / unit;
      return Rect.fromLTWH(
        surface.width - edge / unit - size.width,
        top,
        size.width,
        size.height,
      );
    }
    final anchor = x * surface.width;
    final left = x >= 0.5 ? anchor - size.width : anchor;
    return Rect.fromLTWH(left, y * surface.height, size.width, size.height);
  }

  /// The badge position to save for [box]: (x, y) screen fractions.
  static (double, double) badgeAt(Rect box, Size surface) {
    final right = box.center.dx > surface.width / 2;
    return (
      ((right ? box.right : box.left) / surface.width).clamp(0.0, 1.0),
      (box.top / surface.height).clamp(0.0, 1.0),
    );
  }

  /// The other visor blocks, in surface pixels (the DM badge is gone, 11-13).
  static List<Rect> others(
    String key,
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) => [
    ...arrange(
      [
        for (final item in layout)
          if (item.key != key) item,
      ],
      settings,
      surface,
    ).values,
  ];

  /// One drag step: the block from [start] moved by [delta] (surface pixels),
  /// kept on screen and, unless [snapping] is off (Alt held), snapped.
  static (OverlayWorkspaceLayoutItem, List<OverlayVisorGuide>) drag(
    OverlayWorkspaceLayoutItem start,
    Offset delta,
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface, {
    required bool snapping,
  }) {
    final moved = onScreen(
      // from where the block was shown when the drag began
      boxOf(start, settings, surface, [
        for (final i in layout) i.key == start.key ? start : i,
      ]).shift(delta),
      surface,
    );
    final (box, guides) = snapping
        ? snap(moved, others(start.key, layout, settings, surface), surface)
        : (moved, const <OverlayVisorGuide>[]);
    return (save(start, box, surface), guides);
  }

  /// On release: a block left on top of another moves just clear of it.
  /// Null when nothing changes.
  static OverlayWorkspaceLayoutItem? drop(
    OverlayWorkspaceLayoutItem item,
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    final box = boxOf(item, settings, surface);
    final cleared = clear(
      box,
      others(item.key, layout, settings, surface),
      surface,
    );
    return cleared == box
        ? null
        : save(
            item,
            cleared,
            surface,
            rightAnchor: item.key == 'Members'
                ? membersAnchor(item, surface).$1
                : null,
          );
  }

  /// True when the block covers part of the game's own HUD (shown in red).
  static bool coversGameHud(Rect box, Size surface) {
    final unit = _unit(surface);
    final inUnits = Rect.fromLTRB(
      box.left * unit,
      box.top * unit,
      box.right * unit,
      box.bottom * unit,
    );
    return gameHud(surface.width * unit).any(inUnits.overlaps);
  }
}
