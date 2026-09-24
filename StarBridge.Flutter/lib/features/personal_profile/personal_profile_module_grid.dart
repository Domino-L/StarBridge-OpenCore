import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_favorite_ships.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_favorite_dialog.dart';
import 'personal_profile_grid_chrome.dart';
import 'personal_profile_hangar_overview.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_controls.dart';
import 'personal_profile_positions_module.dart';

class PersonalProfileModuleGrid extends StatefulWidget {
  const PersonalProfileModuleGrid({
    required this.projection,
    required this.visitorView,
    required this.editing,
    required this.layout,
    required this.onLayoutChanged,
    this.onEditPositions,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool visitorView;
  final bool editing;
  final List<PersonalProfileModuleLayoutItem> layout;
  final ValueChanged<List<PersonalProfileModuleLayoutItem>> onLayoutChanged;
  final VoidCallback? onEditPositions;

  @override
  State<PersonalProfileModuleGrid> createState() =>
      _PersonalProfileModuleGridState();
}

class _PersonalProfileModuleGridState extends State<PersonalProfileModuleGrid> {
  double get _cellHeight =>
      140 + (MediaQuery.textScalerOf(context).scale(80) - 80).clamp(0, 160);

  final GlobalKey _canvasKey = GlobalKey();
  List<PersonalProfileModuleLayoutItem>? _dragBaseLayout;
  List<PersonalProfileModuleLayoutItem>? _dragPreviewLayout;
  String? _draggedModuleId;
  int? _dragPreviewPosition;
  bool _dragPointerInside = false;
  DialogRoute<List<String>>? _selectionRoute;
  NavigatorState? _selectionNavigator;

  @override
  void didUpdateWidget(covariant PersonalProfileModuleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.projection, widget.projection)) _closeSelection();
  }

  void _closeSelection() {
    final route = _selectionRoute;
    final navigator = _selectionNavigator;
    _selectionRoute = null;
    _selectionNavigator = null;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
  }

  @override
  void dispose() {
    _closeSelection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized =
        _dragPreviewLayout ?? PersonalProfileLayout.normalize(widget.layout);
    final visible = normalized.where((item) => item.isVisible).toList()
      ..sort(
        (first, second) => PersonalProfileLayout.displayModuleIds
            .indexOf(first.moduleId)
            .compareTo(
              PersonalProfileLayout.displayModuleIds.indexOf(second.moduleId),
            ),
      );
    final hidden = normalized
        .where((item) => !item.isVisible)
        .map((item) => item.moduleId)
        .toList();
    if (widget.projection.local != null &&
        (normalized.length < PersonalProfileLayout.maxModules ||
            hidden.any(PersonalProfileModuleIds.isFavorite))) {
      hidden.insert(0, ProfileFavoriteModules.addAction);
    }
    final tokens = context.tokens;
    if (!widget.editing && visible.isEmpty) {
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Text(
          AppStrings.of(context).text('profile.layout.empty'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editing) ...[
          PersonalProfileLayoutToolbar(
            hiddenModuleIds: hidden,
            onAdd: (moduleId) => _apply(
              context,
              moduleId == ProfileFavoriteModules.addAction
                  ? PersonalProfileLayoutMutation(
                      layout: ProfileFavoriteModules.add(normalized),
                    )
                  : PersonalProfileLayout.show(normalized, moduleId),
            ),
          ),
          SizedBox(height: tokens.space.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) =>
              _buildCanvas(context, constraints, normalized, visible, hidden),
        ),
      ],
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    BoxConstraints constraints,
    List<PersonalProfileModuleLayoutItem> normalized,
    List<PersonalProfileModuleLayoutItem> visible,
    List<String> hidden,
  ) {
    final tokens = context.tokens;
    final gap = tokens.space.sm;
    final cellWidth =
        (constraints.maxWidth - gap * (PersonalProfileLayout.columnCount - 1)) /
        PersonalProfileLayout.columnCount;
    final occupied = PersonalProfileLayout.occupiedCells(normalized);
    final rowCount =
        visible.fold<int>(1, (rows, item) {
          final itemRows =
              item.position ~/ PersonalProfileLayout.columnCount + 1;
          return itemRows > rows ? itemRows : rows;
        }) +
        (widget.editing ? 1 : 0);
    if (constraints.maxWidth < 700) {
      final ordered = visible.toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      return Column(
        key: const Key('profile-module-grid'),
        children: [
          for (final item in ordered)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: SizedBox(
                height: PersonalProfileModuleIds.isFavorite(item.moduleId)
                    ? 65 +
                          item.size.span *
                              MediaQuery.textScalerOf(context).scale(110)
                    : _cellHeight * 1.6,
                child: KeyedSubtree(
                  key: Key('profile-module-${item.moduleId}'),
                  child: _buildModule(context, normalized, item),
                ),
              ),
            ),
        ],
      );
    }
    final height = rowCount * _cellHeight + (rowCount - 1) * gap;

    return KeyedSubtree(
      key: const Key('profile-module-grid'),
      child: SizedBox(
        key: _canvasKey,
        height: height,
        child: Stack(
          children: [
            if (widget.editing)
              for (
                var position = 0;
                position < rowCount * PersonalProfileLayout.columnCount;
                position++
              )
                if (position >= occupied.length || !occupied[position])
                  _positioned(
                    context,
                    position: position,
                    span: 1,
                    cellWidth: cellWidth,
                    gap: gap,
                    child: PersonalProfileEmptyGridCell(
                      position: position,
                      hiddenModuleIds: hidden,
                      onAdd: (moduleId) => _apply(
                        context,
                        moduleId == ProfileFavoriteModules.addAction
                            ? PersonalProfileLayoutMutation(
                                layout: ProfileFavoriteModules.add(normalized),
                              )
                            : PersonalProfileLayout.show(
                                normalized,
                                moduleId,
                                requestedPosition: position,
                              ),
                      ),
                    ),
                  ),
            for (final item in visible)
              _positioned(
                context,
                key: ValueKey('profile-positioned-${item.moduleId}'),
                position: item.position,
                span: item.size.span,
                cellWidth: cellWidth,
                gap: gap,
                child: KeyedSubtree(
                  key: Key('profile-module-${item.moduleId}'),
                  child: _buildDraggableModule(
                    context,
                    normalized,
                    item,
                    width:
                        cellWidth * item.size.span + gap * (item.size.span - 1),
                  ),
                ),
              ),
            if (_dragPointerInside && _dragPreviewPosition != null)
              _positioned(
                context,
                key: ValueKey('profile-drop-position-${_dragPreviewPosition!}'),
                position: _dragPreviewPosition!,
                span: _draggedModuleSpan(normalized),
                cellWidth: cellWidth,
                gap: gap,
                child: const PersonalProfileGridDropPreview(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _positioned(
    BuildContext context, {
    Key? key,
    required int position,
    required int span,
    required double cellWidth,
    required double gap,
    required Widget child,
  }) {
    final row = position ~/ PersonalProfileLayout.columnCount;
    final column = position % PersonalProfileLayout.columnCount;
    return Positioned.directional(
      key: key,
      textDirection: Directionality.of(context),
      start: column * (cellWidth + gap),
      top: row * (_cellHeight + gap),
      width: cellWidth * span + gap * (span - 1),
      height: _cellHeight,
      child: child,
    );
  }

  Widget _buildDraggableModule(
    BuildContext context,
    List<PersonalProfileModuleLayoutItem> normalized,
    PersonalProfileModuleLayoutItem item, {
    required double width,
  }) {
    final child = _buildModule(context, normalized, item);
    if (!widget.editing) {
      return child;
    }
    return Draggable<String>(
      key: Key('profile-module-drag-${item.moduleId}'),
      data: item.moduleId,
      dragAnchorStrategy: childDragAnchorStrategy,
      maxSimultaneousDrags: 1,
      onDragStarted: () => _startDrag(item.moduleId),
      onDragUpdate: (details) =>
          _updateDragFromGlobal(item.moduleId, details.globalPosition),
      onDragEnd: (_) => _finishDrag(item.moduleId),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          height: _cellHeight,
          child: Opacity(opacity: 0.94, child: child),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.58, child: child),
      child: MouseRegion(cursor: SystemMouseCursors.move, child: child),
    );
  }

  Widget _buildModule(
    BuildContext context,
    List<PersonalProfileModuleLayoutItem> normalized,
    PersonalProfileModuleLayoutItem item,
  ) {
    final controls = widget.editing
        ? PersonalProfileModuleControls(
            item: item,
            onEditPositions:
                !widget.visitorView &&
                    item.moduleId == PersonalProfileModuleIds.skilledRoles
                ? widget.onEditPositions
                : null,
            onEditShips:
                PersonalProfileModuleIds.isFavorite(item.moduleId) &&
                    widget.projection.local != null
                ? () => _editShips(item, normalized)
                : null,
            onSizeSelected: (size) => _apply(
              context,
              PersonalProfileLayout.resize(normalized, item.moduleId, size),
            ),
            onRemove: () => _apply(
              context,
              PersonalProfileLayout.hide(normalized, item.moduleId),
            ),
          )
        : null;
    final ids = item.favoriteShipIds;
    final choices =
        widget.projection.local?.choices ?? widget.projection.favoriteShips;
    final byId = {
      for (final ship in [...widget.projection.favoriteShips, ...choices])
        ship.identity.runtimeId: ship,
    };
    return switch (PersonalProfileModuleIds.typeOf(item.moduleId)) {
      PersonalProfileModuleIds.favoriteShips => PersonalProfileFavoriteShips(
        ships: ids == null
            ? widget.projection.favoriteShips
            : [for (final id in ids) ?byId[id]],
        hangarAvailable: widget.projection.hangarSummary.isAvailable,
        unresolvedCount: ids == null
            ? widget.projection.hangarSummary.unresolvedFavoriteCount
            : ids.where((id) => !byId.containsKey(id)).length,
        span: item.size.span,
        headerTrailing: controls,
      ),
      PersonalProfileModuleIds.hangarSummary => PersonalProfileHangarOverview(
        summary: widget.projection.hangarSummary,
        span: item.size.span,
        headerTrailing: controls,
      ),
      PersonalProfileModuleIds.skilledRoles => PersonalProfilePositionsModule(
        roles: widget.projection.roles,
        participationInterests: widget.projection.participationInterests,
        supportCapabilities: widget.projection.supportCapabilities,
        headerTrailing: controls,
      ),
      _ => const PersonalProfileUnavailableModule(),
    };
  }

  void _apply(BuildContext context, PersonalProfileLayoutMutation mutation) {
    if (mutation.failure == PersonalProfileLayoutFailure.selectionExceedsSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text('profile.favorites.resize'),
          ),
        ),
      );
      return;
    }
    if (mutation.failure == PersonalProfileLayoutFailure.noSpace) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('profile.layout.noSpace')),
        ),
      );
      return;
    }
    if (!PersonalProfileLayout.hasSameLayout(widget.layout, mutation.layout)) {
      widget.onLayoutChanged(mutation.layout);
    }
  }

  void _startDrag(String moduleId) {
    final base = PersonalProfileLayout.normalize(widget.layout);
    setState(() {
      _dragBaseLayout = base;
      _dragPreviewLayout = base;
      _draggedModuleId = moduleId;
      _dragPointerInside = true;
      _dragPreviewPosition = base
          .firstWhere((item) => item.moduleId == moduleId)
          .position;
    });
  }

  void _updateDragFromGlobal(String moduleId, Offset globalPosition) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    final bounds = Offset.zero & renderObject.size;
    if (!bounds.contains(localPosition)) {
      if (_dragPointerInside) {
        setState(() => _dragPointerInside = false);
      }
      return;
    }

    final gap = context.tokens.space.sm;
    final cellWidth =
        (renderObject.size.width -
            gap * (PersonalProfileLayout.columnCount - 1)) /
        PersonalProfileLayout.columnCount;
    final logicalX = Directionality.of(context) == TextDirection.rtl
        ? renderObject.size.width - localPosition.dx
        : localPosition.dx;
    final column = (logicalX / (cellWidth + gap)).floor().clamp(
      0,
      PersonalProfileLayout.columnCount - 1,
    );
    final row = (localPosition.dy / (_cellHeight + gap)).floor().clamp(
      0,
      (renderObject.size.height / (_cellHeight + gap)).ceil() - 1,
    );
    _previewDrag(moduleId, row * PersonalProfileLayout.columnCount + column);
  }

  void _previewDrag(String moduleId, int targetPosition) {
    final base = _dragBaseLayout;
    if (base == null || moduleId != _draggedModuleId) {
      return;
    }
    final mutation = PersonalProfileLayout.move(base, moduleId, targetPosition);
    final resolvedPosition = mutation.layout
        .firstWhere((item) => item.moduleId == moduleId)
        .position;
    if (_dragPointerInside && resolvedPosition == _dragPreviewPosition) {
      return;
    }
    setState(() {
      _dragPointerInside = true;
      _dragPreviewPosition = resolvedPosition;
      _dragPreviewLayout = mutation.layout;
    });
  }

  void _finishDrag(String moduleId) {
    if (!_dragPointerInside) {
      _cancelDrag();
      return;
    }
    _commitDrag(moduleId);
  }

  void _commitDrag(String moduleId) {
    final base = _dragBaseLayout;
    if (base == null || moduleId != _draggedModuleId) {
      return;
    }
    final mutation = PersonalProfileLayoutMutation(
      layout: _dragPreviewLayout ?? base,
    );
    _clearDragState();
    _apply(context, mutation);
  }

  int _draggedModuleSpan(List<PersonalProfileModuleLayoutItem> layout) {
    final moduleId = _draggedModuleId;
    if (moduleId == null) {
      return 1;
    }
    return layout.firstWhere((item) => item.moduleId == moduleId).size.span;
  }

  void _cancelDrag() {
    if (_draggedModuleId == null) {
      return;
    }
    _clearDragState();
  }

  void _clearDragState() {
    setState(() {
      _dragBaseLayout = null;
      _dragPreviewLayout = null;
      _draggedModuleId = null;
      _dragPreviewPosition = null;
      _dragPointerInside = false;
    });
  }

  Future<void> _editShips(
    PersonalProfileModuleLayoutItem item,
    List<PersonalProfileModuleLayoutItem> layout,
  ) async {
    final originalProjection = widget.projection;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<List<String>>(
      context: context,
      builder: (_) => ProfileFavoriteDialog(
        local: originalProjection.local!,
        selected: item.favoriteShipIds ?? const [],
        capacity: item.size.span,
        reserved: ProfileFavoriteModules.reserved(layout, item.moduleId),
      ),
    );
    _selectionRoute = route;
    _selectionNavigator = navigator;
    final result = await navigator.push(route);
    if (identical(_selectionRoute, route)) {
      _selectionRoute = null;
      _selectionNavigator = null;
    }
    if (!mounted ||
        !widget.editing ||
        result == null ||
        !identical(originalProjection, widget.projection)) {
      return;
    }
    final updated = [
      for (final entry in layout)
        entry.moduleId == item.moduleId
            ? entry.copyWith(favoriteShipIds: result)
            : entry,
    ];
    if (ProfileFavoriteModules.valid(updated)) widget.onLayoutChanged(updated);
  }
}
