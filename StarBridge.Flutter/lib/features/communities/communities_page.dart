import '../../design_system/theme/classic_font_scope.dart';
import '../../shared/guide/guide_empty_state.dart';
import 'community_directory_controls.dart';
import 'community_initial_read_wait.dart';
import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import 'community_directory_presentation.dart';
import 'community_directory_notice.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/controls/semantic_action_style.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_workspace_frame.dart';
import '../common/social_read_activity.dart';
import 'communities_module.dart';
import 'community_directory_details.dart';
import 'example_communities.dart';
import 'community_filter_panel.dart';
import 'community_visible_refresh.dart';
import 'community_creation_dialog.dart';
import 'community_creation_port.dart';
import 'community_creation_copy.dart';
import 'community_workspace_port.dart';
import 'community_workspace_view.dart';
import 'community_invite_dialog.dart';
import 'community_invite_port.dart';
import 'community_invite_copy.dart';
import 'community_invitation_send_port.dart';
import 'community_invitation_send_copy.dart';
import 'community_invitation_outbox_dialog.dart';
import '../settings/local_privacy_port.dart';

class CommunitiesPage extends StatefulWidget {
  const CommunitiesPage({
    required this.createPort,
    this.module,
    this.createAdmissionPrivacy,
    super.key,
  });
  final CommunitiesPort Function() createPort;
  final CommunitiesModule? module;
  final LocalPrivacyPort Function()? createAdmissionPrivacy;
  @override
  State<CommunitiesPage> createState() => _CommunitiesPageState();
}

class _CommunitiesPageState extends State<CommunitiesPage>
    with CommunityVisibleRefresh<CommunitiesPage> {
  @override
  Future<void> refreshVisibleCommunity() async {
    if (!model.busy && model.selected == null && model.error != null) {
      await model.refresh();
    }
  }

  late final CommunitiesModule model;
  late final SocialReadActivityBinding _directoryActivity;
  late final bool example;
  final search = TextEditingController();
  int revision = 0;
  final _workspaceKey = GlobalKey<CommunityWorkspaceViewState>();
  Future<bool> _confirmWorkspaceLeave() async =>
      await _workspaceKey.currentState?.confirmLeave() ?? true;
  StarBridgeDialogRoute<bool>? _confirmation;
  StarBridgeDialogRoute<String>? _filterDialog;
  StarBridgeDialogRoute<void>? _outboxDialog;
  StarBridgeDialogRoute<void>? _detailsDialog;
  StarBridgeDialogRoute<CommunityCreationOutcome>? _creationDialog;
  StarBridgeDialogRoute<CommunityInviteOutcome>? _inviteDialog;
  bool _creating = false;
  bool _inviting = false;
  // Owned routes can still lay out while the page is being retired. Retain
  // its latest inherited value, including caller-local language overrides.
  late AppStrings _strings;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _strings = AppStrings.of(context);
  }

  String t(String key) => _strings.text('communities.$key');
  @override
  void initState() {
    super.initState();
    final port = widget.module?.port ?? widget.createPort();
    example = port is ExampleCommunities;
    model = widget.module ?? CommunitiesModule(port);
    model.confirmWorkspaceLeave = _confirmWorkspaceLeave;
    _directoryActivity = SocialReadActivityBinding(
      model,
      () => model.showDirectoryProgress,
      initialRead:
          !model.busy &&
          model.selected == null &&
          (model.directory == null || model.view != 'discover'),
      phaseIdentity: () => model.directoryReadEpoch,
    );
    if (model.showDirectoryProgress) {
      // This page joined an already admitted read; it did not initiate it.
      _directoryActivity.source = InteractionSource.programmatic;
    }
    revision = model.accountRevision;
    model.addListener(_changed);
    search.text = model.query;
    if (model.selected == null &&
        (model.directory == null || model.view != 'discover')) {
      scheduleMicrotask(() {
        if (mounted) unawaited(model.refresh(newView: 'discover'));
      });
    } else if (model.selected == null) {
      scheduleMicrotask(() {
        if (mounted) unawaited(model.refresh(silent: true, reuseFresh: true));
      });
    }
  }

  void _changed() {
    if (revision != model.accountRevision) {
      revision = model.accountRevision;
      search.clear();
      for (final route in [
        _confirmation,
        _filterDialog,
        _outboxDialog,
        _detailsDialog,
        _creationDialog,
        _inviteDialog,
      ]) {
        retireStarBridgeDialog(route);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final route in [
      _confirmation,
      _filterDialog,
      _outboxDialog,
      _detailsDialog,
      _creationDialog,
      _inviteDialog,
    ]) {
      retireStarBridgeDialog(route);
    }
    _directoryActivity.dispose();
    model.removeListener(_changed);
    if (model.confirmWorkspaceLeave == _confirmWorkspaceLeave) {
      model.confirmWorkspaceLeave = null;
    }
    if (widget.module == null) model.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> act(CommunityCard card, String action) async {
    if (!mounted || _confirmation != null) return;
    final currentRevision = model.accountRevision;
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      builder: (context) => AlertDialog(
        title: Text(t('action.$action')),
        content: Text('${card.name}\n\n${t('confirm.$action')}'),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('community-command-cancel'),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            child: Text(t('cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('community-command-confirm'),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: true),
            child: Text(t('action.$action')),
          ),
        ],
      ),
      onRouteCreated: (route) => _confirmation = route,
    );
    _confirmation = null;
    if (confirmed == true &&
        mounted &&
        currentRevision == model.accountRevision) {
      await model.execute(card, action);
    }
  }

  Future<void> _showDirectoryDetails(CommunityCard initial) async {
    if (_detailsDialog != null) return;
    await showStarBridgeDialog<void>(
      context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: model,
        builder: (_, _) {
          final row = model.directory?.items
              .where((r) => r.key == initial.key)
              .firstOrNull;
          return CommunityDirectoryDetails(
            row: row,
            text: t,
            message: model.message == null ? null : t(model.message!),
            onClose: () => dismissStarBridgeDialog(
              dialogContext,
              source: currentStarBridgeActivationSource,
            ),
            onAction: row == null || !model.canExecute(row)
                ? null
                : (action) => act(row, action),
            onEnter: model.writing || row == null || row.displayOnly
                ? null
                : () {
                    dismissStarBridgeDialog(
                      dialogContext,
                      source: currentStarBridgeActivationSource,
                    );
                    model.open(row);
                  },
          );
        },
      ),
      onRouteCreated: (route) => _detailsDialog = route,
    );
    _detailsDialog = null;
  }

  Future<void> _openInvitationOutbox() async {
    final port = model.port;
    if (port is! CommunityInvitationSendPort || _outboxDialog != null) return;
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: false,
      builder: (_) => CommunityInvitationOutboxDialog(
        port: port as CommunityInvitationSendPort,
      ),
      onRouteCreated: (route) => _outboxDialog = route,
    );
    _outboxDialog = null;
  }

  Future<void> createOrganization() async {
    final port = model.port;
    if (_creating || model.writing || port is! CommunityCreationPort) return;
    final currentRevision = model.accountRevision;
    setState(() => _creating = true);
    final result = await showStarBridgeDialog<CommunityCreationOutcome>(
      context,
      barrierDismissible: false,
      builder: (_) => CommunityCreationDialog(
        example: example,
        port: port as CommunityCreationPort,
        invalidations: model.port.invalidations,
      ),
      onRouteCreated: (route) => _creationDialog = route,
    );
    _creationDialog = null;
    if (!mounted) return;
    setState(() => _creating = false);
    if (result == null || currentRevision != model.accountRevision) return;
    await model.refresh(newView: 'discover', force: true);
    if (!mounted || currentRevision != model.accountRevision) return;
    await model.refreshJoined();
    if (mounted &&
        currentRevision == model.accountRevision &&
        result.status == 'accepted') {
      model.open(result.organization);
    }
  }

  Future<void> enterInvite() async {
    final port = model.port;
    if (_inviting ||
        _creating ||
        model.writing ||
        port is! CommunityInvitePort) {
      return;
    }
    final currentRevision = model.accountRevision;
    final privacy = port is ExampleCommunities
        ? port.createAdmissionPrivacy()
        : widget.createAdmissionPrivacy?.call();
    setState(() => _inviting = true);
    await showStarBridgeDialog<CommunityInviteOutcome>(
      context,
      barrierDismissible: false,
      builder: (_) => CommunityInviteDialog(
        port: port as CommunityInvitePort,
        privacy: privacy,
        example: example,
      ),
      onRouteCreated: (route) => _inviteDialog = route,
    );
    _inviteDialog = null;
    if (!mounted) return;
    setState(() => _inviting = false);
    if (currentRevision != model.accountRevision) return;
    await model.refresh(newView: 'discover', force: true);
    if (mounted && currentRevision == model.accountRevision) {
      await model.refreshJoined();
    }
  }

  @override
  Widget build(BuildContext context) {
    final internal =
        model.selected != null &&
        const {'owner', 'member'}.contains(model.selected!.relationship);
    // Joined communities use the main fleet's two-screen holo shell,
    // full-bleed like the main fleet page (user decision 2026-10-23).
    if (internal && model.port is CommunityWorkspacePort) {
      return ClassicFontScope(
        child: _workspaceView(model.selected!, holo: true),
      );
    }
    if (internal) {
      return OrganizationWorkspacePage(child: _content());
    }
    return OrganizationWorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('discover'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('community-directory-refresh'),
                onActivate: model.busy ? null : (_) => model.refresh(),
                child: Text(t('refresh')),
              ),
              if (model.port is CommunityCreationPort)
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: const Key('community-create-open'),
                  onActivate: model.writing || _creating
                      ? null
                      : (_) => createOrganization(),
                  child: Text(creationText(context, 'title')),
                ),
            ],
          ),
          Text(
            t('subtitle'),
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
          if (example)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t('example'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (model.port is CommunityInvitePort)
                StarBridgeActionButton(
                  controlKey: const Key('community-admission-open'),
                  onActivate: model.writing || _creating || _inviting
                      ? null
                      : (_) => enterInvite(),
                  child: Text(inviteText(context, 'title')),
                ),
              if (model.port is CommunityInvitationSendPort &&
                  (model.port as CommunityInvitationSendPort)
                      .invitationSendingAvailable)
                StarBridgeActionButton(
                  controlKey: const Key('community-outbox-open'),
                  onActivate: (_) => _openInvitationOutbox(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StandardIcon(StandardIconSemantic.outbox),
                      const SizedBox(width: 8),
                      Text(invitationSendText(context, 'records')),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wideFilters =
                    model.view == 'discover' &&
                    model.selected == null &&
                    constraints.maxWidth >= 1050;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wideFilters) ...[
                      SizedBox(
                        width: 290,
                        child: CommunityFilterPanel(
                          key: ValueKey(
                            'filters-${model.accountRevision}-${model.filters}',
                          ),
                          value: model.filters,
                          invalidations: model.port.invalidations,
                          onApply: (value) => model.refresh(newFilters: value),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(child: _content(showFilterButton: !wideFilters)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    if (!mounted || _filterDialog != null) return;
    final revision = model.accountRevision;
    final value = await showStarBridgeDialog<String>(
      context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 400,
          height: 620,
          child: CommunityFilterPanel(
            value: model.filters,
            invalidations: model.port.invalidations,
            onApply: (value) => dismissStarBridgeDialog(
              context,
              source: currentStarBridgeActivationSource,
              result: value,
            ),
          ),
        ),
      ),
      onRouteCreated: (route) => _filterDialog = route,
    );
    _filterDialog = null;
    if (mounted && revision == model.accountRevision && value != null) {
      await model.refresh(newFilters: value);
    }
  }

  Widget _workspaceView(CommunityCard selected, {bool holo = false}) =>
      CommunityWorkspaceView(
        holo: holo,
        key: _workspaceKey,
        port: model.port as CommunityWorkspacePort,
        targetRef: selected.targetRef,
        organizationKey: selected.key,
        session: model.workspaceSession,
        onFocused: model.onWorkspaceFocused,
        onGovernanceChanged: model.refreshCurrentMembership,
        onNameConfirmed: (code, name) =>
            model.applyOrganizationName(selected.key, code, name),
        actions: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in selected.actions)
              StarBridgeActionButton(
                controlKey: ValueKey('community-workspace-command-$action'),
                tone: action == 'leave' ? ActionTone.warning : null,
                onActivate: !model.canExecute(selected)
                    ? null
                    : (_) => act(selected, action),
                child: Text(t('action.$action')),
              ),
          ],
        ),
      );

  Widget _content({bool showFilterButton = true}) {
    final selected = model.selected;
    final content = OrganizationWorkspaceSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected != null) ...[
            if (!const {'owner', 'member'}.contains(selected.relationship))
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('community-directory-back'),
                  onActivate: (_) => model.open(null),
                  child: Text(t('back')),
                ),
              ),
            Expanded(
              child:
                  model.port is CommunityWorkspacePort &&
                      const {'owner', 'member'}.contains(selected.relationship)
                  ? _workspaceView(selected)
                  : SingleChildScrollView(child: _card(selected, detail: true)),
            ),
          ] else ...[
            ...communityDirectoryControls(
              model: model,
              search: search,
              text: t,
              showFilterButton: showFilterButton,
              onFilters: _showFilters,
            ),
            if (model.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t(model.message!),
                  style: TextStyle(
                    color: model.message!.startsWith('done.')
                        ? context.tokens.colors.success
                        : context.tokens.colors.warning,
                  ),
                ),
              ),
            if (model.directory != null &&
                (model.showDirectoryProgress ||
                    model.error != null ||
                    model.directory!.cachedAtUtc != null))
              CommunityDirectoryNotice(
                model,
                progress: SocialReadActivity(
                  key: ValueKey((
                    'community-directory-read',
                    _directoryActivity.revision,
                  )),
                  source: _directoryActivity.source,
                  opening: _directoryActivity.opening,
                  label: t('loading'),
                  height: 4,
                ),
              ),
            Expanded(
              child: model.busy && model.directory == null
                  ? Center(
                      child: CommunityInitialReadWait.directory(
                        key: ValueKey((
                          'community-directory-initial',
                          _directoryActivity.revision,
                        )),
                        source: model.showDirectoryProgress
                            ? _directoryActivity.source
                            : InteractionSource.programmatic,
                        opening:
                            model.showDirectoryProgress &&
                            _directoryActivity.opening,
                        label: t('loading'),
                      ),
                    )
                  : model.error != null && model.directory == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t(model.error!), textAlign: TextAlign.center),
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            controlKey: const Key('community-directory-retry'),
                            onActivate: (_) => model.refresh(),
                            child: Text(t('retry')),
                          ),
                        ],
                      ),
                    )
                  : model.directory?.items.isEmpty != false &&
                        model.view == 'mine' &&
                        model.query.isEmpty &&
                        model.directory?.cachedAtUtc == null &&
                        GuideEmptyState.active(context)
                  ? GuideEmptyState(
                      'communities',
                      onPrimary: () => unawaited(
                        model.refresh(newView: 'discover', force: true),
                      ),
                    )
                  : model.directory?.items.isEmpty != false
                  ? Center(
                      child: Text(
                        t(
                          model.directory?.cachedAtUtc != null
                              ? 'shortcutsCachedEmpty'
                              : model.query.isNotEmpty
                              ? 'emptySearch'
                              : 'empty.${model.view}',
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            (MediaQuery.textScalerOf(context).scale(14) / 14)
                                .clamp(1.0, 3.0);
                        final horizontal =
                            constraints.maxHeight < 464 * textScale &&
                            constraints.maxWidth >= 720 * textScale;
                        final columns =
                            ((constraints.maxWidth + 12) /
                                    (horizontal ? 1000 * textScale : 532))
                                .floor()
                                .clamp(1, 4);
                        final rows = model.directory!.items;
                        return ListView.separated(
                          key: PageStorageKey(
                            'community-directory-${model.view}-${model.query}-${model.filters}',
                          ),
                          itemCount: (rows.length / columns).ceil(),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, rowIndex) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var column = 0;
                                column < columns;
                                column++
                              ) ...[
                                if (column > 0) const SizedBox(width: 12),
                                Expanded(
                                  child:
                                      rowIndex * columns + column >= rows.length
                                      ? const SizedBox.shrink()
                                      : _card(
                                          rows[rowIndex * columns + column],
                                          horizontal: horizontal,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (model.canPrevious || model.directory?.next != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('community-directory-previous'),
                    onActivate: model.busy || !model.canPrevious
                        ? null
                        : (_) => model.previous(),
                    child: Text(t('previous')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('community-directory-next'),
                    onActivate: model.busy || model.directory?.next == null
                        ? null
                        : (_) => model.next(),
                    child: Text(t('next')),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
    // A workspace owns its separate asynchronous content branches; a directory
    // response must not pretend that its workspace has finished loading.
    if (selected != null) return content;
    final items = model.directory?.items.length ?? 0;
    return LoadingContentProbe(
      route: '/communities',
      status: model.busy
          ? (model.directory == null
                ? LoadingContentStatus.waiting
                : LoadingContentStatus.partial)
          : model.directory?.cachedAtUtc != null
          ? LoadingContentStatus.partial
          : model.error != null
          ? LoadingContentStatus.failed
          : model.directory == null
          ? LoadingContentStatus.unavailable
          : items == 0
          ? LoadingContentStatus.empty
          : LoadingContentStatus.data,
      items: items,
      child: content,
    );
  }

  Widget _card(
    CommunityCard row, {
    bool detail = false,
    bool horizontal = false,
  }) => CommunityDirectoryPresentation(
    context: context,
    model: model,
    t: t,
    onDetails: _showDirectoryDetails,
    onAction: act,
  ).build(row, detail: detail, horizontal: horizontal);
}
