import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/native_viewport_visibility.dart';
import 'personal_profile_favorite_ships.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_favorite_dialog.dart';
import 'personal_profile_grid_chrome.dart';
import 'personal_profile_hangar_overview.dart';
import 'personal_profile_hangar_showcase.dart';
import 'personal_profile_achievement_showcase.dart';
import 'personal_profile_showcase_items.dart';
import 'personal_profile_showcases.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_controls.dart';
import 'personal_profile_showcase_bodies.dart';
import 'personal_profile_showcase_frame.dart';
import 'personal_profile_module_surface.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class PersonalProfileModuleGrid extends StatefulWidget {
  const PersonalProfileModuleGrid({
    required this.projection,
    required this.visitorView,
    required this.editing,
    required this.layout,
    required this.onLayoutChanged,
    this.onEditPositions,
    this.isVisitor = false,
    this.includeLocalTime = false,
    this.gameplayTime,
    this.achievementPicks,
    this.onAchievementPicksChanged,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool visitorView;

  /// A real visitor (not the owner's preview): only server-given showcases.
  final bool isVisitor;
  final bool includeLocalTime;
  final GameplayTimeController? gameplayTime;

  /// The editing draft of the owner's achievement picks.
  final List<String>? achievementPicks;
  final ValueChanged<List<String>>? onAchievementPicksChanged;
  final bool editing;
  final List<PersonalProfileModuleLayoutItem> layout;
  final ValueChanged<List<PersonalProfileModuleLayoutItem>> onLayoutChanged;
  final VoidCallback? onEditPositions;

  @override
  State<PersonalProfileModuleGrid> createState() =>
      _PersonalProfileModuleGridState();
}

class _PersonalProfileModuleGridState extends State<PersonalProfileModuleGrid> {
  StarBridgeDialogRoute<List<String>>? _selectionRoute;
  NavigatorState? _selectionNavigator;
  StarBridgeDialogRoute<void>? _detailsRoute;
  String? _detailsModuleId;
  PersonalProfileShipSummary? _detailsShip;

  /// Data from a visitor read. The owner's own page shown read-only in the
  /// menu is isVisitor too, but keeps the owner page's matching and hints.
  bool get _visitorData => widget.isVisitor && !widget.projection.allowEditing;

  String _shipLookupId(String id) => _visitorData ? id.toLowerCase() : id;

  Map<String, PersonalProfileShipSummary> get _shipsById => {
    for (final ship in widget.projection.favoriteShips)
      _shipLookupId(ship.identity.runtimeId): ship,
    if (!_visitorData)
      for (final ship in widget.projection.local?.choices ?? const [])
        ship.identity.runtimeId: ship,
  };

  /// Ship ID → model, for the one-ship-per-model rule (user 11-07).
  Map<String, String> get _models => ProfileFavoriteModules.modelsOf([
    ...widget.projection.favoriteShips,
    ...?widget.projection.local?.retainedChoices,
    ...widget.projection.local?.choices ?? const [],
  ]);

  List<PersonalProfileShipSummary> _shipsFor(
    PersonalProfileModuleLayoutItem item,
    Map<String, PersonalProfileShipSummary> byId,
  ) => _usesFlatFavorites(item)
      ? widget.projection.favoriteShips
      // The module's ships, then the page's 4th showcase ship (1 + 3).
      : [
          for (final id in PersonalProfileFavoriteExtra.picked(item))
            ?byId[_shipLookupId(id)],
        ];

  bool _usesFlatFavorites(PersonalProfileModuleLayoutItem item) {
    // Visitor reads give every module of a multi-module page its own IDs
    // (visitorFlatFavorites), so a module without IDs is the flat format here,
    // also for the owner's own page shown read-only in the menu.
    if (item.favoriteShipIds == null) return true;
    if (widget.isVisitor ||
        widget.editing ||
        widget.projection.local?.showLocalFavoriteShips != true) {
      return false;
    }
    // The flat local selection has one card. Keep the saved layout and the
    // editor's selection IDs intact while that selection is pending.
    return ProfileFavoriteModules.firstVisibleId(widget.layout) ==
        item.moduleId;
  }

  bool _displaysShip(String moduleId, PersonalProfileShipSummary ship) {
    final item = PersonalProfileLayout.normalize(widget.layout)
        .where((item) => item.moduleId == moduleId && item.isVisible)
        .firstOrNull;
    return item != null &&
        _shipsFor(item, _shipsById).any((current) => identical(current, ship));
  }

  void _closeDetails() {
    final route = _detailsRoute;
    _detailsRoute = null;
    _detailsModuleId = null;
    _detailsShip = null;
    retireStarBridgeDialog(route);
  }

  Future<void> _viewShip(
    BuildContext caller,
    String moduleId,
    PersonalProfileShipSummary ship,
    InteractionSource source,
  ) async {
    if (!caller.mounted ||
        _detailsRoute?.isActive == true ||
        !NativeViewportScope.isActive(context) ||
        !_displaysShip(moduleId, ship)) {
      return;
    }
    late StarBridgeDialogRoute<void> route;
    await showProfileShipDataDialog(
      caller,
      ship,
      source: source,
      onRouteCreated: (created) {
        _detailsRoute = route = created;
        _detailsModuleId = moduleId;
        _detailsShip = ship;
      },
    );
    if (identical(_detailsRoute, route)) {
      _detailsRoute = null;
      _detailsModuleId = null;
      _detailsShip = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!NativeViewportScope.isActive(context)) {
      _closeDetails();
    }
  }

  @override
  void didUpdateWidget(covariant PersonalProfileModuleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.projection, widget.projection)) {
      _closeSelection();
      _closeDetails();
    } else if (_detailsShip case final ship? when _detailsModuleId != null) {
      if (!_displaysShip(_detailsModuleId!, ship)) _closeDetails();
    }
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
    _closeDetails();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = PersonalProfileLayout.singleColumn(widget.layout);
    final visible = normalized.where((item) => item.isVisible).toList()
      ..sort((first, second) => first.position.compareTo(second.position));
    final hidden = normalized
        .where((item) => !item.isVisible)
        .map((item) => item.moduleId)
        .toList();
    if (widget.projection.local != null) {
      if (ProfileFavoriteModules.canAdd(normalized) ||
          hidden.any(PersonalProfileModuleIds.isFavorite)) {
        hidden.insert(0, ProfileFavoriteModules.addAction);
      } else if (ProfileFavoriteModules.count(normalized) >=
          ProfileFavoriteModules.maxModules) {
        hidden.insert(0, ProfileFavoriteModules.limitNotice);
      }
    }
    final tokens = context.tokens;
    // A showcase with nothing for this viewer is skipped by the column; with
    // playtime gone to the rail (user 11-11) a page may have nothing else, and
    // then the empty-page text must still show.
    bool showsNothing(PersonalProfileModuleLayoutItem item) =>
        switch (item.moduleId) {
          PersonalProfileShowcaseIds.tradeCard =>
            widget.projection.publicFacts == null,
          // A visitor's list comes from the server; the owner's needs the
          // local achievements scope, which an offline page does not have.
          PersonalProfileShowcaseIds.achievements =>
            widget.isVisitor
                ? widget.projection.showcaseData.publicAchievements?.isEmpty ??
                      true
                : ProfileAchievementsScope.of(context) == null,
          _ => false,
        };
    if (!widget.editing && visible.every(showsNothing)) {
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Text(
          AppStrings.of(context).text(
            widget.visitorView
                ? 'profile.visitor.layoutEmpty'
                : 'profile.layout.empty',
          ),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      );
    }
    void add(String moduleId) => _apply(
      context,
      moduleId == ProfileFavoriteModules.addAction
          ? PersonalProfileLayoutMutation(
              layout: ProfileFavoriteModules.add(normalized),
            )
          : PersonalProfileLayout.show(
              normalized,
              moduleId,
              requestedPosition:
                  visible.length * PersonalProfileLayout.columnCount,
            ),
    );
    final gap = tokens.space.md;
    // The grid is always the single column, also when built on its own.
    return ProfileShowcaseScope(
      child: _column(context, normalized, visible, hidden, add, gap),
    );
  }

  Widget _column(
    BuildContext context,
    List<PersonalProfileModuleLayoutItem> normalized,
    List<PersonalProfileModuleLayoutItem> visible,
    List<String> hidden,
    ValueChanged<String> add,
    double gap,
  ) {
    return Column(
      key: const Key('profile-module-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editing) ...[
          PersonalProfileLayoutToolbar(hiddenModuleIds: hidden, onAdd: add),
          SizedBox(height: gap),
        ],
        for (final (index, child) in [
          for (var index = 0; index < visible.length; index++)
            if (_buildModule(
                  context,
                  normalized,
                  visible[index],
                  first: index == 0,
                  last: index == visible.length - 1,
                )
                case final child?)
              KeyedSubtree(
                key: Key('profile-module-${visible[index].moduleId}'),
                child: child,
              ),
        ].indexed) ...[if (index > 0) SizedBox(height: gap), child],
      ],
    );
  }

  Widget? _buildModule(
    BuildContext context,
    List<PersonalProfileModuleLayoutItem> normalized,
    PersonalProfileModuleLayoutItem item, {
    bool first = false,
    bool last = false,
  }) {
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
                : item.moduleId == PersonalProfileShowcaseIds.achievements &&
                      widget.onAchievementPicksChanged != null
                ? _pickAchievements
                : null,
            onMoveUp: first
                ? null
                : () => _apply(
                    context,
                    PersonalProfileLayout.step(normalized, item.moduleId, -1),
                  ),
            onMoveDown: last
                ? null
                : () => _apply(
                    context,
                    PersonalProfileLayout.step(normalized, item.moduleId, 1),
                  ),
            onRemove: () => _apply(
              context,
              PersonalProfileLayout.hide(normalized, item.moduleId),
            ),
          )
        : null;
    final ids = item.favoriteShipIds;
    final byId = _shipsById;
    return switch (PersonalProfileModuleIds.typeOf(item.moduleId)) {
      PersonalProfileModuleIds.favoriteShips => PersonalProfileFavoriteShips(
        ships: _shipsFor(item, byId),
        hangarAvailable: widget.projection.hangarSummary.isAvailable,
        unresolvedCount: _usesFlatFavorites(item)
            ? widget.projection.hangarSummary.unresolvedFavoriteCount
            : (_visitorData && widget.projection.hangarSummary.isAvailable
                      ? PersonalProfileFavoriteExtra.picked(item)
                      : ids!)
                  .where((id) => !byId.containsKey(_shipLookupId(id)))
                  .length,
        showPartialPending: _visitorData,
        span: item.size.span,
        headerTrailing: controls,
        onViewShipData: (caller, ship, source) =>
            _viewShip(caller, item.moduleId, ship, source),
      ),
      PersonalProfileModuleIds.hangarSummary
          when widget.projection.hangarSummary.isAvailable =>
        PersonalProfileModuleSurface(
          icon: StarBridgeIconSemantic.hangar,
          titleKey: 'profile.hangar.title',
          headerTrailing: controls,
          child: ProfileHangarShowcase(
            summary: widget.projection.hangarSummary,
          ),
        ),
      PersonalProfileModuleIds.hangarSummary => PersonalProfileHangarOverview(
        summary: widget.projection.hangarSummary,
        span: PersonalProfileModuleSize.three.span,
        headerTrailing: controls,
      ),
      PersonalProfileModuleIds.skilledRoles => PersonalProfileModuleSurface(
        icon: StarBridgeIconSemantic.operation,
        titleKey: 'profile.position.title',
        headerTrailing: controls,
        child: ProfileRolesShowcase(projection: widget.projection),
      ),
      _ when PersonalProfileShowcaseIds.isShowcaseOnly(item.moduleId) =>
        buildProfileShowcaseItem(
          context,
          id: item.moduleId,
          projection: widget.projection,
          editing: widget.editing,
          isVisitor: widget.isVisitor,
          visitorView: widget.visitorView,
          includeLocalTime: widget.includeLocalTime,
          gameplayTime: widget.gameplayTime,
          achievementPicks: widget.achievementPicks,
          controls: controls,
        ),
      _ => const PersonalProfileUnavailableModule(),
    };
  }

  Future<void> _pickAchievements() async {
    final scope = ProfileAchievementsScope.of(context);
    final collection = scope?.collection.value;
    if (collection == null || !collection.isReady) return;
    final result = await showProfileAchievementPicker(
      context,
      collection: collection,
      selected: widget.achievementPicks ?? const [],
    );
    if (mounted && widget.editing && result != null) {
      widget.onAchievementPicksChanged?.call(result);
    }
  }

  void _apply(BuildContext context, PersonalProfileLayoutMutation mutation) {
    if (mutation.failure == PersonalProfileLayoutFailure.selectionExceedsSize) {
      showStarBridgeSnackBar(
        context,
        starBridgeTimedSnackBar(
          content: Text(
            AppStrings.of(context).text('profile.favorites.resize'),
          ),
        ),
        tone: ActionTone.danger,
      );
      return;
    }
    if (mutation.failure == PersonalProfileLayoutFailure.noSpace) {
      showStarBridgeSnackBar(
        context,
        starBridgeTimedSnackBar(
          content: Text(AppStrings.of(context).text('profile.layout.noSpace')),
        ),
        tone: ActionTone.danger,
      );
      return;
    }
    final layout = PersonalProfileLayout.singleColumn(mutation.layout);
    if (!PersonalProfileLayout.hasSameLayout(widget.layout, layout)) {
      _emit(layout);
    }
  }

  /// Every layout edit leaves here, so the 4th-ship slot always sits where
  /// the current layout puts it, not where the read put it.
  void _emit(List<PersonalProfileModuleLayoutItem> layout) =>
      widget.onLayoutChanged(
        PersonalProfileFavoriteExtra.reattach(
          layout,
          each: widget.projection.showcaseData.favoriteExtrasEach,
        ),
      );

  Future<void> _editShips(
    PersonalProfileModuleLayoutItem item,
    List<PersonalProfileModuleLayoutItem> layout,
  ) async {
    if (_selectionRoute?.isActive == true) return;
    final originalProjection = widget.projection;
    final navigator = Navigator.of(context, rootNavigator: true);
    late StarBridgeDialogRoute<List<String>> route;
    final result = await showStarBridgeDialog<List<String>>(
      context,
      onRouteCreated: (created) {
        route = created;
        _selectionRoute = created;
        _selectionNavigator = navigator;
      },
      builder: (_) => ProfileFavoriteDialog(
        local: originalProjection.local!,
        selected: PersonalProfileFavoriteExtra.picked(item),
        // No cell size to fit any more: every module holds the most ships;
        // the showcase takes a 4th only where the HK page holds it.
        capacity: PersonalProfileFavoriteExtra.capacity(item),
        reserved: ProfileFavoriteModules.reserved(
          layout,
          item.moduleId,
          models: _models,
        ),
      ),
    );
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
            ? PersonalProfileFavoriteExtra.apply(entry, result)
            : entry,
    ];
    if (ProfileFavoriteModules.valid(updated, models: _models)) _emit(updated);
  }
}
