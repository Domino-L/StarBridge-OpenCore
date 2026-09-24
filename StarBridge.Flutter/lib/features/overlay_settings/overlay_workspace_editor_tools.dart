import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_editor_state.dart';

const overlayModuleVisibilityFields = <String, String>{
  'Notice': 'showNotice',
  'Squads': 'showSquads',
  'Members': 'showMembers',
  'Chat': 'showChat',
  'Crosshair': 'showCrosshair',
  'Events': 'showEventNotifications',
};

class OverlayWorkspaceEditorTools extends StatelessWidget {
  const OverlayWorkspaceEditorTools({
    required this.editor,
    this.fullscreenButton,
    this.allowSimulation = false,
    super.key,
  });
  final OverlayWorkspaceEditorState editor;
  final Widget? fullscreenButton;
  final bool allowSimulation;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('overlay-editor-preview-assists'),
            child: Wrap(
              spacing: tokens.space.xs,
              runSpacing: tokens.space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ?fullscreenButton,
                if (allowSimulation)
                  FilterChip(
                    key: const Key('overlay-editor-simulate'),
                    label: Text(_copy(context, 'overlay.editor.simulate')),
                    selected: editor.simulateInformation,
                    onSelected: (value) =>
                        editor.change(() => editor.simulateInformation = value),
                  ),
                FilterChip(
                  key: const Key('overlay-layout-show-grid'),
                  label: Text(_copy(context, 'overlay.editor.showGrid')),
                  selected: editor.showGrid,
                  onSelected: (value) =>
                      editor.change(() => editor.showGrid = value),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Divider(height: 1, color: tokens.surfaces.panel.border),
          SizedBox(height: tokens.space.sm),
          Container(
            key: const Key('overlay-editor-grid-snap'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToolToggleRow(
                  label: _copy(context, 'overlay.workspace.layout.grid'),
                  value: editor.snapToGrid,
                  switchKey: const Key('overlay-layout-grid-snap-toggle'),
                  onChanged: (value) =>
                      editor.change(() => editor.snapToGrid = value),
                ),
                if (editor.snapToGrid) ...[
                  SizedBox(height: tokens.space.xs),
                  Wrap(
                    spacing: tokens.space.xs,
                    runSpacing: tokens.space.xs,
                    children: <double>[16, 32, 64]
                        .map(
                          (value) => ChoiceChip(
                            key: Key('overlay-layout-grid-${value.round()}'),
                            label: Text('${value.round()} px'),
                            selected: editor.gridSize == value,
                            onSelected: (_) =>
                                editor.change(() => editor.gridSize = value),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Divider(height: 1, color: tokens.surfaces.panel.border),
          SizedBox(height: tokens.space.sm),
          Container(
            key: const Key('overlay-editor-layout-constraints'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToolToggleRow(
                  label: _copy(context, 'overlay.workspace.layout.smartSnap'),
                  value: editor.smartSnap,
                  switchKey: const Key('overlay-layout-smart-snap'),
                  onChanged: (value) =>
                      editor.change(() => editor.smartSnap = value),
                ),
                _ToolToggleRow(
                  label: _copy(context, 'overlay.editor.lockAll'),
                  value: editor.layoutLocked,
                  switchKey: const Key('overlay-layout-lock-all'),
                  onChanged: (value) =>
                      editor.change(() => editor.layoutLocked = value),
                ),
                SizedBox(height: tokens.space.xs),
                Wrap(
                  spacing: tokens.space.xs,
                  runSpacing: tokens.space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_copy(context, 'overlay.workspace.layout.nudgeStep')),
                    ...<double>[1, 5, 10].map(
                      (value) => ChoiceChip(
                        key: Key('overlay-layout-nudge-${value.round()}'),
                        label: Text('${value.round()} px'),
                        selected: editor.nudgePixels == value,
                        onSelected: (_) =>
                            editor.change(() => editor.nudgePixels = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolToggleRow extends StatelessWidget {
  const _ToolToggleRow({
    required this.label,
    required this.value,
    required this.switchKey,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Switch(key: switchKey, value: value, onChanged: onChanged),
    ],
  );
}

class OverlayWorkspaceFloatingTools extends StatefulWidget {
  const OverlayWorkspaceFloatingTools({
    required this.available,
    required this.child,
    required this.editor,
    this.actions,
    super.key,
  });
  final Size available;
  final Widget? actions;
  final Widget child;
  final OverlayWorkspaceEditorState editor;
  @override
  State<OverlayWorkspaceFloatingTools> createState() => _FloatingToolsState();
}

class _FloatingToolsState extends State<OverlayWorkspaceFloatingTools> {
  final _scroll = ScrollController();
  int? _dragPointer;
  Offset? _dragStart;
  Offset? _panelStart;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final width = math
        .min(408.0, widget.available.width - 24)
        .clamp(1.0, 408.0);
    final height = math.max(1.0, widget.available.height - 148);
    final maxX = math.max(12.0, widget.available.width - width - 12);
    final maxY = math.max(64.0, widget.available.height - height - 12);
    final preferred = widget.editor.toolsPosition ?? Offset(maxX, 76);
    final position = Offset(
      preferred.dx.clamp(12.0, maxX),
      preferred.dy.clamp(64.0, maxY),
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: width,
      height: height,
      child: Material(
        elevation: 12,
        color: tokens.surfaces.floating.fill,
        shape: RoundedRectangleBorder(
          borderRadius: tokens.shape.small,
          side: BorderSide(color: tokens.surfaces.panel.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Listener(
                key: const Key('overlay-editor-tools-drag'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if ((event.buttons & kPrimaryMouseButton) == 0) return;
                  _dragPointer = event.pointer;
                  _dragStart = event.position;
                  _panelStart = position;
                },
                onPointerMove: (event) {
                  if (event.pointer != _dragPointer) return;
                  final target = _panelStart! + event.position - _dragStart!;
                  setState(
                    () => widget.editor.toolsPosition = Offset(
                      target.dx.clamp(12.0, maxX),
                      target.dy.clamp(64.0, maxY),
                    ),
                  );
                },
                onPointerUp: (_) => _dragPointer = null,
                onPointerCancel: (_) => _dragPointer = null,
                child: Padding(
                  padding: EdgeInsets.all(tokens.space.sm),
                  child: Row(
                    children: [
                      const StarBridgeIcon(
                        StarBridgeIconSemantic.dragHandle,
                        size: 18,
                      ),
                      SizedBox(width: tokens.space.sm),
                      Text(_copy(context, 'overlay.editor.tools')),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: tokens.surfaces.panel.border),
            ?widget.actions,
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.all(tokens.space.sm),
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OverlayWorkspaceGridPainter extends CustomPainter {
  const OverlayWorkspaceGridPainter({
    required this.spacing,
    required this.color,
  });
  final double spacing;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (spacing < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(OverlayWorkspaceGridPainter oldDelegate) =>
      spacing != oldDelegate.spacing || color != oldDelegate.color;
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
