import 'community_initial_read_wait.dart';
import 'community_activity_section.dart';
import '../common/organization_workspace_frame.dart';
import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'community_workspace_members.dart';
import 'community_workspace_information.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../common/social_read_activity.dart';

import '../../platform/window/native_viewport_visibility.dart';

import 'community_workspace_controller.dart';
import 'community_activity_port.dart';
import 'community_workspace_session.dart';
import 'community_workspace_copy.dart';
import 'community_announcements_port.dart';
import 'community_workspace_port.dart';
import 'community_settings_workspace.dart';
import 'community_workspace_management_chrome.dart';
import 'community_visible_refresh.dart';
import 'community_ownership_exit_port.dart';
import 'community_ownership_exit_dialog.dart';
import 'community_disband_port.dart';
import 'community_disband_dialog.dart';
import 'community_chat_port.dart';
import 'community_chat_panel.dart';
import 'community_chat_workspace.dart';
import 'community_ships_port.dart';
import 'community_ships_panel.dart';
import 'community_ships_copy.dart' show communityShipsCulture;
import 'community_section_stack.dart';
import 'community_section_navigation.dart';
import 'community_holo_workspace.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';
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
    this.holo = false,
    super.key,
  });

  /// The main fleet's two-screen holo shell (joined communities on the
  /// community page, user decision 2026-10-23).
  final bool holo;
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
  late SocialReadActivityBinding _readActivity;
  ValueGetter<InteractionSource>? _membershipSource;
  int _membershipRevision = 0;
  bool _ownsModel = true;
  final search = TextEditingController();
  bool _leaving = false, _refreshingMembership = false;
  bool _automaticRenewalAttempted = false;
  String _section = 'members';
  String get _organization => widget.organizationKey ?? model.targetRef;
  StarBridgeDialogRoute<void>? _detailsRoute;
  StarBridgeDialogRoute<bool>? _ownershipRoute, _disbandRoute;
  final _memberRoutes = <StarBridgeDialogRoute<bool>>{};
  void _retireMemberRoutes() {
    for (final route in _memberRoutes.toList()) {
      retireStarBridgeDialog(route);
    }
  }

  Future<bool?> _openMemberDialog(WidgetBuilder builder) async {
    StarBridgeDialogRoute<bool>? opened;
    try {
      return await showStarBridgeDialog<bool>(
        context,
        barrierDismissible: false,
        builder: builder,
        onRouteCreated: (route) {
          opened = route;
          _memberRoutes.add(route);
        },
      );
    } finally {
      _memberRoutes.remove(opened);
    }
  }

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
    if (_refreshingMembership || _leaving) return;
    // Reuse the existing account-scoped page and media; never rebind the
    // directory or ask about drafts for a background metadata read.
    if (model.error == 'identityUnavailable' || model.error == 'notAllowed') {
      return;
    }
    await model.refreshFromActivity();
  }

  @override
  Stream<void>? get communityChanges => widget.port is CommunityActivityPort
      ? (widget.port as CommunityActivityPort).workspaceChanges
      : null;
  @override
  bool get communityEventsHealthy =>
      widget.port is CommunityActivityPort &&
      (widget.port as CommunityActivityPort).activityHealthy;

  Future<bool> confirmLeave() async =>
      await (_settingsKey.currentState?.confirmLeave() ??
          _chatKey.currentState?.confirmLeave() ??
          Future.value(true));

  Future<void> _refreshWorkspace() => runStarBridgeActivation(
    captureStarBridgeActivationSource()(),
    _refreshWorkspaceWithOrigin,
  );

  Future<void> _refreshWorkspaceWithOrigin() async {
    if (_refreshingMembership || _leaving) return;
    final previous = model;
    final previousTarget = widget.targetRef;
    final source = captureStarBridgeActivationSource();
    _membershipSource = source;
    _membershipRevision++;
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
      if (identical(_membershipSource, source)) _membershipSource = null;
      if (mounted) setState(() => _refreshingMembership = false);
    }
  }

  Future<void> _selectSection(String section) => runStarBridgeActivation(
    StarBridgeActivationOrigin.sourceOf(context),
    () => _selectSectionWithOrigin(section),
  );

  Future<void> _selectSectionWithOrigin(String section) async {
    if (section == _section) return;
    final current = model;
    if (!await confirmLeave() || !mounted || current != model) return;
    setState(() {
      _section = section;
      _setSectionSource(currentStarBridgeActivationSource);
      if (section != 'manage') model.selectedSection = section;
      // High-frequency navigation keeps the same compact overview and hit targets.
    });
  }

  final _assignmentInvalidations = StreamController<void>.broadcast();
  bool _headerExpanded = false;
  InteractionSource? _sectionSource;
  int _sectionSourceRevision = 0;
  void _setSectionSource(InteractionSource source) {
    _sectionSource = source;
    final revision = ++_sectionSourceRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _sectionSourceRevision) _sectionSource = null;
    });
  }

  String t(String key) => workspaceText(context, key);
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sectionSource = null;
    _sectionSourceRevision++;
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
    _readActivity = SocialReadActivityBinding(
      model,
      () => model.showProgress,
      initialRead:
          !model.busy && model.workspace == null && model.error == null,
      phaseIdentity: () => model.readEpoch,
    );
    // Joining an existing request is not the action that initiated it.
    if (model.showProgress) {
      _readActivity.source = InteractionSource.programmatic;
    }
    model.addListener(_changed);
    unawaited(model.enter(widget.targetRef));
    // A retained failure can need reference renewal before any listener fires.
    if (model.error == 'refreshRequired') _changed();
    _scheduleSectionPreparation();
  }

  void _changed() {
    _scheduleSectionPreparation();
    if (model.workspace == null) {
      _dismissDetails();
      // A rejected workspace refresh can revoke the visible authority without
      // a separate account invalidation event. Old member previews may not
      // survive that loss, even if their own controller has not reread yet.
      _retireMemberRoutes();
    }
    if (model.error == 'identityUnavailable') {
      search.clear();
      _retireMemberRoutes();
      retireStarBridgeDialog(_ownershipRoute);
      retireStarBridgeDialog(_disbandRoute);
    }
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
      _retireMemberRoutes();
      retireStarBridgeDialog(_ownershipRoute);
      retireStarBridgeDialog(_disbandRoute);
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
      _readActivity.dispose();
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
    _retireMemberRoutes();
    _dismissDetails();
    retireStarBridgeDialog(_ownershipRoute);
    retireStarBridgeDialog(_disbandRoute);
    _assignmentInvalidations.add(null);
    unawaited(_assignmentInvalidations.close());
    _readActivity.dispose();
    model.removeListener(_changed);
    model.setMemberListHovered(false);
    if (_ownsModel) model.dispose();
    search.dispose();
    super.dispose();
  }

  void _dismissDetails() {
    final route = _detailsRoute;
    _detailsRoute = null;
    retireStarBridgeDialog(route);
  }

  Future<void> _openDetails(Widget details) async {
    if (_detailsRoute != null || model.workspace == null) return;
    StarBridgeDialogRoute<void>? opened;
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        key: const Key('community-details-dialog'),
        title: Text(workspaceText(context, 'details')),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(child: details),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('community-details-refresh'),
            onActivate: (source) {
              dismissStarBridgeDialog(context, source: source);
              unawaited(_refreshWorkspace());
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StandardIcon(StandardIconSemantic.refresh, size: 18),
                const SizedBox(width: 8),
                Text(workspaceText(context, 'refresh')),
              ],
            ),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('community-workspace-details-close'),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
      onRouteCreated: (route) => _detailsRoute = opened = route,
    );
    if (identical(_detailsRoute, opened)) _detailsRoute = null;
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
      await showStarBridgeDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (_) => CommunityOwnershipExitDialog(
          port: port as CommunityOwnershipExitPort,
          workspacePort: port,
          targetRef: target,
          contextInvalidations: _assignmentInvalidations.stream,
        ),
        onRouteCreated: (route) => _ownershipRoute = route,
      );
      _ownershipRoute = null;
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
      await showStarBridgeDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (_) => CommunityDisbandDialog(
          port: port as CommunityDisbandPort,
          targetRef: target,
          contextInvalidations: _assignmentInvalidations.stream,
        ),
        onRouteCreated: (route) => _disbandRoute = route,
      );
      _disbandRoute = null;
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
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: value.trim()));
      message = all ? 'copiedAll' : 'copied';
    } catch (_) {
      message = 'contactCopyFailed';
    }
    if (mounted && model == current && model.workspace == currentWorkspace) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(starBridgeTimedSnackBar(content: Text(t(message))));
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
            CommunityInitialReadWait.workspace(
              key: ValueKey((
                model,
                model.busy ? _readActivity.revision : _membershipRevision,
                _refreshingMembership,
              )),
              source: model.busy
                  ? _readActivity.source
                  : _membershipSource?.call() ?? InteractionSource.programmatic,
              opening: model.busy && _readActivity.opening,
              label: t(_refreshingMembership ? 'renewing' : 'loading'),
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Text(t(_refreshingMembership ? 'renewing' : 'loading')),
            ),
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
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('community-workspace-retry'),
                onActivate: (_) => _refreshWorkspace(),
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
    final canOpenActivity = communityActivityAvailable(widget.port);
    final section =
        (_section == 'chat' && !canOpenChat) ||
            (_section == 'ships' && !canOpenShips) ||
            (_section == 'broadcast' && !canOpenActivity)
        ? 'members'
        : _section;
    final information = CommunityWorkspaceInformation(
      context: context,
      model: model,
      workspace: workspace,
      copy: _copy,
    );
    final members = CommunityWorkspaceMembers(
      context: context,
      currentModel: () => model,
      isMounted: () => mounted,
      port: widget.port,
      organizationKey: widget.organizationKey,
      search: search,
      contextInvalidations: _assignmentInvalidations.stream,
      openDialog: _openMemberDialog,
      onGovernanceChanged: () async => await widget.onGovernanceChanged?.call(),
      refreshingIndicator: model.showProgress
          ? KeyedSubtree(
              key: ValueKey((model, _readActivity.revision)),
              child: ExcludeSemantics(
                child: SocialReadActivity(
                  source: _readActivity.source,
                  opening: false,
                  label: t('loading'),
                ),
              ),
            )
          : null,
    ).build();
    final showOwnershipExit =
        workspace.access['isOwner'] == true &&
        widget.port is CommunityOwnershipExitPort &&
        (widget.port as CommunityOwnershipExitPort).ownershipExitAvailable;
    final showDisband =
        workspace.access['isOwner'] == true &&
        widget.port is CommunityDisbandPort &&
        (widget.port as CommunityDisbandPort).disbandAvailable;
    final management = CommunitySettingsWorkspace(
      key: _settingsKey,
      port: widget.port,
      workspace: workspace,
      targetRef: model.targetRef,
      images: model.image,
      logoLoading: model.imageLoading('logo'),
      logoFailed: model.imageFailed('logo'),
      contextInvalidations: _assignmentInvalidations.stream,
      onMembers: () => _selectSection('members'),
      onNameConfirmed: widget.onNameConfirmed,
      onWorkspaceChanged: (images) =>
          unawaited(model.load(refreshImages: images)),
      hasDangerActions: showOwnershipExit || showDisband,
      dangerActions: communityWorkspaceDangerActions(
        context,
        showOwnershipExit: showOwnershipExit,
        showDisband: showDisband,
        busy: _leaving,
        onOwnershipExit: _leaveWithSuccessor,
        onDisband: _disband,
      ),
    );
    final manageView = Column(
      key: const Key('community-internal-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        communityWorkspaceManagementHeader(
          context,
          name: workspace.name,
          onBack: () => _selectSection('members'),
          onRefresh: _refreshWorkspace,
        ),
        const Divider(height: 24),
        _refreshProgress(),
        Expanded(child: management),
      ],
    );
    final sections = communityWorkspaceSections(
      chat: canOpenChat,
      ships: canOpenShips,
      // Everyone has their own settings here; what they may manage decides
      // which sections show inside (user 2026-10-31).
      manage: true,
      announcements: canOpenActivity,
    );
    final navigation = CommunitySectionNavigation(
      skewed: true,
      chatUnreadCount: model.chatUnreadCount,
      sections: sections,
      selected: section,
      onSelected: _selectSection,
      changeSource: _sectionSource,
    );
    Widget frame(Widget header, {bool tabs = true}) {
      return OrganizationWorkspaceFrame(
        key: const Key('community-internal-workspace'),
        header: header,
        navigation: tabs ? navigation : null,
        actions: tabs ? widget.actions : null,
        feedback: [
          _refreshProgress(),
          if (model.error != null)
            Row(
              children: [
                Expanded(child: Text(t('refreshFailed'))),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('community-workspace-refresh-error'),
                  onActivate: model.busy ? null : (_) => model.load(),
                  child: Text(t('refresh')),
                ),
              ],
            ),
        ],
        body: CommunitySectionStack(
          key: ValueKey((widget.port, _organization)),
          selected: section,
          sections: {
            if (canOpenChat)
              'chat': (_) => CommunityChatWorkspace(
                key: ValueKey('chat-workspace:$_organization'),
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
                  onBackSource: (source) => setState(() {
                    _setSectionSource(source);
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
            if (canOpenActivity)
              'broadcast': (_) => CommunityActivitySection(
                key: ValueKey('activity:$_organization'),
                port: widget.port as CommunityAnnouncementsPort,
                model: model,
              ),
            'members': (_) => members,
          },
        ),
      );
    }

    if (widget.holo) {
      return CommunityHoloWorkspace(
        port: widget.port,
        model: model,
        workspace: workspace,
        section: section,
        sections: sections,
        onSection: _selectSection,
        tabs: navigation,
        actions: widget.actions,
        onRefresh: _refreshWorkspace,
        onDetails: _openDetails,
        information: information,
        body: (context, {required tabsInBar}) => section == 'manage'
            ? manageView
            : frame(const SizedBox.shrink(), tabs: !tabsInBar),
      );
    }
    if (section == 'manage') return manageView;
    return frame(
      information.header(
        port: widget.port,
        expanded: _headerExpanded,
        onToggleExpansion: () =>
            setState(() => _headerExpanded = !_headerExpanded),
        onRefresh: _refreshWorkspace,
        onDetails: _openDetails,
      ),
    );
  }

  Widget _refreshProgress() =>
      communityRefreshProgress(model, _readActivity, t('loading'));
}
