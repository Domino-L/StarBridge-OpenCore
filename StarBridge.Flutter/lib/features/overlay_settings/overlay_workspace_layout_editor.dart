import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'overlay_preview_identity.dart';
import 'overlay_preview_sources.dart';
import 'overlay_scene_controller.dart';
import 'overlay_visor_editor_overlay.dart';

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
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_runtime_projection.dart';
import 'overlay_workspace_fixed_previews.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_canvas_module.dart';
import 'overlay_visor_projection.dart';
import 'overlay_visor_editor_content.dart';
import 'overlay_visor_rally_sample.dart';
import 'overlay_visor_sim_scope.dart';
import 'overlay_workspace_editor_group_panel.dart';

class OverlayWorkspaceInteractivePreview extends StatelessWidget {
  const OverlayWorkspaceInteractivePreview({
    required this.module,
    required this.editor,
    this.selectionOnly = false,
    this.background,
    this.showGrid,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlayWorkspaceEditorState editor;
  final bool selectionOnly;
  final Widget? background;
  final bool? showGrid;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: module.projection,
    builder: (context, projection, _) => AbsorbPointer(
      absorbing: projection.busy,
      child: OverlayWorkspaceLayoutWorkbench(
        layout: projection.layout,
        settings: projection.settings!,
        editOwner: (module, projection.snapshot),
        currentEditOwner: () => (module, module.projection.value.snapshot),
        controller: editor,
        previewIdentity: module.previewIdentity,
        sources: projection.sources,
        sourceScenes: module.sourceScenes,
        canvasOnly: true,
        selectionOnly: selectionOnly,
        background: background,
        showGrid: showGrid,
        showHiddenModules: false,
        editorContent: module.createVisorEditorContent,
        onSettingChanged: module.updateSetting,
        onMembersResized: module.updateMembersSize,
        onSizeStep: module.stepMembersSize,
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
    this.onMembersResized,
    this.onSizeStep,
    this.appearances = const [],
    this.onExperiencePreset,
    this.onEventNotificationPlacement,
    this.onEventNotificationGestureStart,
    this.onEventNotificationGestureEnd,
    this.previewIdentity,
    this.sources,
    this.sourceScenes,
    this.controller,
    this.fullScreen = false,
    this.fullscreenButton,
    this.presetId = 'preset1',
    this.startupExtra,
    this.editorActions,
    this.canvasOnly = false,
    this.editOwner,
    this.currentEditOwner,
    this.showHiddenModules = true,
    this.selectionOnly = false,
    this.background,
    this.showGrid,
    this.editorContent,
    this.groupFooterExtra,
    super.key,
  });

  /// What the settings page shows below a block's group, shown the same way
  /// in the full-screen tools (11-13, 请你定 3): the member picker.
  final Widget? Function(String group)? groupFooterExtra;

  final List<OverlayWorkspaceLayoutItem> layout;

  /// Makes the source of what the visor would show (the Host's members,
  /// events and chat) for this editor's simplified panels; null, or a null
  /// result, shows samples.
  final OverlayVisorEditorContentSource? Function()? editorContent;
  final OverlayWorkspaceSettings settings;
  final Object? editOwner;
  final Object? Function()? currentEditOwner;
  final List<OverlayWorkspaceAppearance> appearances;
  final void Function(String field, Object? value)? onSettingChanged;
  final void Function(int width, int height, OverlayWorkspaceLayoutItem item)?
  onMembersResized;
  final void Function(String field, Object? value)? onSizeStep;
  final ValueChanged<String>? onExperiencePreset;
  final void Function(String side, double normalizedY, {double? x})?
  onEventNotificationPlacement;
  final VoidCallback? onEventNotificationGestureStart;
  final VoidCallback? onEventNotificationGestureEnd;
  final ValueListenable<OverlayPreviewIdentity?>? previewIdentity;
  final OverlayPresetSources? sources;
  final ValueListenable<OverlaySceneState>? sourceScenes;
  final OverlayWorkspaceEditorState? controller;
  final bool fullScreen;
  final Widget? fullscreenButton;
  final String presetId;
  final Widget? startupExtra;
  final Widget? editorActions;
  final bool canvasOnly;
  final bool showHiddenModules;
  final bool selectionOnly;
  final Widget? background;
  final bool? showGrid;
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
  final _visor = OverlayVisorEditing();
  Rect? _membersResizePreview;
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
    _content = widget.editorContent?.call()?..addListener(_changed);
  }

  OverlayVisorEditorContentSource? _content;

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
    _content?.dispose();
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
    return OverlayPreviewSourceScope(
      sources: widget.sources,
      scenes: widget.sourceScenes,
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = context.tokens;
    if (widget.fullScreen) _editor.fullscreenSurfaceSize = _surfaceSize;
    if (widget.canvasOnly) {
      // the settings page's preview: never wider than the surface it shows
      // (11-12 "显示区不够大也不要增加文字大小"), centred when there is room
      return LayoutBuilder(
        builder: (context, outer) {
          final preview = AspectRatio(
            aspectRatio: 16 / 9,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _canvas(context, constraints.biggest),
            ),
          );
          return outer.maxWidth > _surfaceSize.width
              ? Center(
                  child: SizedBox(width: _surfaceSize.width, child: preview),
                )
              : preview;
        },
      );
    }
    final selected = _selected;
    _editor.selectedKey ??= selected?.key;
    final inspector = selected == null
        ? const SizedBox.shrink()
        : _inspector(selected);
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
                        // the appearance itself is the appearance centre's;
                        // its settings moved to Global and the blocks (11-11)
                        items: overlayWorkspaceNavigationGroupOrder
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
                    OverlayWorkspaceEditorGroupPanel(
                      group: _panelGroup,
                      settings: widget.settings,
                      layout: widget.layout,
                      selected: selected,
                      editOwner:
                          widget.editOwner ??
                          (widget.presetId, widget.settings),
                      currentEditOwner: widget.currentEditOwner,
                      appearances: widget.appearances,
                      onSettingChanged: widget.onSettingChanged ?? (_, _) {},
                      onSizeStep: widget.onSizeStep,
                      layoutLocked: _editor.layoutLocked,
                      onLayoutChanged: widget.onChanged,
                      onExperiencePreset: widget.onExperiencePreset,
                      position: (item) =>
                          _inspector(item, embedded: true, positionOnly: true),
                      onOpenGlobal: () => _selectPanelGroup('global'),
                      startupExtra: widget.startupExtra,
                      footerExtra: widget.groupFooterExtra?.call(_panelGroup),
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
              _atMostActualSize(
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) => _canvas(
                      context,
                      Size(constraints.maxWidth, constraints.maxHeight),
                    ),
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

  Widget _inspector(
    OverlayWorkspaceLayoutItem item, {
    bool embedded = false,
    bool positionOnly = false,
  }) => OverlayWorkspaceLayoutInspector(
    key: ValueKey('overlay-layout-inspector-${item.key}'),
    item: item,
    presetId: widget.presetId,
    layoutLocked: _editor.layoutLocked,
    nudgePixels: _editor.nudgePixels,
    surfaceSize: _surfaceSize,
    embedded: embedded,
    positionOnly: positionOnly,
    settings: widget.settings,
    onChanged: widget.onChanged,
  );

  /// The canvas is never drawn larger than the surface it stands for, so the
  /// visor's text never grows past its real size however wide the page is
  /// (11-12 user: "显示区不够大也不要增加文字大小"); smaller, everything shrinks
  /// together.
  Widget _atMostActualSize(Widget canvas) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _surfaceSize.width),
      child: canvas,
    ),
  );

  Widget _canvas(BuildContext context, Size viewportSize) {
    final tokens = context.tokens;
    // the visor's side blocks lean as the visor draws them (11-11 "同样的3d效果")
    final tilts = OverlayVisorProjection.tilts(
      widget.layout,
      widget.settings,
      _surfaceSize,
    );
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
    // what the visor would show, for the simplified panels (11-12): asked
    // again when the draft or its sources change; the panels keep what they
    // show until the answer comes
    if (_projectsSampleInformation &&
        OverlayVisorLayout.active(widget.settings)) {
      _content?.sync((widget.sources, widget.settings));
    }
    final canvas = Container(
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
          if (widget.background != null)
            Positioned.fill(child: IgnorePointer(child: widget.background!)),
          if (widget.showGrid ?? _editor.showGrid)
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
          // the rally's other dock while it is selected or dragged (11-18)
          if (visibility.isLayoutModuleVisible('Notice'))
            ?OverlayVisorRallySlots.forLayout(
              layout: widget.layout,
              settings: widget.settings,
              surface: _surfaceSize,
              scale: Offset(scaleX, scaleY),
              // previews (import, shared, runtime cards) show it only held
              selected:
                  _editor.selectedKey == 'Notice' &&
                  !widget.canvasOnly &&
                  !widget.selectionOnly,
              dragDy: _visor.rallyDy,
            ),
          ...widget.layout
              .where(
                (item) =>
                    // the visor shows the overview inside the members block
                    !OverlayVisorLayout.mergedIntoMembers(
                      widget.settings,
                      item.key,
                    ) &&
                    (widget.showHiddenModules ||
                        visibility.isLayoutModuleVisible(item.key)),
              )
              .where(
                (item) =>
                    !(_projectsSampleInformation &&
                        item.key == 'Chat' &&
                        OverlayPreviewSourceScope.of(
                              context,
                              'Chat',
                            )?.unavailable !=
                            true &&
                        widget.settings['chatDisplayMode'] ==
                            'FullScreenBarrage'),
              )
              .map((item) {
                // Defer collision arrangement of the grabbed box until release.
                final rect =
                    (item.key == 'Members' && !_editor.layoutLocked
                        ? _membersResizePreview
                        : null) ??
                    _visor.shown(
                      item,
                      widget.settings,
                      _surfaceSize,
                      widget.layout,
                    ) ??
                    resolvedItems[item.key]!;
                final selected = item.key == _editor.selectedKey;
                return Positioned(
                  left: rect.left * scaleX,
                  top: rect.top * scaleY,
                  width: rect.width * scaleX,
                  height: rect.height * scaleY,
                  child: _tilted(
                    item.key,
                    rect,
                    scaleX,
                    scaleY,
                    tilts,
                    OverlayWorkspaceCanvasModule(
                      // the settings page's small preview moves and resizes
                      // like the full-screen editor (11-13 user)
                      // a visor block reads from its screen edge (the side it
                      // leans to; one placed up top, the half it is in)
                      visorRight:
                          OverlayVisorEditing.boxOrNull(
                                item,
                                widget.settings,
                                _surfaceSize,
                                widget.layout,
                              ) ==
                              null
                          ? null
                          : tilts[item.key] ??
                                rect.center.dx > _surfaceSize.width / 2,
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
                      onMoveStart: (grab) => _beginGesture(
                        item,
                        grab:
                            rect.topLeft +
                            Offset(grab.dx / scaleX, grab.dy / scaleY),
                      ),
                      onMove: (delta) => _move(item, delta, viewportSize),
                      onMoveEnd: _endGesture,
                      onResizeStart: () => _beginGesture(item),
                      onResize: (delta) => _resize(item, delta, viewportSize),
                      onResizeEnd: _endGesture,
                    ),
                  ),
                );
              }),
          if (OverlayVisorLayout.active(widget.settings))
            Positioned.fill(
              child: OverlayVisorEditorOverlay(
                layout: widget.layout,
                settings: widget.settings,
                surface: _surfaceSize,
                guides: _visor.guides,
                guideColor: tokens.colors.accent,
                warningColor: tokens.colors.danger,
                onSettingChanged: _editor.layoutLocked
                    ? null
                    : widget.onSettingChanged,
                onGestureStart: widget.onEventNotificationGestureStart,
                onGestureEnd: widget.onEventNotificationGestureEnd,
                onMembersResized: _editor.layoutLocked
                    ? null
                    : widget.onMembersResized,
                onResizePreview: (box) =>
                    setState(() => _membersResizePreview = box),
              ),
            ),
          Positioned.fill(
            child: OverlayWorkspaceFixedPreviews(
              selectionOnly: widget.selectionOnly,
              settings: widget.settings,
              layout: widget.layout,
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
              onSelected: widget.fullScreen || widget.selectionOnly
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
    final strings = AppStrings.of(context);
    return OverlayVisorSimScope(
      content: _content?.content ?? overlayVisorSampleContent(strings.text),
      sampleLabel: strings.text('overlay.sample.visorSampleData'),
      simulate: _projectsSampleInformation,
      child: canvas,
    );
  }

  /// A visor side block shown through the visor's camera: drawn and hit where
  /// the visor shows it; placing stays on the flat box.
  Widget _tilted(
    String key,
    Rect rect,
    double scaleX,
    double scaleY,
    Map<String, bool> tilts,
    Widget child,
  ) {
    final right = tilts[key];
    final degrees = OverlayVisorProjection.degrees(widget.settings);
    if (right == null || degrees == 0) return child;
    return Transform(
      transform: OverlayVisorProjection.forWidget(
        rect,
        right: right,
        degrees: degrees,
        surface: _surfaceSize,
        distance: OverlayVisorProjection.distance(widget.settings),
        scaleX: scaleX,
        scaleY: scaleY,
      ),
      child: child,
    );
  }

  /// [grab]: the flat point grabbed (surface pixels), for a leaning block.
  void _beginGesture(OverlayWorkspaceLayoutItem item, {Offset? grab}) {
    _selectLayoutModule(item.key);
    _gestureStart = item;
    _gestureDelta = Offset.zero;
    _grab = _grabShown = null;
    final degrees = OverlayVisorProjection.degrees(widget.settings);
    final leans = OverlayVisorProjection.tilts(
      widget.layout,
      widget.settings,
      _surfaceSize,
    ).containsKey(item.key);
    if (grab == null || !leans || degrees == 0) return;
    final box = OverlayVisorLayout.boxOf(
      item,
      widget.settings,
      _surfaceSize,
      widget.layout,
    );
    _grab = grab;
    _grabBox = box;
    _grabShown = OverlayVisorProjection.point(
      grab,
      right: box.center.dx > _surfaceSize.width / 2,
      degrees: degrees,
      surface: _surfaceSize,
      distance: OverlayVisorProjection.distance(widget.settings),
    );
  }

  Offset? _grab, _grabShown;
  Rect _grabBox = Rect.zero;

  /// The flat move for the pointer's move on screen ([_gestureDelta]): a
  /// leaning block moves so the point grabbed stays under the pointer, worked
  /// out from where the pointer is each time (reviews CX-VISOR-EVENTS3D-R1,
  /// R2); a flat one by the pointer's move.
  Offset _flatDelta(String key) {
    final grab = _grab, shown = _grabShown;
    if (grab == null || shown == null) return _gestureDelta;
    return OverlayVisorProjection.follow(
      grab,
      _grabBox,
      shown + _gestureDelta,
      degrees: OverlayVisorProjection.degrees(widget.settings),
      surface: _surfaceSize,
      distance: OverlayVisorProjection.distance(widget.settings),
    );
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
    final s = widget.settings, l = widget.layout;
    final v = _visor.move(
      _gestureStart!,
      _flatDelta(item.key),
      l,
      s,
      _surfaceSize,
    );
    // the rally only follows the pointer until release (v is its start)
    if (v != null) {
      return setState(
        () => v == _gestureStart ? null : widget.onChanged(v, true),
      );
    }
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
    final visor = OverlayVisorEditing.handles(widget.settings, item.key);
    if (_editor.layoutLocked || item.isLocked || _gestureStart == null) return;
    if (visor) return; // visor blocks keep the S/M/L size setting
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
    final start = _gestureStart;
    _gestureStart = null;
    _gestureDelta = Offset.zero;
    final s = widget.settings, l = widget.layout;
    final v = _visor.end(start?.key, l, s, _surfaceSize);
    // a rally drop is its own undo step; a drop after a drag joins the drag
    // (review CX-OVERLAY-M102-R1 P2-5)
    setState(
      () => v == null ? null : widget.onChanged(v, start?.key != 'Notice'),
    );
  }
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
