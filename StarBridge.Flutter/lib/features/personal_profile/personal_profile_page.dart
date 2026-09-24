import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';

import 'package:flutter/foundation.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_editor.dart';
import '../account/account_avatar_editor.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_identity_header.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module.dart';
import 'personal_profile_visibility.dart';
import 'personal_profile_visibility_dialog.dart';
import 'personal_profile_module_grid.dart';
import 'personal_profile_summary.dart';
import 'personal_profile_wallpaper_backdrop.dart';
import 'personal_profile_wallpaper_catalog.dart';

class PersonalProfilePage extends StatefulWidget {
  const PersonalProfilePage({
    required this.module,
    this.presence,
    this.gameplayTime,
    this.isVisitor = false,
    this.visitorAvatarImageData,
    this.pageToolbar,
    super.key,
  });

  final PersonalProfileModule module;
  final bool isVisitor;
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
  bool _visitorPreview = false;
  bool _editing = false;
  List<PersonalProfileModuleLayoutItem>? _layoutDraft;
  String? _wallpaperDraft;

  @override
  void initState() {
    super.initState();
    widget.module.projection.addListener(_onProfileChanged);
  }

  @override
  void didUpdateWidget(covariant PersonalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      oldWidget.module.projection.removeListener(_onProfileChanged);
      widget.module.projection.addListener(_onProfileChanged);
      _clearDraft();
    }
  }

  void _onProfileChanged() {
    if (widget.module.projection.value.availability !=
            PersonalProfileAvailability.available &&
        (_editing || _visitorPreview)) {
      // An invalidated account may refresh before the next rendered frame.
      // Clear the old editor and grid/background drafts synchronously.
      setState(_clearDraft);
    }
  }

  void _clearDraft() {
    _editing = false;
    _visitorPreview = false;
    _layoutDraft = null;
    _wallpaperDraft = null;
  }

  @override
  void dispose() {
    widget.module.projection.removeListener(_onProfileChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<PersonalProfileProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        if (!widget.isVisitor) {
          projection = projection.copyWith(
            avatarImageData: AccountAvatarScope.of(context)?.imageData,
          );
        } else {
          projection = projection.copyWith(
            avatarImageData:
                widget.visitorAvatarImageData ?? projection.avatarImageData,
          );
        }
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
        return Stack(
          key: const Key('profile-page-wallpaper-stack'),
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: PersonalProfileWallpaperBackdrop(wallpaperId: wallpaperId),
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
                        const _LoadingView(),
                      PersonalProfileAvailability.signedOut =>
                        const _SignedOutView(),
                      PersonalProfileAvailability.unavailable =>
                        _UnavailableView(
                          failureKey:
                              projection.failureKey ??
                              'profile.error.unavailable',
                          onRetry: widget.module.refresh,
                          retrying:
                              projection.operation ==
                              PersonalProfileOperation.refreshing,
                        ),
                      PersonalProfileAvailability.available => _ProfileView(
                        editorKey: _editorKey,
                        onVisibility: widget.module is! ProfileVisibilityAccess
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => ProfileVisibilityDialog(
                                  access:
                                      widget.module as ProfileVisibilityAccess,
                                ),
                              ),
                        projection: projection,
                        presence: widget.presence,
                        gameplayTime: widget.gameplayTime,
                        visitorPreview: _visitorPreview,
                        isVisitor: widget.isVisitor,
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
                        onEdit: () => setState(() {
                          _editing = true;
                          _wallpaperDraft = projection.wallpaperId;
                          _layoutDraft = PersonalProfileLayout.normalize(
                            projection.moduleLayout,
                          );
                        }),
                        onCancelEdit: () => setState(() {
                          _editing = false;
                          _wallpaperDraft = null;
                          _layoutDraft = null;
                        }),
                        onSaved: () => setState(() {
                          _editing = false;
                          _wallpaperDraft = null;
                          _layoutDraft = null;
                        }),
                        onWallpaperChanged: (wallpaperId) => setState(() {
                          _wallpaperDraft = wallpaperId;
                        }),
                        onLayoutChanged: (layout) => setState(() {
                          _layoutDraft = layout;
                        }),
                        onSave: widget.module.save,
                        onRefresh: () => unawaited(widget.module.refresh()),
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
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: tokens.space.md),
          Text(strings.text('profile.loading')),
        ],
      ),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.profile,
            size: tokens.icons.large,
            color: tokens.colors.accent,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('profile.signedOut.title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('profile.signedOut.body'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({
    required this.failureKey,
    required this.onRetry,
    required this.retrying,
  });

  final String failureKey;
  final Future<PersonalProfileActionResult> Function() onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('profile-unavailable'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.large,
            color: tokens.colors.warning,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('profile.unavailable.title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text(failureKey),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.md),
          OutlinedButton.icon(
            key: const Key('profile-retry'),
            onPressed: retrying ? null : () => unawaited(onRetry()),
            icon: retrying
                ? SizedBox.square(
                    dimension: tokens.icons.small,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            label: Text(
              strings.text(
                retrying ? 'profile.retrying' : 'profile.unavailable.retry',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.editorKey,
    required this.onVisibility,
    required this.projection,
    this.presence,
    this.gameplayTime,
    required this.visitorPreview,
    this.isVisitor = false,
    required this.editing,
    required this.layout,
    required this.onPreview,
    required this.onExitPreview,
    required this.onEdit,
    required this.onEditPositions,
    required this.onCancelEdit,
    required this.onSaved,
    required this.onSave,
    required this.onRefresh,
    required this.onLayoutChanged,
    required this.onWallpaperChanged,
  });

  final PersonalProfileProjection projection;
  final VoidCallback? onVisibility;
  final GameplayTimeController? gameplayTime;
  final ValueListenable<ShellChromeProjection>? presence;
  final bool visitorPreview;
  final bool isVisitor;
  final bool editing;
  final List<PersonalProfileModuleLayoutItem> layout;
  final VoidCallback onPreview;
  final VoidCallback onExitPreview;
  final VoidCallback onEdit;
  final VoidCallback onEditPositions;
  final GlobalKey<PersonalProfileEditorPanelState> editorKey;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaved;
  final VoidCallback onRefresh;
  final Future<PersonalProfileActionResult> Function(PersonalProfileEdit edit)
  onSave;
  final ValueChanged<List<PersonalProfileModuleLayoutItem>> onLayoutChanged;
  final ValueChanged<String> onWallpaperChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visitorPreview) ...[
          PersonalProfileVisitorPreviewBanner(onExit: onExitPreview),
          SizedBox(height: tokens.space.md),
        ],
        if (visitorPreview && !projection.isPublic)
          const _PrivateVisitorView()
        else ...[
          if (editing)
            PersonalProfileEditorPanel(
              key: editorKey,
              projection: projection,
              onSave: onSave,
              onCancel: onCancelEdit,
              onSaved: onSaved,
              moduleLayout: layout,
              onWallpaperChanged: onWallpaperChanged,
            )
          else
            PersonalProfileIdentityHeader(
              projection: projection,
              isSelf: !isVisitor,
              presence: visitorPreview || isVisitor ? null : presence,
            ),
          SizedBox(height: tokens.space.xl),
          PersonalProfileSectionHeading(
            projection: projection,
            showOwnerActions: !visitorPreview && !isVisitor && !editing,
            onPreview: onPreview,
            onEdit: onEdit,
            onRefresh: onRefresh,
            onVisibility: onVisibility,
          ),
          if (!projection.allowEditing && !visitorPreview && !isVisitor) ...[
            SizedBox(height: tokens.space.sm),
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.privacy,
                  size: tokens.icons.small,
                  color: tokens.colors.textSecondary,
                ),
                SizedBox(width: tokens.space.xs),
                Expanded(
                  child: Text(
                    AppStrings.of(context).text('profile.readOnly.notice'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: tokens.space.md),
          if (projection.local?.needsCreation == true && !editing) ...[
            Text(
              AppStrings.of(context).text('profile.local.firstSteps'),
              key: const Key('profile-local-first-steps'),
            ),
            SizedBox(height: tokens.space.sm),
          ],
          if (projection.local?.remoteAvailable == false)
            Text(
              AppStrings.of(context).text('profile.local.remoteUnavailable'),
              key: const Key('profile-local-remote-unavailable'),
            ),
          PersonalProfileSummaryStrip(
            projection: projection,
            gameplayTime: isVisitor ? null : gameplayTime,
            includeLocalTime: !visitorPreview && !isVisitor,
          ),
          SizedBox(height: tokens.space.md),
          ExcludeFocus(
            excluding: projection.operation != PersonalProfileOperation.none,
            child: AbsorbPointer(
              absorbing: projection.operation != PersonalProfileOperation.none,
              child: PersonalProfileModuleGrid(
                projection: projection,
                visitorView: visitorPreview || isVisitor,
                editing: editing,
                layout: layout,
                onLayoutChanged: onLayoutChanged,
                onEditPositions:
                    projection.canEdit &&
                        editing &&
                        !visitorPreview &&
                        projection.local != null
                    ? onEditPositions
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PrivateVisitorView extends StatelessWidget {
  const _PrivateVisitorView();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('profile-private-visitor-view'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.xxl),
      child: Column(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.privacy,
            size: tokens.icons.large,
            color: tokens.colors.textSecondary,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('profile.private.title'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('profile.private.body'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
