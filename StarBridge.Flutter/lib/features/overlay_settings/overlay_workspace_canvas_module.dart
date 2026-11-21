import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_preview_identity.dart';
import 'overlay_visor_editor_overlay.dart';
import 'overlay_visor_rally_sample.dart';
import 'overlay_visor_sim_panel.dart';
import 'overlay_visor_sim_scope.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_preview_content.dart';

/// One module on the layout canvas: its outline, name, the hidden and locked
/// marks, and its resize corner (moved out of overlay_workspace_layout_editor.dart
/// for the 800-line size gate).
class OverlayWorkspaceCanvasModule extends StatefulWidget {
  const OverlayWorkspaceCanvasModule({
    required this.item,
    required this.selected,
    required this.isVisible,
    required this.settings,
    required this.referenceSize,
    required this.previewIdentity,
    required this.simulate,
    required this.onSelected,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
    this.selectionOnly = false,
    this.visorRight,
    super.key,
  });

  /// For a visor block, the screen edge it reads from (true: right); null for
  /// an ordinary module. The block then shows the editor's simplified visor
  /// panel (11-12 "编辑里还是要用模拟面板").
  final bool? visorRight;
  final OverlayWorkspaceLayoutItem item;
  final bool selected, isVisible, simulate;
  final bool selectionOnly;
  final OverlayWorkspaceSettings settings;
  final Size referenceSize;
  final OverlayPreviewIdentity? previewIdentity;
  final VoidCallback onSelected, onMoveEnd, onResizeStart, onResizeEnd;
  final ValueChanged<Offset> onMove, onResize;

  /// Where the module was grabbed, in its own (flat) coordinates: inside the
  /// visor's camera these are the flat block's, whatever the lean.
  final ValueChanged<Offset> onMoveStart;
  @override
  State<OverlayWorkspaceCanvasModule> createState() =>
      OverlayWorkspaceCanvasModuleState();
}

class OverlayWorkspaceCanvasModuleState
    extends State<OverlayWorkspaceCanvasModule> {
  int? _pointer;
  Offset? _previous, _down;
  bool _resizing = false;

  void _end() {
    if (_pointer != null) {
      if (_resizing) {
        widget.onResizeEnd();
      } else {
        widget.onMoveEnd();
      }
    }
    _pointer = null;
    _previous = null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tokens = context.tokens;
    // a visor block shows the simplified panel (frame, background, the
    // visor's own layout of what it would show); the surface keeps only the
    // selection outline
    final sim = OverlayVisorSimScope.of(context);
    final block = switch (item.key) {
      'Members' => 'team',
      'Chat' => 'chat',
      _ => null,
    };
    final native =
        widget.visorRight != null &&
        block != null &&
        sim != null &&
        sim.simulate;
    // on the visor the rally block shows a sample rally as the game draws it
    // (11-18 "照真实召集的样子"); a hidden block shows none
    final rally =
        item.key == 'Notice' &&
        OverlayVisorEditing.handles(widget.settings, item.key);
    return Semantics(
      // the rally names its dock, as Alt+M placement does (review P3)
      label: rally
          ? '${_moduleName(context, item.key)} · '
                '${_copy(context, 'overlay.workspace.anchor.${item.verticalAnchor == 'Bottom' ? 'Bottom' : 'Top'}')}'
          : _moduleName(context, item.key),
      button: true,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          cursor: widget.selectionOnly
              ? SystemMouseCursors.click
              : item.isLocked
              ? SystemMouseCursors.basic
              : SystemMouseCursors.move,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if ((event.buttons & kPrimaryMouseButton) == 0 ||
                  _pointer != null) {
                return;
              }
              widget.onSelected();
              if (item.isLocked || widget.selectionOnly) return;
              _pointer = event.pointer;
              _previous = _down = event.position;
              _resizing =
                  event.localPosition.dx >= constraints.maxWidth - 32 &&
                  event.localPosition.dy >= constraints.maxHeight - 32;
              if (_resizing) {
                widget.onResizeStart();
              } else {
                widget.onMoveStart(event.localPosition);
              }
            },
            onPointerMove: (event) {
              if (event.pointer != _pointer ||
                  item.isLocked ||
                  widget.selectionOnly) {
                return;
              }
              final delta = event.position - _previous!;
              _previous = event.position;
              if (_resizing) {
                widget.onResize(delta);
              } else {
                widget.onMove(delta);
              }
            },
            onPointerUp: (event) {
              if (event.pointer == _pointer) _end();
            },
            onPointerCancel: (event) {
              if (event.pointer != _pointer) return;
              // a cancelled rally drag changes nothing: back to where it was
              // grabbed first, so it docks where it was (review
              // CX-OVERLAY-M102-R1 P2-5)
              if (rally && !_resizing && _down != null && _previous != null) {
                widget.onMove(_down! - _previous!);
              }
              _end();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: widget.referenceSize.width,
                    height: widget.referenceSize.height,
                    child: OverlayPreviewModuleSurface(
                      settings: widget.settings,
                      selected: widget.selected,
                      visible: widget.isVisible,
                      // the visor's rally has no plate or frame of its own
                      backgroundOpacity: native || rally
                          ? 0
                          : item.backgroundOpacity,
                      // the simplified panel applies the block's opacities itself
                      // (review CX-OVERLAY-TIDY-R1: 0 here hid the whole panel)
                      textOpacity: native || rally ? 1 : item.textOpacity,
                      decorationOpacity: native || rally
                          ? 0
                          : item.decorationOpacity,
                      child: rally
                          ? const SizedBox.shrink()
                          : native
                          ? OverlayVisorSimPanel(
                              key: Key('overlay-visor-sim-${item.key}'),
                              block: block,
                              content: sim.content,
                              settings: widget.settings,
                              right: widget.visorRight!,
                              textOpacity: item.textOpacity,
                              backgroundOpacity: item.backgroundOpacity,
                              decorationOpacity: item.decorationOpacity,
                              sampleLabel: sim.sampleLabel,
                            )
                          : OverlayPreviewContent(
                              moduleKey: item.key,
                              settings: widget.settings,
                              referenceSize: widget.referenceSize,
                              previewIdentity: widget.previewIdentity,
                              simulate: widget.simulate,
                            ),
                    ),
                  ),
                ),
                if (rally && widget.isVisible)
                  IgnorePointer(
                    child: OverlayVisorRallySample(
                      unit:
                          constraints.maxWidth / OverlayVisorRallySample.width,
                    ),
                  ),
                if (item.isLocked)
                  Positioned(
                    top: 4,
                    right: 6,
                    child: Text(
                      _copy(context, 'overlay.workspace.layout.lockedShort'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                if (!widget.isVisible)
                  Positioned(
                    left: 6,
                    bottom: 4,
                    child: Text(
                      _copy(context, 'overlay.workspace.layout.hiddenShort'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                // a visor block keeps its own size ("面罩大小"): no resize
                // corner on it (11-11 "去掉没用的控件")
                if (!item.isLocked &&
                    !widget.selectionOnly &&
                    !OverlayVisorEditing.handles(widget.settings, item.key))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: SizedBox(
                        key: Key('overlay-layout-resize-${item.key}'),
                        width: 24,
                        height: 24,
                        child: CustomPaint(
                          painter: _ResizeHandlePainter(
                            color: tokens.colors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  const _ResizeHandlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var inset = 5.0; inset <= 15; inset += 5) {
      canvas.drawLine(
        Offset(size.width - inset, size.height),
        Offset(size.width, size.height - inset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResizeHandlePainter oldDelegate) =>
      color != oldDelegate.color;
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);

String _moduleName(BuildContext context, String key) =>
    _copy(context, 'overlay.workspace.module.$key');
