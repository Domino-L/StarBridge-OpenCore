import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'overlay_preview_identity.dart';
import 'overlay_workspace_preview_content.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_inspector.dart';
import 'overlay_workspace_editor_tools.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_module_style_controls.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_runtime_projection.dart';
import 'overlay_workspace_fixed_previews.dart';
import 'overlay_workspace_module.dart';

class OverlayWorkspaceInteractivePreview extends StatelessWidget {
  const OverlayWorkspaceInteractivePreview({
    required this.module,
    required this.editor,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: module.projection,
    builder: (context, projection, _) => AbsorbPointer(
      absorbing: projection.busy,
      child: OverlayWorkspaceLayoutWorkbench(
        layout: projection.layout,
        settings: projection.settings!,
        controller: editor,
        previewIdentity: module.previewIdentity,
        canvasOnly: true,
        showHiddenModules: false,
        onSettingChanged: module.updateSetting,
        onEventNotificationPlacement: module.updateEventNotificationPlacement,
        onEventNotificationGestureStart: module.beginEventNotificationGesture,
        onEventNotificationGestureEnd: module.endEventNotificationGesture,
        onChanged: (item, coalesce) =>
            module.updateLayoutItem(item, coalesce: coalesce),
      ),
    ),
  );
}

class OverlayWorkspaceLayoutWorkbench extends StatefulWidget {
  const OverlayWorkspaceLayoutWorkbench({
    required this.layout,
    required this.settings,
    required this.onChanged,
    this.onSettingChanged,
    this.appearances = const [],
    this.onExperiencePreset,
    this.onEventNotificationPlacement,
    this.onEventNotificationGestureStart,
    this.onEventNotificationGestureEnd,
    this.previewIdentity,
    this.controller,
    this.fullScreen = false,
    this.fullscreenButton,
    this.presetId = 'preset1',
    this.startupExtra,
    this.editorActions,
    this.canvasOnly = false,
    this.showHiddenModules = true,
    super.key,
  });

  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceAppearance> appearances;
  final void Function(String field, Object? value)? onSettingChanged;
  final ValueChanged<String>? onExperiencePreset;
  final void Function(String side, double normalizedY)?
  onEventNotificationPlacement;
  final VoidCallback? onEventNotificationGestureStart;
  final VoidCallback? onEventNotificationGestureEnd;
  final ValueListenable<OverlayPreviewIdentity?>? previewIdentity;
  final OverlayWorkspaceEditorState? controller;
  final bool fullScreen;
  final Widget? fullscreenButton;
  final String presetId;
  final Widget? startupExtra;
  final Widget? editorActions;
  final bool canvasOnly;
  final bool showHiddenModules;
  final void Function(OverlayWorkspaceLayoutItem item, bool coalesce) onChanged;

  @override
  State<OverlayWorkspaceLayoutWorkbench> createState() =>
      _OverlayWorkspaceLayoutWorkbenchState();
}

class _OverlayWorkspaceLayoutWorkbenchState
    extends State<OverlayWorkspaceLayoutWorkbench> {
  static const _moduleKeyByGroup = <String, String>{
    'notice': 'Notice',
    'fleetOverview': 'Squads',
    'members': 'Members',
    'chat': 'Chat',
    'events': 'Events',
    'crosshair': 'Crosshair',
  };
  static const _groupByModuleKey = <String, String>{
    'Notice': 'notice',
    'Squads': 'fleetOverview',
    'Members': 'members',
    'Chat': 'chat',
    'Events': 'events',
    'Crosshair': 'crosshair',
  };

  late final OverlayWorkspaceEditorState _editor;
  late String _panelGroup;
  OverlayWorkspaceLayoutItem? _gestureStart;
  Offset _gestureDelta = Offset.zero;
  Size get _surfaceSize => widget.fullScreen
      ? MediaQuery.sizeOf(context)
      : OverlayWorkspaceLayoutGeometry.referenceSize;
  bool get _projectsSampleInformation =>
      widget.fullScreen ? _editor.simulateInformation : true;

  @override
  void initState() {
    super.initState();
    _editor = widget.controller ?? OverlayWorkspaceEditorState();
    _editor.selectedKey ??= widget.layout.firstOrNull?.key;
    _panelGroup =
        _groupByModuleKey[_editor.selectedKey] ??
        overlayWorkspaceGroupOrder.first;
    _editor.addListener(_changed);
    widget.previewIdentity?.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant OverlayWorkspaceLayoutWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewIdentity != widget.previewIdentity) {
      oldWidget.previewIdentity?.removeListener(_changed);
      widget.previewIdentity?.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _editor.removeListener(_changed);
    widget.previewIdentity?.removeListener(_changed);
    if (widget.controller == null) _editor.dispose();
    super.dispose();
  }

  OverlayWorkspaceLayoutItem? get _selected {
    if (widget.layout.isEmpty) return null;
    return widget.layout.cast<OverlayWorkspaceLayoutItem?>().firstWhere(
      (item) => item?.key == _editor.selectedKey,
      orElse: () => widget.fullScreen ? null : widget.layout.first,
    );
  }

  void _selectPanelGroup(String group) {
    _panelGroup = group;
    _editor.change(() => _editor.selectedKey = _moduleKeyByGroup[group]);
  }

  void _selectLayoutModule(String key) {
    _panelGroup = _groupByModuleKey[key] ?? _panelGroup;
    _editor.change(() => _editor.selectedKey = key);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (widget.fullScreen) _editor.fullscreenSurfaceSize = _surfaceSize;
    if (widget.canvasOnly) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _canvas(context, constraints.biggest),
        ),
      );
    }
    final selected = _selected;
    _editor.selectedKey ??= selected?.key;
    final inspector = selected == null
        ? const SizedBox.shrink()
        : OverlayWorkspaceLayoutInspector(
            key: ValueKey('overlay-layout-inspector-${selected.key}'),
            item: selected,
            presetId: widget.presetId,
            layoutLocked: _editor.layoutLocked,
            nudgePixels: _editor.nudgePixels,
            surfaceSize: _surfaceSize,
            onChanged: widget.onChanged,
          );
    final toolbar = OverlayWorkspaceEditorTools(
      editor: _editor,
      fullscreenButton: widget.fullscreenButton,
      allowSimulation: widget.fullScreen,
    );
    if (widget.fullScreen) {
      return LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: _canvas(context, constraints.biggest)),
            if (_editor.toolsVisible)
              OverlayWorkspaceFloatingTools(
                available: constraints.biggest,
                editor: _editor,
                actions: widget.editorActions,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    toolbar,
                    SizedBox(height: tokens.space.sm),
                    KeyedSubtree(
                      key: const Key('overlay-fullscreen-section'),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'overlay-fullscreen-section-$_panelGroup',
                        ),
                        initialValue: _panelGroup,
                        isExpanded: true,
                        items: overlayWorkspaceGroupOrder
                            .map(
                              (group) => DropdownMenuItem(
                                value: group,
                                child: Text(
                                  overlayWorkspaceGroupName(context, group),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (group) {
                          if (group != null) _selectPanelGroup(group);
                        },
                      ),
                    ),
                    SizedBox(height: tokens.space.sm),
                    OverlayWorkspaceSettingsGroup(
                      group: _panelGroup,
                      fields: overlayWorkspaceFieldSpecs
                          .where((field) => field.group == _panelGroup)
                          .toList(),
                      settings: widget.settings,
                      appearances: widget.appearances,
                      onChanged: widget.onSettingChanged ?? (_, _) {},
                      onExperiencePreset: widget.onExperiencePreset,
                      footer: switch (_panelGroup) {
                        'notice' || 'fleetOverview' || 'members' || 'chat'
                            when selected != null =>
                          OverlayWorkspaceLayoutInspector(
                            key: ValueKey(
                              'overlay-layout-inspector-${selected.key}',
                            ),
                            item: selected,
                            presetId: widget.presetId,
                            layoutLocked: _editor.layoutLocked,
                            nudgePixels: _editor.nudgePixels,
                            surfaceSize: _surfaceSize,
                            embedded: true,
                            onChanged: widget.onChanged,
                          ),
                        'events' => OverlayWorkspaceModuleStyleControls(
                          group: _panelGroup,
                          layout: widget.layout,
                          settings: widget.settings,
                          onLayoutChanged: widget.onChanged,
                          onSettingChanged:
                              widget.onSettingChanged ?? (_, _) {},
                        ),
                        'startup' => widget.startupExtra,
                        _ => null,
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        SizedBox(height: tokens.space.sm),
        StarBridgeSurface(
          role: SurfaceRole.panel,
          padding: EdgeInsets.all(tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _copy(context, 'overlay.workspace.layout.dragHelp'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: tokens.space.sm),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) => _canvas(
                    context,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space.md),
        inspector,
      ],
    );
  }

  Widget _canvas(BuildContext context, Size viewportSize) {
    final tokens = context.tokens;
    final resolvedItems = OverlayWorkspaceLayoutGeometry.resolveItems(
      widget.layout,
      surfaceSize: _surfaceSize,
    );
    final visibility = OverlayWorkspaceRuntimeProjection.resolveVisibility(
      widget.settings,
      noticeHasContent: true,
      chatHasContent: true,
      eventNotificationsHaveContent: true,
    );
    final scaleX = viewportSize.width / _surfaceSize.width;
    final scaleY = viewportSize.height / _surfaceSize.height;
    return Container(
      key: Key(
        widget.canvasOnly ? 'overlay-runtime-preview' : 'overlay-layout-canvas',
      ),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: tokens.surfaces.ground.fill),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: tokens.surfaces.panel.border),
      ),
      child: Stack(
        children: [
          if (_editor.showGrid)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: OverlayWorkspaceGridPainter(
                    spacing: _editor.gridSize * scaleX,
                    color: tokens.colors.accent.withValues(alpha: 0.14),
                  ),
                ),
              ),
            ),
          ...widget.layout
              .where(
                (item) =>
                    widget.showHiddenModules ||
                    visibility.isLayoutModuleVisible(item.key),
              )
              .where(
                (item) =>
                    !(_projectsSampleInformation &&
                        item.key == 'Chat' &&
                        widget.settings['chatDisplayMode'] ==
                            'FullScreenBarrage'),
              )
              .map((item) {
                final rect = resolvedItems[item.key]!;
                final selected = item.key == _editor.selectedKey;
                return Positioned(
                  left: rect.left * scaleX,
                  top: rect.top * scaleY,
                  width: rect.width * scaleX,
                  height: rect.height * scaleY,
                  child: _CanvasModule(
                    key: Key(
                      widget.canvasOnly
                          ? 'overlay-runtime-preview-${item.key}'
                          : 'overlay-layout-module-${item.key}',
                    ),
                    item: _editor.layoutLocked
                        ? item.copyWith(isLocked: true)
                        : item,
                    selected: selected,
                    settings: widget.settings,
                    referenceSize: rect.size,
                    previewIdentity: widget.previewIdentity?.value,
                    simulate: _projectsSampleInformation,
                    isVisible: visibility.isLayoutModuleVisible(item.key),
                    onSelected: () => _selectLayoutModule(item.key),
                    onMoveStart: () => _beginGesture(item),
                    onMove: (delta) => _move(item, delta, viewportSize),
                    onMoveEnd: _endGesture,
                    onResizeStart: () => _beginGesture(item),
                    onResize: (delta) => _resize(item, delta, viewportSize),
                    onResizeEnd: _endGesture,
                  ),
                );
              }),
          Positioned.fill(
            child: OverlayWorkspaceFixedPreviews(
              settings: widget.settings,
              chatTextOpacity:
                  widget.layout
                      .where((item) => item.key == 'Chat')
                      .map((item) => item.textOpacity)
                      .firstOrNull ??
                  1,
              surfaceSize: _surfaceSize,
              simulate: _projectsSampleInformation,
              eventNotificationSnapPixels: _editor.snapPixels,
              eventNotificationSmartSnap: _editor.smartSnap,
              onEventNotificationPlacement: _editor.layoutLocked
                  ? null
                  : widget.onEventNotificationPlacement,
              onEventNotificationGestureStart: _editor.layoutLocked
                  ? null
                  : widget.onEventNotificationGestureStart,
              onEventNotificationGestureEnd: _editor.layoutLocked
                  ? null
                  : widget.onEventNotificationGestureEnd,
              onSelected: widget.fullScreen
                  ? (group) {
                      _panelGroup = group;
                      _editor.change(() {
                        _editor.toolsVisible = true;
                        _editor.selectedKey = _moduleKeyByGroup[group];
                      });
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  void _beginGesture(OverlayWorkspaceLayoutItem item) {
    _selectLayoutModule(item.key);
    _gestureStart = item;
    _gestureDelta = Offset.zero;
  }

  void _move(
    OverlayWorkspaceLayoutItem item,
    Offset viewportDelta,
    Size viewportSize,
  ) {
    if (_editor.layoutLocked || item.isLocked || _gestureStart == null) return;
    _gestureDelta += OverlayWorkspaceLayoutGeometry.scaleDelta(
      viewportDelta,
      viewportSize,
      surfaceSize: _surfaceSize,
    );
    widget.onChanged(
      OverlayWorkspaceLayoutGeometry.move(
        item: _gestureStart!,
        layout: widget.layout,
        delta: _gestureDelta,
        snapPixels: _editor.snapPixels,
        smartSnap: _editor.smartSnap,
        surfaceSize: _surfaceSize,
      ),
      true,
    );
  }

  void _resize(
    OverlayWorkspaceLayoutItem item,
    Offset viewportDelta,
    Size viewportSize,
  ) {
    if (_editor.layoutLocked || item.isLocked || _gestureStart == null) return;
    _gestureDelta += OverlayWorkspaceLayoutGeometry.scaleDelta(
      viewportDelta,
      viewportSize,
      surfaceSize: _surfaceSize,
    );
    widget.onChanged(
      OverlayWorkspaceLayoutGeometry.resize(
        item: _gestureStart!,
        layout: widget.layout,
        delta: _gestureDelta,
        snapPixels: _editor.snapPixels,
        smartSnap: _editor.smartSnap,
        surfaceSize: _surfaceSize,
      ),
      true,
    );
  }

  void _endGesture() {
    _gestureStart = null;
    _gestureDelta = Offset.zero;
  }
}

class _CanvasModule extends StatefulWidget {
  const _CanvasModule({
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
    super.key,
  });
  final OverlayWorkspaceLayoutItem item;
  final bool selected, isVisible, simulate;
  final OverlayWorkspaceSettings settings;
  final Size referenceSize;
  final OverlayPreviewIdentity? previewIdentity;
  final VoidCallback onSelected,
      onMoveStart,
      onMoveEnd,
      onResizeStart,
      onResizeEnd;
  final ValueChanged<Offset> onMove, onResize;
  @override
  State<_CanvasModule> createState() => _CanvasModuleState();
}

class _CanvasModuleState extends State<_CanvasModule> {
  int? _pointer;
  Offset? _previous;
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
    return Semantics(
      label: _moduleName(context, item.key),
      button: true,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          cursor: item.isLocked
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
              if (item.isLocked) return;
              _pointer = event.pointer;
              _previous = event.position;
              _resizing =
                  event.localPosition.dx >= constraints.maxWidth - 24 &&
                  event.localPosition.dy >= constraints.maxHeight - 24;
              if (_resizing) {
                widget.onResizeStart();
              } else {
                widget.onMoveStart();
              }
            },
            onPointerMove: (event) {
              if (event.pointer != _pointer || item.isLocked) return;
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
              if (event.pointer == _pointer) _end();
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
                      backgroundOpacity: item.backgroundOpacity,
                      textOpacity: item.textOpacity,
                      decorationOpacity: item.decorationOpacity,
                      child: OverlayPreviewContent(
                        moduleKey: item.key,
                        settings: widget.settings,
                        referenceSize: widget.referenceSize,
                        previewIdentity: widget.previewIdentity,
                        simulate: widget.simulate,
                      ),
                    ),
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
                if (!item.isLocked)
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
