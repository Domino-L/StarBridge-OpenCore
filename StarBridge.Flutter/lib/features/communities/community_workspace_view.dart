import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'community_workspace_members.dart';
import 'community_workspace_information.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/window/native_viewport_visibility.dart';

import 'community_workspace_controller.dart';
import 'community_workspace_session.dart';
import 'community_workspace_copy.dart';
import 'community_workspace_port.dart';
import 'community_settings_workspace.dart';
import 'community_workspace_header.dart';
import 'community_visible_refresh.dart';
import 'community_ownership_exit_port.dart';
import 'community_ownership_exit_dialog.dart';
import 'community_ownership_exit_copy.dart';
import 'community_disband_port.dart';
import 'community_disband_dialog.dart';
import 'community_disband_copy.dart';
import 'community_chat_port.dart';
import 'community_chat_panel.dart';
import 'community_chat_workspace.dart';
import 'community_ships_port.dart';
import 'community_ships_panel.dart';
import 'community_ships_copy.dart' show communityShipsCulture;
import 'community_section_stack.dart';
import 'community_announcements_port.dart';
import 'community_announcements_dialog.dart';
import '../../design_system/controls/semantic_action_style.dart';
export 'community_workspace_image.dart';

class CommunityWorkspaceView extends StatefulWidget {
  const CommunityWorkspaceView({
    required this.port,
    required this.targetRef,
    this.organizationKey,
    this.session,
    this.actions,
    this.onGovernanceChanged,
    this.onNameConfirmed,
    this.onFocused,
    super.key,
  });
  final CommunityWorkspacePort port;
  final String targetRef;

  /// Stable directory identity, distinct from the short-lived access reference.
  final String? organizationKey;
  final CommunityWorkspaceSession? session;
  final Widget? actions;
  final Future<void> Function()? onGovernanceChanged;
  final void Function(String code, String name)? onNameConfirmed;
  final void Function(String code)? onFocused;
  @override
  State<CommunityWorkspaceView> createState() => CommunityWorkspaceViewState();
}

class CommunityWorkspaceViewState extends State<CommunityWorkspaceView>
    with CommunityVisibleRefresh<CommunityWorkspaceView> {
  late CommunityWorkspaceController model;
  bool _ownsModel = true;
  final search = TextEditingController();
  bool _leaving = false;
  bool _refreshingMembership = false;
  bool _automaticRenewalAttempted = false;
  String _section = 'members';
  DialogRoute<void>? _detailsRoute;
  final _chatKey = GlobalKey<CommunityChatPanelState>();
  final _settingsKey = GlobalKey<CommunitySettingsWorkspaceState>();
  Timer? _sectionPreparation;

  void _scheduleSectionPreparation() {
    if (!mounted ||
        _sectionPreparation != null ||
        !model.needsSectionPreparation) {
      return;
    }
    _sectionPreparation = Timer(const Duration(milliseconds: 500), () {
      _sectionPreparation = null;
      if (!mounted) return;
      if (isCommunityVisible &&
          _section != 'manage' &&
          !_refreshingMembership &&
          !_leaving) {
        unawaited(model.prepareNextSection(communityShipsCulture(context)));
      }
      _scheduleSectionPreparation();
    });
  }

  @override
  Future<void> refreshVisibleCommunity() async {
    if (model.busy || _refreshingMembership || _leaving) return;
    // Reuse the existing account-scoped page and media; never rebind the
    // directory or ask about drafts for a background metadata read.
    if (model.error == 'identityUnavailable' || model.error == 'notAllowed') {
      return;
    }
    await model.load(silent: true);
  }

  Future<bool> confirmLeave() async =>
      await (_settingsKey.currentState?.confirmLeave() ??
          _chatKey.currentState?.confirmLeave() ??
          Future.value(true));

  Future<void> _refreshWorkspace() async {
    if (_refreshingMembership || _leaving) return;
    final previous = model;
    final previousTarget = widget.targetRef;
    setState(() => _refreshingMembership = true);
    try {
      // Rebinding can discard a chat draft; retain the existing leave guard.
      if (!await confirmLeave() || !mounted || model != previous) return;
      final refresh = widget.onGovernanceChanged;
      if (refresh != null) {
        // The directory rechecks current membership and account revision before
        // issuing a new reference. Never replay a mutation or relax Host expiry.
        await refresh();
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted &&
          model == previous &&
          widget.targetRef == previousTarget &&
          !model.busy) {
        await model.load();
      }
    } catch (_) {
      // A failed rebind keeps the existing error/retry UI. Never replay writes.
    } finally {
      if (mounted) setState(() => _refreshingMembership = false);
    }
  }

  Future<void> _selectSection(String section) async {
    if (section == _section) return;
    final current = model;
    if (!await confirmLeave() || !mounted || current != model) return;
    setState(() {
      _section = section;
      if (section != 'manage') model.selectedSection = section;
      // High-frequency navigation keeps the same compact overview and hit targets.
    });
  }

  final _assignmentInvalidations = StreamController<void>.broadcast();
  bool _headerExpanded = false;
  String t(String key) => workspaceText(context, key);
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _ownsModel = widget.session == null;
    model =
        widget.session?.obtain(
          widget.port,
          widget.targetRef,
          widget.organizationKey,
        ) ??
        CommunityWorkspaceController(widget.port, widget.targetRef);
    search.text = model.query;
    _section = model.selectedSection;
    model.addListener(_changed);
    unawaited(model.enter(widget.targetRef));
    // A retained failure can need reference renewal before any listener fires.
    if (model.error == 'refreshRequired') _changed();
    _scheduleSectionPreparation();
  }

  void _changed() {
    _scheduleSectionPreparation();
    if (model.workspace == null) _dismissDetails();
    if (model.error == 'identityUnavailable') search.clear();
    if (mounted) setState(() {});
    if (mounted &&
        model.workspace == null &&
        model.error == 'refreshRequired' &&
        !_automaticRenewalAttempted &&
        !_refreshingMembership &&
        widget.onGovernanceChanged != null) {
      _automaticRenewalAttempted = true;
      final current = model;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && model == current && model.error == 'refreshRequired') {
          unawaited(_refreshWorkspace());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CommunityWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.organizationKey != widget.organizationKey) {
      if (oldWidget.port != widget.port ||
          oldWidget.organizationKey != widget.organizationKey) {
        _automaticRenewalAttempted = false;
      }
      _assignmentInvalidations.add(null);
      final sameOrganization =
          oldWidget.port == widget.port &&
          widget.organizationKey != null &&
          oldWidget.organizationKey == widget.organizationKey;
      if (oldWidget.session == widget.session &&
          sameOrganization &&
          model.workspace != null &&
          model.error == null) {
        if (_section != 'ships') _section = 'members';
        model.selectedSection = _section;
        _dismissDetails();
        unawaited(model.renewReference(widget.targetRef));
        return;
      }
      model.removeListener(_changed);
      model.setMemberListHovered(false);
      if (_ownsModel) model.dispose();
      search.clear();
      // Keep the ship tab on reference renewal, never on organization switches.
      // Chat and management retain their existing reset/confirmation semantics.
      if (!sameOrganization || _section != 'ships') _section = 'members';
      _dismissDetails();
      _start();
    }
  }

  @override
  void dispose() {
    _sectionPreparation?.cancel();
    _dismissDetails();
    _assignmentInvalidations.add(null);
    unawaited(_assignmentInvalidations.close());
    model.removeListener(_changed);
    model.setMemberListHovered(false);
    if (_ownsModel) model.dispose();
    search.dispose();
    super.dispose();
  }

  void _dismissDetails() {
    final route = _detailsRoute;
    _detailsRoute = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  Future<void> _openDetails(Widget details) async {
    if (_detailsRoute != null || model.workspace == null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('community-details-dialog'),
        title: Text(t('details')),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(child: details),
        ),
        actions: [
          TextButton.icon(
            key: const Key('community-details-refresh'),
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_refreshWorkspace());
            },
            icon: const StandardIcon(StandardIconSemantic.refresh, size: 18),
            label: Text(t('refresh')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
    _detailsRoute = route;
    await Navigator.of(context).push(route);
    if (_detailsRoute == route) _detailsRoute = null;
  }

  Future<void> _leaveWithSuccessor() async {
    final current = model;
    final port = widget.port;
    final target = model.targetRef;
    if (_leaving ||
        port is! CommunityOwnershipExitPort ||
        !(port as CommunityOwnershipExitPort).ownershipExitAvailable ||
        current.workspace?.access['isOwner'] != true) {
      return;
    }
    setState(() => _leaving = true);
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityOwnershipExitDialog(
          port: port as CommunityOwnershipExitPort,
          workspacePort: port,
          targetRef: target,
          contextInvalidations: _assignmentInvalidations.stream,
        ),
      );
      if (!mounted ||
          model != current ||
          current.error == 'identityUnavailable') {
        return;
      }
      await current.load();
      // A successful exit makes the member workspace forbidden. Still refresh
      // both directory and joined shortcuts; a null workspace is not failure.
      if (mounted &&
          model == current &&
          current.error != 'identityUnavailable') {
        await widget.onGovernanceChanged?.call();
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _disband() async {
    final current = model;
    final port = widget.port;
    final target = model.targetRef;
    if (_leaving ||
        port is! CommunityDisbandPort ||
        !(port as CommunityDisbandPort).disbandAvailable ||
        current.workspace?.access['isOwner'] != true) {
      return;
    }
    setState(() => _leaving = true);
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityDisbandDialog(
          port: port as CommunityDisbandPort,
          targetRef: target,
          contextInvalidations: _assignmentInvalidations.stream,
        ),
      );
      if (!mounted ||
          model != current ||
          current.error == 'identityUnavailable') {
        return;
      }
      await current.load();
      // Removal makes the workspace unavailable. Refresh membership shortcuts
      // even then, and also reread after an uncertain response without retrying.
      if (mounted &&
          model == current &&
          current.error != 'identityUnavailable') {
        await widget.onGovernanceChanged?.call();
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _copy(String value, {bool all = false}) async {
    if (value.trim().isEmpty) return;
    final current = model;
    final currentWorkspace = model.workspace;
    try {
      await Clipboard.setData(ClipboardData(text: value.trim()));
      if (mounted && model == current && model.workspace == currentWorkspace) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(all ? 'copiedAll' : 'copied'))),
        );
      }
    } catch (_) {
      if (mounted && model == current && model.workspace == currentWorkspace) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('contactCopyFailed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only visible workspaces announce navigation, never prefetch or hidden tabs.
    final code = model.workspace?.code;
    if (code != null &&
        TickerMode.valuesOf(context).enabled &&
        NativeViewportScope.isActive(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            TickerMode.valuesOf(context).enabled &&
            NativeViewportScope.isActive(context) &&
            model.workspace?.code == code) {
          widget.onFocused?.call(code);
        }
      });
    }
    return ExcludeFocus(
      excluding: model.renewingReference && model.workspace != null,
      child: AbsorbPointer(
        key: const ValueKey('community-reference-guard'),
        absorbing: model.renewingReference && model.workspace != null,
        child: _buildWorkspace(context),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final workspace = model.workspace;
    if ((model.busy || _refreshingMembership) && workspace == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.disableAnimationsOf(context))
              const StandardIcon(StandardIconSemantic.hourglassTop)
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(t(_refreshingMembership ? 'renewing' : 'loading')),
          ],
        ),
      );
    }
    if (workspace == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(model.error ?? 'unavailable'), textAlign: TextAlign.center),
            if (model.error == 'refreshRequired' &&
                    widget.onGovernanceChanged != null ||
                !const {
                  'identityUnavailable',
                  'notAllowed',
                  'refreshRequired',
                }.contains(model.error))
              TextButton(
                onPressed: _refreshWorkspace,
                child: Text(t('refresh')),
              ),
          ],
        ),
      );
    }
    final canOpenChat =
        widget.port is CommunityChatPort &&
        (widget.port as CommunityChatPort).chatAvailable;
    final canOpenShips =
        widget.port is CommunityShipsPort &&
        (widget.port as CommunityShipsPort).shipsAvailable;
    final canManage =
        workspace.access['isOwner'] == true ||
        workspace.access['canEditProfile'] == true ||
        workspace.access['canEditLogo'] == true ||
        workspace.access['canEditBanner'] == true ||
        workspace.access['canReviewApplications'] == true ||
        workspace.access['canCreateInvite'] == true ||
        workspace.access['canViewLogs'] == true;
    final section =
        (_section == 'manage' && !canManage) ||
            (_section == 'chat' && !canOpenChat) ||
            (_section == 'ships' && !canOpenShips)
        ? 'members'
        : _section;
    final information = CommunityWorkspaceInformation(
      context: context,
      model: model,
      workspace: workspace,
      copy: _copy,
    );
    final headerInformation = information.information;
    final details = information.details;
    final members = CommunityWorkspaceMembers(
      context: context,
      currentModel: () => model,
      isMounted: () => mounted,
      port: widget.port,
      organizationKey: widget.organizationKey,
      search: search,
      contextInvalidations: _assignmentInvalidations.stream,
      onGovernanceChanged: () async => await widget.onGovernanceChanged?.call(),
    ).build();
    final management = CommunitySettingsWorkspace(
      key: _settingsKey,
      port: widget.port,
      workspace: workspace,
      targetRef: model.targetRef,
      logo: model.image('logo'),
      logoLoading: model.imageLoading('logo'),
      logoFailed: model.imageFailed('logo'),
      contextInvalidations: _assignmentInvalidations.stream,
      onMembers: () => _selectSection('members'),
      onNameConfirmed: widget.onNameConfirmed,
      onWorkspaceChanged: (images) =>
          unawaited(model.load(refreshImages: images)),
      hasDangerActions:
          workspace.access['isOwner'] == true &&
          ((widget.port is CommunityOwnershipExitPort &&
                  (widget.port as CommunityOwnershipExitPort)
                      .ownershipExitAvailable) ||
              (widget.port is CommunityDisbandPort &&
                  (widget.port as CommunityDisbandPort).disbandAvailable)),
      dangerActions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workspace.access['isOwner'] == true &&
              widget.port is CommunityOwnershipExitPort &&
              (widget.port as CommunityOwnershipExitPort)
                  .ownershipExitAvailable) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('leave-with-successor'),
                style: semanticActionStyle(
                  context,
                  ActionTone.warning,
                  emphasis: ActionEmphasis.outlined,
                ),
                onPressed: _leaving ? null : _leaveWithSuccessor,
                icon: const StandardIcon(StandardIconSemantic.logout),
                label: Text(ownershipExitText(context, 'title')),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (workspace.access['isOwner'] == true &&
              widget.port is CommunityDisbandPort &&
              (widget.port as CommunityDisbandPort).disbandAvailable) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('disband-community'),
                style: semanticActionStyle(
                  context,
                  ActionTone.danger,
                  emphasis: ActionEmphasis.outlined,
                ),
                onPressed: _leaving ? null : _disband,
                icon: const StandardIcon(StandardIconSemantic.deleteForever),
                label: Text(disbandText(context, 'action')),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
    if (section == 'manage') {
      return Column(
        key: const Key('community-internal-workspace'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('community-settings-back'),
                onPressed: () => _selectSection('members'),
                icon: const StandardIcon(StandardIconSemantic.arrowBack, size: 18),
                label: Text(communitySettingsText(context, 'back')),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  workspace.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: t('refresh'),
                onPressed: _refreshWorkspace,
                icon: const StandardIcon(StandardIconSemantic.refresh),
              ),
            ],
          ),
          const Divider(height: 24),
          _refreshProgress(),
          Expanded(child: management),
        ],
      );
    }
    return Column(
      key: const Key('community-internal-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityWorkspaceHeader(
          expanded: _headerExpanded,
          onToggleExpansion: () =>
              setState(() => _headerExpanded = !_headerExpanded),
          workspace: workspace,
          logo: model.image('logo'),
          logoLoading: model.imageLoading('logo'),
          logoFailed: model.imageFailed('logo'),
          onRefresh: _refreshWorkspace,
          onCopyContacts: information.copyContacts,
          onCopyContact: (value) => _copy(value),
          onDetails: () => _openDetails(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  workspace.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(workspace.code),
                details,
                const Divider(height: 32),
                if (widget.port is CommunityAnnouncementsPort &&
                    (widget.port as CommunityAnnouncementsPort)
                        .announcementsAvailable) ...[
                  CommunityAnnouncementEntry(
                    key: ValueKey('detail-announcements:${model.targetRef}'),
                    controller: model.announcements,
                    port: widget.port as CommunityAnnouncementsPort,
                    targetRef: model.targetRef,
                    expanded: true,
                  ),
                  const Divider(height: 32),
                ] else ...[
                  Text(
                    t('announcements'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(t('sectionUnavailable')),
                  const Divider(height: 32),
                ],
                headerInformation,
              ],
            ),
          ),
          announcement:
              widget.port is CommunityAnnouncementsPort &&
                  (widget.port as CommunityAnnouncementsPort)
                      .announcementsAvailable
              ? CommunityAnnouncementEntry(
                  key: ValueKey('announcements:${model.targetRef}'),
                  controller: model.announcements,
                  port: widget.port as CommunityAnnouncementsPort,
                  targetRef: model.targetRef,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('sectionUnavailable'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in [
                      ('members', true),
                      ('chat', canOpenChat),
                      ('ships', canOpenShips),
                      // WPF broadcasts have no Flutter port yet. Keep the location
                      // explicit without inventing a send action or permission.
                      ('broadcast', false),
                      if (canManage) ('manage', true),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Tooltip(
                          message: item.$2 ? '' : t('sectionUnavailable'),
                          child: ChoiceChip(
                            key: ValueKey('community-section-${item.$1}'),
                            label: Text(t('section.${item.$1}')),
                            showCheckmark: false,
                            labelStyle: Theme.of(context).textTheme.labelLarge,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            pressElevation: 0,
                            chipAnimationStyle: ChipAnimationStyle(
                              enableAnimation: AnimationStyle.noAnimation,
                              selectAnimation: AnimationStyle.noAnimation,
                              avatarDrawerAnimation: AnimationStyle.noAnimation,
                              deleteDrawerAnimation: AnimationStyle.noAnimation,
                            ),
                            selected: section == item.$1,
                            onSelected: item.$2
                                ? (_) => _selectSection(item.$1)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.actions != null) widget.actions!,
          ],
        ),
        const Divider(height: 24),
        _refreshProgress(),
        if (model.error != null)
          Row(
            children: [
              Expanded(child: Text(t('refreshFailed'))),
              TextButton(
                onPressed: model.busy ? null : () => model.load(),
                child: Text(t('refresh')),
              ),
            ],
          ),
        Expanded(
          child: CommunitySectionStack(
            key: ValueKey((widget.port, model.targetRef)),
            selected: section,
            sections: {
              if (canOpenChat)
                'chat': (_) => CommunityChatWorkspace(
                  key: ValueKey('chat-workspace:${model.targetRef}'),
                  port: widget.port,
                  targetRef: model.targetRef,
                  avatars: model.avatars,
                  onAllMembers: () => _selectSection('members'),
                  chat: CommunityChatPanel(
                    key: _chatKey,
                    controller: model.chat,
                    avatars: model.avatars,
                    port: widget.port as CommunityChatPort,
                    targetRef: model.targetRef,
                    name: workspace.name,
                    onBack: () => setState(() {
                      _section = 'members';
                      model.selectedSection = 'members';
                    }),
                  ),
                ),
              if (canOpenShips)
                'ships': (_) => CommunityShipsPanel(
                  key: ValueKey('ships:${model.targetRef}'),
                  controller: model.ships,
                  avatars: model.avatars,
                  port: widget.port as CommunityShipsPort,
                  targetRef: model.targetRef,
                  name: workspace.name,
                  onRefreshMembership: _refreshWorkspace,
                  onBack: () => setState(() {
                    _section = 'members';
                    model.selectedSection = 'members';
                  }),
                ),
              'members': (_) => members,
            },
          ),
        ),
      ],
    );
  }

  Widget _refreshProgress() => SizedBox(
    height: 2,
    child: model.showProgress
        ? LinearProgressIndicator(
            key: const ValueKey('community-refresh-progress'),
            value: MediaQuery.disableAnimationsOf(context) ? 0.5 : null,
            semanticsLabel: t('loading'),
          )
        : null,
  );
}
