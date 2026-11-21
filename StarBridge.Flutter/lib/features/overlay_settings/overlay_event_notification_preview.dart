import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'overlay_visor_editor_content.dart';
import 'overlay_visor_layout.dart';
import 'overlay_visor_projection.dart';
import 'overlay_visor_sim_panel.dart';
import 'overlay_visor_sim_scope.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_preview_content.dart';

/// The events block on the layout canvas (moved out of
/// overlay_workspace_fixed_previews.dart for the 800-line gate). With the
/// visor it is the visor's events box, drawn as the editor's simplified panel
/// (11-12 "编辑里还是要用模拟面板"), and it drags anywhere on screen (11-12 user:
/// "我觉得应该允许事件随意调整位置了"): the half it lands in decides the side it
/// opens from and leans to; each event keeps its size ("事件还是要保持原有的单个
/// 事件大小"). Without the visor it is the old one-line preview on a screen
/// edge, dragged up or down.
class OverlayEventNotificationPreview extends StatefulWidget {
  const OverlayEventNotificationPreview({
    required this.settings,
    required this.eventRect,
    this.visorPlacement = false,
    this.tiltRight,
    this.tiltDegrees = 0,
    required this.surfaceSize,
    required this.scaleX,
    required this.scaleY,
    required this.snapPixels,
    required this.smartSnap,
    required this.simulate,
    this.onSelected,
    this.onPlacementChanged,
    this.onGestureStart,
    this.onGestureEnd,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final Rect eventRect;

  /// The visor's events box: free placement, the visor's own units.
  final bool visorPlacement;

  /// The side the visor leans the events to (null: drawn flat) and by how
  /// much: a drag follows the pointer on screen through that camera.
  final bool? tiltRight;
  final double tiltDegrees;
  final Size surfaceSize;
  final double scaleX;
  final double scaleY;
  final double snapPixels;
  final bool smartSnap;
  final bool simulate;
  final ValueChanged<String>? onSelected;

  /// The side, the saved height and, with the visor, where across (a screen
  /// fraction of the side's edge, -1 at that edge).
  final void Function(String side, double normalizedY, {double? x})?
  onPlacementChanged;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  @override
  State<OverlayEventNotificationPreview> createState() =>
      _OverlayEventNotificationPreviewState();
}

class _OverlayEventNotificationPreviewState
    extends State<OverlayEventNotificationPreview> {
  int? _pointer;
  double? _rawTop;
  double? _pointerX;
  double _startTop = 0;
  Rect _startBox = Rect.zero;
  Offset _grabFlat = Offset.zero;
  Offset _shownStart = Offset.zero, _moved = Offset.zero;

  double get _distance => OverlayVisorProjection.distance(widget.settings);

  /// Where a flat point shows (the visor's camera when it leans the events).
  Offset _shown(Offset flat) =>
      widget.tiltRight == null || widget.tiltDegrees == 0
      ? flat
      : OverlayVisorProjection.point(
          flat,
          right: widget.tiltRight!,
          degrees: widget.tiltDegrees,
          surface: widget.surfaceSize,
          distance: _distance,
        );

  void _start(PointerDownEvent event) {
    if ((event.buttons & kPrimaryMouseButton) == 0 || _pointer != null) return;
    widget.onSelected?.call('events');
    if (widget.onPlacementChanged == null) return;
    _pointer = event.pointer;
    _rawTop = _startTop = widget.eventRect.top;
    _startBox = widget.eventRect;
    // the grabbed point: flat in the block's own coordinates, then on screen
    _grabFlat =
        widget.eventRect.topLeft +
        Offset(
          event.localPosition.dx / widget.scaleX.clamp(0.0001, double.infinity),
          event.localPosition.dy / widget.scaleY.clamp(0.0001, double.infinity),
        );
    _shownStart = _shown(_grabFlat);
    _moved = Offset.zero;
    _pointerX = _shownStart.dx;
    widget.onGestureStart?.call();
  }

  void _update(PointerMoveEvent event) {
    if (event.pointer != _pointer || _rawTop == null || _pointerX == null) {
      return;
    }
    _moved += Offset(
      event.delta.dx / widget.scaleX.clamp(0.0001, double.infinity),
      event.delta.dy / widget.scaleY.clamp(0.0001, double.infinity),
    );
    final shown = _shownStart + _moved;
    _pointerX = shown.dx;
    if (widget.visorPlacement) return _placeFree(shown);
    // the old one-line preview: the pointer's half picks the side, the drag
    // moves it up or down
    _rawTop = _startTop + _moved.dy;
    final (minTop, maxTop) = _verticalRange();
    final available = math.max(1.0, maxTop - minTop);
    final top = _snapTop(_rawTop!, minTop, maxTop);
    widget.onPlacementChanged!(
      _pointerX! < widget.surfaceSize.width / 2 ? 'Left' : 'Right',
      ((top - minTop) / available).clamp(0.0, 1.0).toDouble(),
    );
  }

  (double, double) _verticalRange() {
    final minTop =
        OverlayWorkspaceLayoutGeometry.eventNotificationVerticalInset;
    final maxTop = math.max(
      minTop,
      widget.surfaceSize.height -
          widget.eventRect.height -
          OverlayWorkspaceLayoutGeometry.eventNotificationVerticalInset,
    );
    return (minTop, maxTop);
  }

  double _snapTop(double raw, double minTop, double maxTop) {
    var top = raw.clamp(minTop, maxTop).toDouble();
    if (widget.snapPixels > 0) {
      top = (top / widget.snapPixels).round() * widget.snapPixels;
    }
    if (widget.smartSnap) {
      final centeredTop = minTop + (maxTop - minTop) / 2;
      for (final target in [minTop, centeredTop, maxTop]) {
        if ((top - target).abs() <=
            OverlayWorkspaceLayoutGeometry.edgeSnapThreshold) {
          top = target;
          break;
        }
      }
    }
    return top.clamp(minTop, maxTop).toDouble();
  }

  /// The visor's events, anywhere on screen: the flat box moves so the grabbed
  /// point stays under the pointer through the camera of the side it lands on
  /// (OverlayVisorProjection.follow, as the members and chat drag); the half
  /// its centre is in is the side it opens from and leans to. Near the screen
  /// edge it snaps back against the edge (saved as "at the edge").
  void _placeFree(Offset shown) {
    final surface = widget.surfaceSize;
    final move = widget.tiltRight == null || widget.tiltDegrees == 0
        ? _moved
        : OverlayVisorProjection.follow(
            _grabFlat,
            _startBox,
            shown,
            degrees: widget.tiltDegrees,
            surface: surface,
            distance: _distance,
          );
    final unit = 1080 / surface.height;
    final margin = OverlayVisorLayout.screenMargin / unit;
    var box = _startBox.shift(move);
    box = box.translate(
      box.left < margin
          ? margin - box.left
          : box.right > surface.width - margin
          ? surface.width - margin - box.right
          : 0.0,
      0,
    );
    final right = box.center.dx > surface.width / 2;
    final edge = OverlayVisorLayout.edge / unit;
    final edgeLeft = right ? surface.width - edge - box.width : edge;
    final snaps =
        !HardwareKeyboard.instance.isAltPressed &&
        (box.left - edgeLeft).abs() <=
            OverlayWorkspaceLayoutGeometry.edgeSnapThreshold;
    final (minTop, maxTop) = _verticalRange();
    final top = _snapTop(box.top, minTop, maxTop);
    final x = snaps
        ? -1.0
        : ((right ? box.right : box.left) / surface.width).clamp(0.0, 1.0);
    widget.onPlacementChanged!(
      right ? 'Right' : 'Left',
      OverlayVisorLayout.eventYFromTop(top, surface, right: right && snaps),
      x: x.toDouble(),
    );
  }

  void _end(int pointer) {
    if (pointer != _pointer || _rawTop == null) return;
    _pointer = null;
    _rawTop = null;
    _pointerX = null;
    widget.onGestureEnd?.call();
  }

  double _setting(String field) =>
      (widget.settings[field] as num?)?.toDouble() ?? 1;

  @override
  Widget build(BuildContext context) {
    // the editor's content (the Host's, or samples until it answers); on its
    // own (outside the editor) the samples
    final sim = OverlayVisorSimScope.of(context);
    final strings = AppStrings.of(context);
    final simulate = widget.simulate && (sim?.simulate ?? true);
    final content = sim?.content ?? overlayVisorSampleContent(strings.text);
    final sampleLabel =
        sim?.sampleLabel ?? strings.text('overlay.sample.visorSampleData');
    return StarBridgeTooltip(
      message: widget.onPlacementChanged == null
          ? ''
          : strings.text('overlay.preview.eventDrag'),
      consumeEscape: false,
      child: MouseRegion(
        cursor: widget.onPlacementChanged == null
            ? widget.onSelected == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click
            : SystemMouseCursors.move,
        child: Listener(
          key: const Key('overlay-runtime-preview-event'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _start,
          onPointerMove: _update,
          onPointerUp: (event) => _end(event.pointer),
          onPointerCancel: (event) => _end(event.pointer),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            child: widget.visorPlacement
                ? SizedBox(
                    width: widget.eventRect.width,
                    height: widget.eventRect.height,
                    child: !simulate
                        // sample information off: the block's name only
                        ? OverlayPreviewModuleSurface(
                            settings: widget.settings,
                            backgroundOpacity: _setting(
                              'eventNotificationBackgroundOpacity',
                            ),
                            textOpacity: 1,
                            decorationOpacity: _setting(
                              'eventNotificationDecorationOpacity',
                            ),
                            child: OverlayPreviewContent(
                              moduleKey: 'Events',
                              settings: widget.settings,
                              referenceSize: widget.eventRect.size,
                            ),
                          )
                        : OverlayVisorSimPanel(
                            key: const Key(
                              'overlay-simulated-structure-Events',
                            ),
                            block: 'events',
                            content: content,
                            settings: widget.settings,
                            right:
                                widget.settings['eventNotificationSide'] !=
                                'Left',
                            textOpacity: _setting(
                              'eventNotificationTextOpacity',
                            ),
                            backgroundOpacity: _setting(
                              'eventNotificationBackgroundOpacity',
                            ),
                            decorationOpacity: _setting(
                              'eventNotificationDecorationOpacity',
                            ),
                            sampleLabel: sampleLabel,
                          ),
                  )
                : SizedBox(
                    width: widget.eventRect.width,
                    height: OverlayWorkspaceLayoutGeometry
                        .singleEventNotificationPreviewHeight,
                    child: OverlayPreviewModuleSurface(
                      settings: widget.settings,
                      backgroundOpacity: _setting(
                        'eventNotificationBackgroundOpacity',
                      ),
                      textOpacity: _setting('eventNotificationTextOpacity'),
                      decorationOpacity: _setting(
                        'eventNotificationDecorationOpacity',
                      ),
                      child: OverlayPreviewContent(
                        moduleKey: 'Events',
                        settings: widget.settings,
                        referenceSize: Size(
                          widget.eventRect.width,
                          OverlayWorkspaceLayoutGeometry
                              .singleEventNotificationPreviewHeight,
                        ),
                        simulate: widget.simulate,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
