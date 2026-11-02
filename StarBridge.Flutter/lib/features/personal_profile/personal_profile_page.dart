import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';

import 'package:flutter/foundation.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'personal_profile_editor.dart';
import '../account/account_avatar_editor.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'personal_profile_module.dart';
import 'personal_profile_read_status.dart';
import 'personal_profile_view_state.dart';
import 'personal_profile_draft.dart';
import 'personal_profile_access.dart';
import 'personal_profile_visibility.dart';
import 'personal_profile_visibility_dialog.dart';
import 'personal_profile_wallpaper_backdrop.dart';
import 'personal_profile_wallpaper_catalog.dart';
import 'personal_profile_view.dart';

class PersonalProfilePage extends StatefulWidget {
  const PersonalProfilePage({
    required this.module,
    this.presence,
    this.gameplayTime,
    this.isVisitor = false,
    this.offline = false,
    this.visitorAvatarImageData,
    this.pageToolbar,
    this.viewState,
    this.access,
    super.key,
  });

  final PersonalProfileModule module;
  final PersonalProfileViewState? viewState;
  final PersonalProfileAccess? access;
  final bool isVisitor;
  final bool offline;
  final String? visitorAvatarImageData;

  /// Navigation overlays the wallpaper without reducing its viewport.
  final Widget? pageToolbar;
  final GameplayTimeController? gameplayTime;
  final ValueListenable<ShellChromeProjection>? presence;

  @override
  State<PersonalProfilePage> createState() => _PersonalProfilePageState();
}

class _PersonalProfilePageState extends State<PersonalProfilePage> {
  final ScrollController _scrollController = ScrollController();
  final _editorKey = GlobalKey<PersonalProfileEditorPanelState>();
  PersonalProfileViewState? _view;
  bool _restoringView = false;
  PersonalProfileEditorDraft? _restoredDraft;
  bool _visitorPreview = false;
  bool _editing = false;
  PersonalProfileEditingSession? _editingOwner;
  List<PersonalProfileModuleLayoutItem>? _layoutDraft;
  String? _wallpaperDraft;
  int _wallpaperReadEpoch = 0;
  bool _profileWasRefreshing = false;
  InteractionSource? _refreshIntent;
  InteractionSource _readSource = InteractionSource.programmatic;
  int _readPhase = 0;
  PersonalProfileProjection? _avatarBaseProjection;
  PersonalProfileProjection? _avatarViewProjection;
  String? _avatarViewData;
  StarBridgeDialogRoute<void>? _visibilityRoute;

  void _retireVisibility() {
    retireStarBridgeDialog(_visibilityRoute, includeClosing: true);
  }

  // A presentation-only avatar fallback must not pretend to be a fresh domain
  // projection on every window/theme rebuild. Keep one derived view per actual
  // source value and avatar value; a new module always gets a new view identity.
  PersonalProfileProjection _withAvatar(PersonalProfileProjection projection) {
    final avatar = widget.isVisitor
        ? projection.avatarImageData ?? widget.visitorAvatarImageData
        : projection.local?.accountCallSign == true
        ? projection.avatarImageData ??
              AccountAvatarScope.of(context)?.imageData
        : AccountAvatarScope.of(context)?.imageData ??
              projection.avatarImageData;
    if (!identical(_avatarBaseProjection, projection) ||
        _avatarViewData != avatar ||
        _avatarViewProjection == null) {
      _avatarBaseProjection = projection;
      _avatarViewData = avatar;
      _avatarViewProjection = projection.copyWith(avatarImageData: avatar);
    }
    return _avatarViewProjection!;
  }

  @override
  void initState() {
    super.initState();
    _view = widget.viewState;
    _scrollController.addListener(_rememberView);
    _restoreView();
    _restoreDraft();
    widget.module.projection.addListener(_onProfileChanged);
    _profileWasRefreshing =
        widget.module.projection.value.operation ==
        PersonalProfileOperation.refreshing;
  }

  @override
  void didUpdateWidget(covariant PersonalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moduleChanged = oldWidget.module != widget.module;
    if (moduleChanged ||
        !identical(oldWidget.access, widget.access) ||
        widget.access?.permitsEditing == false) {
      _retireVisibility();
    }
    if (moduleChanged || oldWidget.viewState != widget.viewState) {
      _rememberView();
    }
    if (moduleChanged) {
      _parkDraft(oldWidget.module);
      oldWidget.module.projection.removeListener(_onProfileChanged);
      widget.module.projection.addListener(_onProfileChanged);
      _wallpaperReadEpoch++;
      _readSource = InteractionSource.programmatic;
      _readPhase++;
      _profileWasRefreshing =
          widget.module.projection.value.operation ==
          PersonalProfileOperation.refreshing;
      _avatarBaseProjection = null;
      _avatarViewProjection = null;
      _avatarViewData = null;
      _clearDraft();
      _restoreDraft();
    }
    if (moduleChanged || oldWidget.viewState != widget.viewState) {
      _view = widget.viewState;
      _restoreView();
    }
  }

  void _onProfileChanged() {
    final next = widget.module.projection.value;
    if (next.availability != PersonalProfileAvailability.available ||
        widget.access?.permitsEditing == false) {
      _retireVisibility();
    }
    final refreshing = next.operation == PersonalProfileOperation.refreshing;
    if (next.availability == PersonalProfileAvailability.loading ||
        refreshing && !_profileWasRefreshing) {
      // A fast refresh can finish before loading gets painted. Still retire the
      // previous image failure and its bounded retry state for this new read.
      _wallpaperReadEpoch++;
      _readSource = _refreshIntent ?? InteractionSource.programmatic;
      _readPhase++;
    }
    _profileWasRefreshing = refreshing;
    if (_editing &&
        widget.module is PersonalProfileDraftSession &&
        !(widget.module as PersonalProfileDraftSession).editingLeaseActive) {
      setState(_clearDraft);
    }
    if (!_editing &&
        next.availability == PersonalProfileAvailability.available) {
      _restoreDraft();
      if (_editing) setState(() {});
    }
    if (widget.module.projection.value.availability !=
            PersonalProfileAvailability.available &&
        (_editing || _visitorPreview)) {
      // An invalidated account may refresh before the next rendered frame.
      // Clear the old editor and grid/background drafts synchronously.
      _parkDraft(widget.module);
      setState(_clearDraft);
    }
  }

  @override
  void deactivate() {
    // Capture values before descendant GlobalKeys leave the active tree.
    // The original module decides whether its editing lease still admits them.
    if (_editing) {
      _restoredDraft =
          _editorKey.currentState?.captureDraft() ?? _restoredDraft;
    }
    super.deactivate();
  }

  void _rememberView() {
    final view = _view;
    if (view == null || !view.current || _restoringView) return;
    view.visitorPreview = _visitorPreview;
    if (_scrollController.hasClients) {
      view.scrollOffset = _scrollController.offset;
    }
  }

  void _restoreView() {
    final view = _view;
    if (view == null || !view.current) return;
    _visitorPreview = view.visitorPreview;
    _restoringView = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(_view, view) &&
          view.current &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(
          view.scrollOffset.clamp(
            0,
            _scrollController.position.maxScrollExtent,
          ),
        );
        _restoringView = false;
      }
    });
  }

  void _parkDraft(PersonalProfileModule module) {
    if (!_editing || module is! PersonalProfileDraftSession) return;
    final draft = _editorKey.currentState?.captureDraft() ?? _restoredDraft;
    if (draft != null &&
        (module as PersonalProfileDraftSession).keepEditorDraft(draft)) {
      _editingOwner = null;
    }
  }

  void _restoreDraft() {
    final module = widget.module;
    if (_editing ||
        widget.access?.permitsEditing == false ||
        module is! PersonalProfileDraftSession) {
      return;
    }
    final draft = (module as PersonalProfileDraftSession).takeEditorDraft();
    if (draft == null) return;
    _editing = true;
    _restoredDraft = draft;
    _layoutDraft = draft.edit.moduleLayout;
    _wallpaperDraft = draft.edit.wallpaperId;
    _editingOwner = module is PersonalProfileEditingSession
        ? module as PersonalProfileEditingSession
        : null;
  }

  void _clearDraft() {
    _restoredDraft = null;
    _editing = false;
    _visitorPreview = false;
    _layoutDraft = null;
    _wallpaperDraft = null;
    _releaseEditing();
  }

  void _releaseEditing() {
    final owner = _editingOwner;
    _editingOwner = null;
    owner?.endEditing();
  }

  Future<PersonalProfileActionResult> _refresh() {
    // Provenance of this synchronous admission only. Deferred/background reads
    // must not inherit an earlier keyboard command; the module still owns them.
    _refreshIntent = currentStarBridgeActivationSource;
    try {
      return widget.module.refresh();
    } finally {
      _refreshIntent = null;
    }
  }

  Future<void> _editVisibility() async {
    final module = widget.module;
    if (widget.access?.permitsEditing == false ||
        module is! ProfileVisibilityAccess) {
      return;
    }
    final owner = module is PersonalProfileEditingSession
        ? module as PersonalProfileEditingSession
        : null;
    if (owner != null && !owner.beginEditing()) return;
    final access = widget.access;
    try {
      await showStarBridgeDialog<void>(
        context,
        source: currentStarBridgeActivationSource,
        barrierDismissible: false,
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        onRouteCreated: (route) {
          _visibilityRoute = route;
          unawaited(
            route.completed.then((_) {
              if (identical(_visibilityRoute, route)) _visibilityRoute = null;
            }),
          );
        },
        builder: (_) => Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: SafeArea(
            child: StarBridgeDialogOwnerGuard(
              isCurrent: () =>
                  mounted &&
                  identical(widget.module, module) &&
                  identical(widget.access, access) &&
                  widget.access?.permitsEditing != false &&
                  (module is! PersonalProfileDraftSession ||
                      (module as PersonalProfileDraftSession)
                          .editingLeaseActive) &&
                  module.projection.value.availability ==
                      PersonalProfileAvailability.available,
              child: ProfileVisibilityDialog(
                access: access?.visibility ?? module as ProfileVisibilityAccess,
              ),
            ),
          ),
        ),
      );
    } finally {
      owner?.endEditing();
    }
  }

  @override
  void dispose() {
    _retireVisibility();
    _rememberView();
    _parkDraft(widget.module);
    widget.module.projection.removeListener(_onProfileChanged);
    _releaseEditing();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<PersonalProfileProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        if (widget.access?.permitsEditing == false) {
          projection = projection.copyWith(allowEditing: false);
        }
        projection = _withAvatar(projection);
        final hasProfile =
            projection.availability == PersonalProfileAvailability.available;
        final ownerWallpaperId = _editing
            ? _wallpaperDraft ?? projection.wallpaperId
            : projection.wallpaperId;
        final wallpaperId =
            hasProfile && !(_visitorPreview && !projection.isPublic)
            ? ownerWallpaperId
            : PersonalProfileWallpaperCatalog.noneId;
        final wallpaper = PersonalProfileWallpaperCatalog.resolve(wallpaperId);
        final content = Stack(
          key: const Key('profile-page-wallpaper-stack'),
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: PersonalProfileWallpaperBackdrop(
                key: ValueKey(_wallpaperReadEpoch),
                wallpaperId: wallpaperId,
              ),
            ),
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsetsDirectional.fromSTEB(
                  tokens.space.xl,
                  widget.pageToolbar == null ? tokens.space.lg : 64,
                  tokens.space.xl,
                  tokens.space.xxl,
                ),
                child: Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: tokens.density.contentMaxWidth,
                    ),
                    child: switch (projection.availability) {
                      PersonalProfileAvailability.loading =>
                        PersonalProfileLoadingView(
                          key: ValueKey(('profile-load', _readPhase)),
                          source: _readSource,
                        ),
                      PersonalProfileAvailability.signedOut =>
                        const PersonalProfileSignedOutView(),
                      PersonalProfileAvailability.unavailable =>
                        PersonalProfileUnavailableView(
                          failureKey:
                              projection.failureKey ??
                              'profile.error.unavailable',
                          onRetry: _refresh,
                          source: _readSource,
                          retrying:
                              projection.operation ==
                              PersonalProfileOperation.refreshing,
                        ),
                      PersonalProfileAvailability.available => PersonalProfileView(
                        readSource: _readSource,
                        readPhase: _readPhase,
                        editorKey: _editorKey,
                        onVisibility:
                            widget.offline ||
                                !projection.canEdit ||
                                widget.module is! ProfileVisibilityAccess
                            ? null
                            : () => unawaited(_editVisibility()),
                        projection: projection,
                        presence: widget.presence,
                        gameplayTime: widget.gameplayTime,
                        visitorPreview: _visitorPreview,
                        isVisitor: widget.isVisitor,
                        offline: widget.offline,
                        editing: _editing,
                        layout: _editing
                            ? _layoutDraft ??
                                  PersonalProfileLayout.normalize(
                                    projection.moduleLayout,
                                  )
                            : PersonalProfileLayout.normalize(
                                projection.moduleLayout,
                              ),
                        onPreview: () => setState(() => _visitorPreview = true),
                        onExitPreview: () =>
                            setState(() => _visitorPreview = false),
                        onEdit: () {
                          if (widget.access?.permitsEditing == false) return;
                          final module = widget.module;
                          if (module is PersonalProfileEditingSession) {
                            if (!(module as PersonalProfileEditingSession)
                                .beginEditing()) {
                              return;
                            }
                            _editingOwner =
                                module as PersonalProfileEditingSession;
                          }
                          setState(() {
                            _editing = true;
                            _wallpaperDraft = projection.wallpaperId;
                            _layoutDraft = PersonalProfileLayout.normalize(
                              projection.moduleLayout,
                            );
                          });
                        },
                        onCancelEdit: () => setState(_clearDraft),
                        onSaved: () => setState(_clearDraft),
                        onWallpaperChanged: (wallpaperId) => setState(() {
                          _wallpaperDraft = wallpaperId;
                        }),
                        onLayoutChanged: (layout) => setState(() {
                          _layoutDraft = layout;
                        }),
                        initialDraft: _restoredDraft,
                        ownerRequiresReload:
                            widget.module is PersonalProfileDraftSession
                            ? (widget.module as PersonalProfileDraftSession)
                                  .draftRequiresReload
                            : null,
                        onSave: widget.access?.save ?? widget.module.save,
                        onRefresh: () => unawaited(_refresh()),
                        onEditPositions: () =>
                            _editorKey.currentState?.editPositions(),
                      ),
                    },
                  ),
                ),
              ),
            ),
            if (widget.pageToolbar != null)
              PositionedDirectional(
                start: tokens.space.sm,
                end: tokens.space.sm,
                top: tokens.space.sm,
                height: 40,
                child: widget.pageToolbar!,
              ),
            if (wallpaper.requiresCigFankitNotice)
              PositionedDirectional(
                end: tokens.space.xl,
                bottom: tokens.space.lg,
                child: const SafeArea(
                  child: CigFankitNoticeButton(
                    key: Key('profile-cig-fankit-notice'),
                  ),
                ),
              ),
          ],
        );
        return LoadingContentProbe(
          route: '/profile',
          status: switch (projection.availability) {
            PersonalProfileAvailability.loading => LoadingContentStatus.waiting,
            PersonalProfileAvailability.available =>
              projection.operation == PersonalProfileOperation.refreshing ||
                      projection.refreshFailed
                  ? LoadingContentStatus.partial
                  : LoadingContentStatus.data,
            PersonalProfileAvailability.signedOut =>
              LoadingContentStatus.unavailable,
            PersonalProfileAvailability.unavailable =>
              LoadingContentStatus.unavailable,
          },
          items: hasProfile ? 1 : 0,
          child: content,
        );
      },
    );
  }
}
