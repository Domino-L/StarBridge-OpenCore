import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../app/localization/app_strings.dart';
import 'overlay_members_size.dart';
import 'overlay_members_resize_handles.dart';
import 'overlay_visor_layout.dart';
import 'overlay_visor_overlap_warning.dart';
import 'overlay_visor_projection.dart';
import 'overlay_workspace_models.dart';

export 'overlay_visor_layout.dart' show OverlayVisorLayout;

/// The layout editor's visor gestures (11-06: free positions, size stays S/M/L).
final class OverlayVisorEditing {
  /// Snap guides of the drag in progress.
  List<OverlayVisorGuide> guides = const [];

  static bool handles(OverlayWorkspaceSettings settings, String key) =>
      OverlayVisorLayout.fixedSize(settings, key);

  /// Where the visor draws the block, or null for an ordinary module.
  static Rect? boxOrNull(
    OverlayWorkspaceLayoutItem item,
    OverlayWorkspaceSettings settings,
    Size surface, [
    List<OverlayWorkspaceLayoutItem>? layout,
  ]) => !handles(settings, item.key)
      ? null
      : item.key == 'Notice'
      ? OverlayVisorLayout.rallyBox(item, settings, surface)
      : OverlayVisorLayout.boxOf(item, settings, surface, layout);

  /// The rally's drag so far (surface pixels, up and down) while it is
  /// dragged; null otherwise.
  double? rallyDy;

  /// Where [item] shows now: [boxOrNull], except the rally while dragged,
  /// which follows the pointer up and down (11-18 "框跟着手上下走").
  Rect? shown(
    OverlayWorkspaceLayoutItem item,
    OverlayWorkspaceSettings settings,
    Size surface, [
    List<OverlayWorkspaceLayoutItem>? layout,
  ]) {
    final box = boxOrNull(item, settings, surface, layout);
    final dy = rallyDy;
    return box == null || dy == null || item.key != 'Notice'
        ? box
        : OverlayVisorLayout.rallyFollow(box, dy, surface);
  }

  /// A drag step for a visor block (holding Alt turns snapping off); null for
  /// an ordinary module. The rally only follows the pointer ([rallyDy]) and
  /// docks on release ([end]), so it answers its start unchanged.
  OverlayWorkspaceLayoutItem? move(
    OverlayWorkspaceLayoutItem start,
    Offset delta,
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    if (!handles(settings, start.key)) return null;
    if (start.key == 'Notice') {
      guides = const [];
      rallyDy = delta.dy;
      return start;
    }
    final (next, snapped) = OverlayVisorLayout.drag(
      start,
      delta,
      layout,
      settings,
      surface,
      snapping: !HardwareKeyboard.instance.isAltPressed,
    );
    guides = snapped;
    return next;
  }

  /// On release: clears the guides; a visor block left on another moves just
  /// clear of it; the rally docks at the spot nearer to where it was let go.
  /// Null when nothing changes.
  OverlayWorkspaceLayoutItem? end(
    String? key,
    List<OverlayWorkspaceLayoutItem> layout,
    OverlayWorkspaceSettings settings,
    Size surface,
  ) {
    guides = const [];
    final dy = rallyDy;
    rallyDy = null;
    final item = layout.where((i) => i.key == key).firstOrNull;
    if (item == null || !handles(settings, item.key)) return null;
    if (item.key != 'Notice') {
      return OverlayVisorLayout.drop(item, layout, settings, surface);
    }
    if (dy == null) return null;
    final box = OverlayVisorLayout.rallyFollow(
      OverlayVisorLayout.rallyBox(item, settings, surface),
      dy,
      surface,
    );
    final next = OverlayVisorLayout.dockRally(
      item,
      box.center.dy,
      surface,
      split: OverlayVisorLayout.rallySplit(item, settings, surface),
    );
    return next.verticalAnchor == item.verticalAnchor && next.y == item.y
        ? null
        : next;
  }
}

/// Visor editing aids drawn over the canvas: snap guides while dragging, a red
/// outline on a block that covers the game's own HUD (a warning only; the block
/// may stay there) and the members box's resize corner (11-07: its width and
/// height settings, a maximum while adaptive or the fixed size otherwise).
class OverlayVisorEditorOverlay extends StatefulWidget {
  const OverlayVisorEditorOverlay({
    required this.layout,
    required this.settings,
    required this.surface,
    required this.guides,
    required this.guideColor,
    required this.warningColor,
    this.onSettingChanged,
    this.onGestureStart,
    this.onGestureEnd,
    this.onMembersResized,
    this.onResizePreview,
    super.key,
  });

  /// Starts a new undo step: each members resize is its own
  /// step, even when the same fields are written again (review
  /// CX-VISOR-EDITOR-B88-R2).
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;
  final ValueChanged<Rect?>? onResizePreview;
  final void Function(int width, int height, OverlayWorkspaceLayoutItem item)?
  onMembersResized;

  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceSettings settings;
  final Size surface;
  final List<OverlayVisorGuide> guides;
  final Color guideColor;

  /// The outline of a block over the game HUD.
  final Color warningColor;

  /// Saves the members box size; null leaves it as it is (locked). The DM
  /// badge is gone (11-13 user: "整个都不要").
  final void Function(String field, Object? value)? onSettingChanged;

  @override
  State<OverlayVisorEditorOverlay> createState() =>
      _OverlayVisorEditorOverlayState();
}

class _OverlayVisorEditorOverlayState extends State<OverlayVisorEditorOverlay> {
  // the members resize in progress: the anchor and settings it started from
  OverlayMembersResize? _resizeStart;
  Offset _resizeDelta = Offset.zero;
  Rect? _dragBox;
  OverlayWorkspaceLayoutItem? _dragItem;
  OverlayWorkspaceSettings? _dragSettings;
  // a leaning members resize: the side it leans to, the flat point grabbed and
  // where it showed (surface pixels); null when the members are drawn flat
  bool? _lean;
  Offset? _grab, _grabShown;
  Offset _pointerStart = Offset.zero;

  /// The flat move for the pointer's move on screen ([_resizeDelta]). Flat:
  /// the move itself. Leaning, the grabbed point stays under the pointer,
  /// worked out from where the pointer is each time: the moving side edge
  /// goes to the pointer's flat x and stops at the width limits; the height
  /// then comes from the pointer's shown height at the grabbed point's actual
  /// flat x, so a corner held at a width limit does not drift up or down
  /// (review CX-HANDLES-PROJ-073-R1 P2), and a top or bottom edge, whose
  /// grabbed point never moves sideways, ignores the pointer's sideways move.
  Offset _flatMove(OverlayMembersResize start) {
    final lean = _lean, grab = _grab, grabShown = _grabShown;
    if (lean == null || grab == null || grabShown == null) return _resizeDelta;
    final pointer = grabShown + _resizeDelta;
    var dx = 0.0;
    if (start.changesWidth) {
      final reached = start.at(Offset(_flat(pointer, lean).dx - grab.dx, 0));
      dx = start.right
          ? reached.box.left - start.box.left
          : reached.box.right - start.box.right;
    }
    if (!start.changesHeight) return Offset(dx, 0);
    final y = OverlayVisorProjection.flatY(
      pointer.dy,
      grab.dx + dx,
      right: lean,
      degrees: OverlayVisorProjection.degrees(widget.settings),
      surface: widget.surface,
      distance: OverlayVisorProjection.distance(widget.settings),
    );
    return Offset(dx, y - grab.dy);
  }

  /// The members' lean while the visor tilts them: the side (true: right),
  /// or null when they are drawn flat (no lean, 0 degrees or another look).
  bool? get _membersLean {
    if (OverlayVisorProjection.degrees(widget.settings) == 0) return null;
    return OverlayVisorProjection.tilts(
      widget.layout,
      widget.settings,
      widget.surface,
    )['Members'];
  }

  Offset _shown(Offset flat, bool right) => OverlayVisorProjection.point(
    flat,
    right: right,
    degrees: OverlayVisorProjection.degrees(widget.settings),
    surface: widget.surface,
    distance: OverlayVisorProjection.distance(widget.settings),
  );

  Offset _flat(Offset shown, bool right) => OverlayVisorProjection.unproject(
    shown,
    right: right,
    degrees: OverlayVisorProjection.degrees(widget.settings),
    surface: widget.surface,
    distance: OverlayVisorProjection.distance(widget.settings),
  );

  /// A global pointer position in surface pixels (the canvas may be zoomed).
  Offset _surfacePointer(Offset globalPosition, Size canvas) {
    final local = (context.findRenderObject()! as RenderBox).globalToLocal(
      globalPosition,
    );
    return Offset(
      local.dx * widget.surface.width / canvas.width,
      local.dy * widget.surface.height / canvas.height,
    );
  }

  void _resize(Offset globalPosition, Size canvas) {
    final start = _resizeStart;
    if (start == null || widget.onMembersResized == null) return;
    // the pointer's move on screen since the press (surface pixels), from its
    // positions, never from deltas (review CX-HANDLES-PROJ-073-R1 P2)
    _resizeDelta = _surfacePointer(globalPosition, canvas) - _pointerStart;
    final next = start.at(_flatMove(start));
    _dragSettings = start.settings
        .withValue('visorMembersWidth', next.width)
        .withValue('visorMembersHeight', next.height);
    _dragItem = next.item;
    setState(() => _dragBox = next.box);
    widget.onResizePreview?.call(next.box);
    widget.onMembersResized!(next.width, next.height, next.item);
  }

  void _endResize() {
    final item = _dragItem;
    final settings = _dragSettings;
    if (item != null && settings != null) {
      final dropped = OverlayVisorLayout.drop(
        item,
        widget.layout,
        settings,
        widget.surface,
      );
      if (dropped != null) {
        widget.onMembersResized?.call(
          OverlayVisorLayout.membersWidth(settings).round(),
          OverlayVisorLayout.membersHeight(settings).round(),
          dropped,
        );
      }
    }
    setState(() {
      _resizeStart = null;
      _dragBox = null;
      _dragItem = null;
      _dragSettings = null;
      _lean = null;
      _grab = null;
      _grabShown = null;
    });
    widget.onGestureEnd?.call();
    widget.onResizePreview?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface;
    final members = widget.layout
        .where((item) => item.key == 'Members')
        .firstOrNull;
    final membersBox =
        members == null || !OverlayVisorLayout.membersResizable(widget.settings)
        ? null
        : OverlayVisorLayout.boxOf(
            members,
            widget.settings,
            surface,
            widget.layout,
          );
    // a resize keeps the lean it began with
    final lean = _resizeStart != null ? _lean : _membersLean;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = constraints.biggest;
        final sx = canvas.width / surface.width;
        final sy = canvas.height / surface.height;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const Key('overlay-visor-editor-overlay'),
                  painter: _Painter(
                    warnings: [
                      for (final item in widget.layout)
                        if (OverlayVisorLayout.keys.contains(item.key))
                          if (OverlayVisorLayout.boxOf(
                                item,
                                widget.settings,
                                surface,
                                widget.layout,
                              )
                              case final box
                              when OverlayVisorLayout.coversGameHud(
                                box,
                                surface,
                              ))
                            box,
                    ],
                    surface: surface,
                    guides: widget.guides,
                    guideColor: widget.guideColor,
                    warningColor: widget.warningColor,
                  ),
                ),
              ),
            ),
            // the events and the members would overlap (11-18): warn only
            ?OverlayVisorOverlapWarning.forLayout(
              layout: widget.layout,
              settings: widget.settings,
              surface: surface,
              scale: Offset(sx, sy),
            ),
            if (members != null &&
                !members.isLocked &&
                membersBox != null &&
                widget.onMembersResized != null)
              ...overlayMembersResizeHandles(
                box: _dragBox ?? membersBox,
                sx: sx,
                sy: sy,
                right:
                    _resizeStart?.right ??
                    OverlayVisorLayout.membersAnchor(members, surface).$1,
                color: widget.guideColor,
                background: context.tokens.colors.scrim,
                project: lean == null ? null : (p) => _shown(p, lean),
                onStart: (handle, globalPosition) {
                  widget.onGestureStart?.call();
                  final pointer = _surfacePointer(globalPosition, canvas);
                  setState(() {
                    _pointerStart = pointer;
                    _resizeStart = OverlayMembersResize(
                      members,
                      widget.settings,
                      membersBox,
                      surface,
                      handle,
                    );
                    _resizeDelta = Offset.zero;
                    _dragBox = membersBox;
                    _lean = lean;
                    _grabShown = lean == null ? null : pointer;
                    _grab = lean == null ? null : _flat(pointer, lean);
                  });
                },
                onUpdate: (position) => _resize(position, canvas),
                onEnd: _endResize,
              ),
            if (_resizeStart != null &&
                _dragBox != null &&
                widget.onMembersResized != null &&
                members?.isLocked == false)
              _sizeLabel(_shownBox(_dragBox!, lean), sx, sy, canvas),
          ],
        );
      },
    );
  }
}

extension on _OverlayVisorEditorOverlayState {
  /// Where the box shows (surface pixels): the bounds of its shown corners
  /// while the members lean, the flat box otherwise.
  Rect _shownBox(Rect box, bool? lean) {
    if (lean == null) return box;
    final corners = [
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
    ].map((p) => _shown(p, lean));
    double least(double Function(Offset) of) =>
        corners.map(of).reduce((a, b) => a < b ? a : b);
    double most(double Function(Offset) of) =>
        corners.map(of).reduce((a, b) => a > b ? a : b);
    return Rect.fromLTRB(
      least((p) => p.dx),
      least((p) => p.dy),
      most((p) => p.dx),
      most((p) => p.dy),
    );
  }

  Widget _sizeLabel(Rect box, double sx, double sy, Size canvas) {
    final start = _resizeStart!;
    final settings = _dragSettings ?? start.settings;
    final label = AppStrings.of(context)
        .text('overlay.workspace.membersSize.dimensions')
        .replaceAll(
          '{rows}',
          OverlayMembersSize.rows(OverlayVisorLayout.membersHeight(settings))
              .toString(),
        )
        .replaceAll(
          '{width}',
          OverlayVisorLayout.membersWidth(settings).round().toString(),
        );
    final side = start.handle == OverlayMembersHandle.side;
    final x = side
        ? (start.right ? box.left * sx - 190 : box.right * sx + 12)
        : box.center.dx * sx - 90;
    final y = side
        ? box.center.dy * sy - 14
        : start.top
        ? box.top * sy - 34
        : box.bottom * sy + 12;
    return Positioned(
      left: x.clamp(0.0, (canvas.width - 180).clamp(0.0, double.infinity)),
      top: y.clamp(0.0, (canvas.height - 28).clamp(0.0, double.infinity)),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.tokens.colors.scrim,
            border: Border.all(color: widget.guideColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              label,
              key: const Key('overlay-visor-members-size-label'),
              style: TextStyle(color: widget.guideColor, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({
    required this.warnings,
    required this.surface,
    required this.guides,
    required this.guideColor,
    required this.warningColor,
  });

  final List<Rect> warnings;
  final Size surface;
  final List<OverlayVisorGuide> guides;
  final Color guideColor;
  final Color warningColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / surface.width, sy = size.height / surface.height;
    final red = Paint()
      ..color = warningColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final box in warnings) {
      canvas.drawRect(
        Rect.fromLTRB(
          box.left * sx,
          box.top * sy,
          box.right * sx,
          box.bottom * sy,
        ),
        red,
      );
    }
    final line = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    for (final guide in guides) {
      if (guide.vertical) {
        canvas.drawLine(
          Offset(guide.at * sx, 0),
          Offset(guide.at * sx, size.height),
          line,
        );
      } else {
        canvas.drawLine(
          Offset(0, guide.at * sy),
          Offset(size.width, guide.at * sy),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.guides != guides ||
      old.warnings.length != warnings.length ||
      !Iterable<int>.generate(warnings.length)
          .every((i) => old.warnings[i] == warnings[i]) ||
      old.surface != surface;
}
