import 'official_fleet_activity_section.dart';
import '../common/organization_communication.dart';
import 'official_fleet_manage_workspace.dart';

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';

import '../communities/community_visible_refresh.dart';
import 'official_fleet_holo_deck.dart';
import 'official_fleet_holo_header.dart';
import 'official_fleet_holo_paint.dart';
import 'official_fleet_command_row.dart';
import 'official_fleet_members_fallback.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_rally_views.dart';
import 'official_fleet_backdrop.dart';
import 'official_fleet_chat_workspace.dart';
import 'official_fleet_rail_previews.dart';
import 'official_fleet_screen_switch.dart';
import 'official_fleet_wheel_gate.dart';
import 'official_fleet_section_rail.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../common/organization_holo_art.dart';
import '../common/organization_section_stack.dart';
import '../common/organization_workspace_frame.dart';
import 'official_fleet_models.dart';
import 'official_fleet_members_section.dart';
import 'official_fleet_module.dart';
import 'official_fleet_workspace_sync_notice.dart';
import 'official_fleet_overview_models.dart';
import 'official_fleet_profile_section.dart';
import '../communities/community_ships_panel.dart';
import '../communities/community_ships_port.dart';
import '../communities/community_hangar_sharing_dialog.dart';
import '../communities/community_ships_copy.dart';
import '../common/organization_hangar_sharing.dart';
import 'official_fleet_ship_count.dart';
import 'unavailable_official_fleet_shared_ships.dart';
import 'official_fleet_ship_owner_access.dart';
import '../communities/community_ship_avatar_access.dart';
import 'official_fleet_support_views.dart';
import 'official_fleet_workspace_header.dart';
import 'official_fleet_workspace_navigation.dart';
import '../settings/local_privacy_controller.dart';
import 'official_fleet_first_sharing_choice.dart';
import 'official_fleet_manual_refresh.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class OfficialFleetPage extends StatefulWidget {
  const OfficialFleetPage({
    required this.module,
    this.sharedShipsPort,
    this.hangarSharingPort,
    this.privacy,
    super.key,
  });
  final CommunityShipsPort? sharedShipsPort;
  final OrganizationHangarSharingPort? hangarSharingPort;
  final OfficialFleetModule module;
  final LocalPrivacyController? privacy;
  @override
  State<OfficialFleetPage> createState() => _OfficialFleetPageState();
}

class _OfficialFleetPageState extends State<OfficialFleetPage> {
  OfficialFleetWorkspaceSection _section =
      OfficialFleetWorkspaceSection.members;
  String? _sourceRef;
  Object? _contextKey;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<OfficialFleetProjection>(
    valueListenable: widget.module.projection,
    builder: (context, projection, _) {
      Widget content;
      if (projection.availability == OfficialFleetAvailability.available) {
        final sourceRef = projection.fleet!.sourceRef;
        final contextKey = (widget.module, widget.module.contextRevision);
        if (_sourceRef != sourceRef || _contextKey != contextKey) {
          _sourceRef = sourceRef;
          _contextKey = contextKey;
          _section = OfficialFleetWorkspaceSection.members;
        }
        content = _FleetWorkspace(
          key: ValueKey((contextKey, sourceRef)),
          projection: projection,
          module: widget.module,
          section: _section,
          sharedShipsPort: widget.sharedShipsPort,
          hangarSharingPort: widget.hangarSharingPort,
          onSectionChanged: (value) => setState(() => _section = value),
        );
        // The holo header is full-bleed: the workspace owns its own insets.
        return OfficialFleetBackdrop(
          art: OrganizationHoloArt.fromUrl(
            projection.fleet?.profile?.backgroundUrl,
          ),
          child: widget.privacy == null
              ? content
              : OfficialFleetFirstSharingChoice(
                  key: ValueKey((contextKey, sourceRef, widget.privacy)),
                  controller: widget.privacy!,
                  sourceRef: sourceRef,
                  child: content,
                ),
        );
      } else {
        if (projection.availability != OfficialFleetAvailability.loading) {
          _sourceRef = null;
        }
        content = SingleChildScrollView(
          child: Column(
            children: [
              LoadingContentProbe(
                route: '/fleet',
                status:
                    projection.availability == OfficialFleetAvailability.loading
                    ? LoadingContentStatus.waiting
                    : LoadingContentStatus.unavailable,
                child: switch (projection.availability) {
                  OfficialFleetAvailability.loading =>
                    const OfficialFleetLoadingView(),
                  OfficialFleetAvailability.signedOut =>
                    const OfficialFleetSignedOutView(),
                  OfficialFleetAvailability.notMember =>
                    OfficialFleetNotMemberView(onRetry: widget.module.refresh),
                  _ => OfficialFleetUnavailableView(
                    failureKey:
                        projection.failureKey ??
                        'officialFleet.error.unavailable',
                    onRetry: widget.module.refresh,
                  ),
                },
              ),
              if (projection.availability !=
                      OfficialFleetAvailability.signedOut &&
                  projection.availability != OfficialFleetAvailability.loading)
                officialFleetOwnAnnouncementOutcomes(widget.module.communication),
              if (widget.hangarSharingPort?.available == true &&
                  projection.availability !=
                      OfficialFleetAvailability.signedOut &&
                  projection.availability != OfficialFleetAvailability.loading)
                StarBridgeActionButton(
                  controlKey: const ValueKey('official-fleet-own-sharing'),
                  onActivate: (_) => showStarBridgeDialog<bool>(
                    context,
                    useRootNavigator: false,
                    barrierDismissible: false,
                    builder: (_) => CommunityHangarSharingDialog.editor(
                      editor: widget.hangarSharingPort,
                    ),
                  ),
                  child: Text(communityShipsText(context, 'ownSharingTitle')),
                ),
            ],
          ),
        );
      }
      return OrganizationWorkspacePage(
        child: OrganizationWorkspaceSurface(child: content),
      );
    },
  );
}

class _FleetWorkspace extends StatefulWidget {
  const _FleetWorkspace({
    required this.projection,
    required this.module,
    required this.section,
    required this.onSectionChanged,
    this.sharedShipsPort,
    this.hangarSharingPort,
    super.key,
  });
  final OfficialFleetProjection projection;
  final OfficialFleetModule module;
  final OfficialFleetWorkspaceSection section;
  final ValueChanged<OfficialFleetWorkspaceSection> onSectionChanged;
  final CommunityShipsPort? sharedShipsPort;
  final OrganizationHangarSharingPort? hangarSharingPort;
  @override
  State<_FleetWorkspace> createState() => _FleetWorkspaceState();
}

class _FleetWorkspaceState extends State<_FleetWorkspace>
    with
        CommunityVisibleRefresh<_FleetWorkspace>,
        OfficialFleetMembersFallback<_FleetWorkspace> {
  @override
  Future<void> refreshMembers() => widget.module.members.refresh(silent: true);

  @override
  Stream<void>? get communityChanges =>
      widget.module.communication.backgroundAttentionManaged
      ? null
      : widget.module.communication.workspaceChanges;
  // The app-owned worker now observes official events and owns its bounded
  // compatibility fallback. The workspace must not add a second unread poll.
  @override
  bool get communityEventsHealthy =>
      widget.module.communication.backgroundAttentionManaged;
  @override
  Future<void> refreshVisibleCommunity() =>
      widget.module.communication.needsScopeRefresh
      ? widget.module.refresh()
      : widget.module.communication.refreshReadback();
  // Two screens: false is the top screen (banner, deck, command row and the
  // section rail); true is the detail screen (slim bar over the section).
  bool _detail = false, _entryPlayed = false, _bodyAtTop = true;
  final _wheel = OfficialFleetWheelGate();
  OfficialFleetWorkspaceSection? _lastVisited;
  double _pan = 0;
  final _openingWebsite = ValueNotifier(false);
  final _shipCount = OfficialFleetShipCount();
  late final _railChanges = Listenable.merge([widget.module.rally, _shipCount]);
  StarBridgeDialogRoute<void>? _detailsRoute;

  @override
  void dispose() {
    retireStarBridgeDialog(_detailsRoute);
    _openingWebsite.dispose();
    _shipCount.dispose();
    super.dispose();
  }

  Future<void> _openDetails() async {
    if (_detailsRoute != null) return;
    final fleet = widget.projection.fleet!;
    final contextRevision = widget.module.contextRevision;
    final strings = AppStrings.of(context);
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: false,
      onRouteCreated: (route) => _detailsRoute = route,
      builder: (context) => AnimatedBuilder(
        animation: Listenable.merge([
          _openingWebsite,
          widget.module.projection,
          widget.module.communication,
        ]),
        builder: (context, _) {
          final current = widget.module.projection.value;
          if (current.availability != OfficialFleetAvailability.available ||
              current.fleet?.sourceRef != fleet.sourceRef ||
              widget.module.contextRevision != contextRevision) {
            return const SizedBox.shrink();
          }
          return AlertDialog(
            key: const Key('official-fleet-details-dialog'),
            title: Text(strings.text('officialFleet.workspace.details')),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                key: const Key('official-fleet-profile-scroll'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OfficialFleetProfileSection(
                      fleet: current.fleet!,
                      observedAtUtc: current.observedAtUtc,
                      profileReadState: current.profileReadState,
                      isReading: current.isProfileReading,
                      profileObservedAtUtc: current.profileObservedAtUtc,
                    ),
                    if (widget.module.communication.announcementsAvailable) ...[
                      const SizedBox(height: 16),
                      widget.module.communication.announcement(expanded: true),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (widget.module.websiteAvailable)
                StarBridgeActionButton(
                  controlKey: const Key('official-fleet-open-website'),
                  onActivate: _openingWebsite.value
                      ? null
                      : (source) async {
                          if (_openingWebsite.value) return;
                          _openingWebsite.value = true;
                          final opened = await widget.module.openWebsite();
                          if (!mounted) return;
                          _openingWebsite.value = false;
                          if (!context.mounted ||
                              widget.module.contextRevision !=
                                  contextRevision ||
                              widget.module.projection.value.fleet?.sourceRef !=
                                  fleet.sourceRef) {
                            return;
                          }
                          if (!opened) {
                            showStarBridgeSnackBar(
                              context,
                              starBridgeTimedSnackBar(
                                content: Text(
                                  strings.text('officialFleet.website.openFailed'),
                                ),
                              ),
                              source: source,
                            );
                          }
                        },
                  child: Text(strings.text('officialFleet.website.open')),
                ),
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('official-fleet-details-close'),
                onActivate: (source) =>
                    dismissStarBridgeDialog(context, source: source),
                child: Text(strings.text('officialFleet.workspace.close')),
              ),
            ],
          );
        },
      ),
    );
    _detailsRoute = null;
  }

  @override
  Widget build(BuildContext context) {
    final fleet = widget.projection.fleet!;
    Widget viewport(Widget child, {EdgeInsetsGeometry? padding}) =>
        SingleChildScrollView(
          key: PageStorageKey((
            widget.module,
            widget.module.contextRevision,
            fleet.sourceRef,
            child.runtimeType,
          )),
          primary: false,
          padding: padding,
          child: child,
        );
    final communication = widget.module.communication;
    return AnimatedBuilder(
      animation: Listenable.merge([
        communication,
        widget.module.members.projection,
      ]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          // Narrow pages give the tabs the whole row; controls sit above.
          final stacked = constraints.maxWidth < 700;
          final scale = math.max(
            1.0,
            MediaQuery.textScalerOf(context).scale(1),
          );
          // RSI banners are 3:1 (1140x380): at width/3 the whole image shows.
          // The top screen gives it that height when the command row and the
          // section rail still fit below; smaller windows scale it down.
          final railCompact =
              constraints.maxWidth < OfficialFleetSectionRail.compactBelow;
          final topChrome =
              (240 +
                  (stacked ? 56 : 0) +
                  (railCompact ? OfficialFleetSectionRail.compactExtra : 0)) *
              scale;
          final maxBanner = math.max(
            110.0,
            math.min(
              constraints.maxWidth / 3,
              constraints.maxHeight - topChrome - 150 * scale,
            ),
          );
          final collapsed = _detail;
          // A screen tall enough for the whole banner hands the rest of its
          // height to the rail, which grows into section preview tiles.
          final tiles =
              !railCompact && maxBanner >= constraints.maxWidth / 3 - .5;
          final entry = collapsed || _entryPlayed
              ? OfficialFleetHoloEntry.none
              : widget.module.takeFirstVisitToday()
              ? OfficialFleetHoloEntry.full
              : OfficialFleetHoloEntry.quick;
          if (!collapsed) _entryPlayed = true;
          // Whatever does not fit is clipped, never squeezed or overflowed.
          double headerMax(bool collapsed) => math.max(
            64.0,
            collapsed
                ? constraints.maxHeight -
                      (stacked ? 56 : 0) * scale -
                      200 * scale
                : constraints.maxHeight,
          );
          return ValueListenableBuilder<OfficialFleetOverviewProjection>(
            valueListenable: widget.module.overview.projection,
            builder: (context, overview, _) {
              Widget actionsFor(bool collapsed) {
                final headerActions = OfficialFleetHeaderActions(
                  retained:
                      widget.projection.refreshFailed ||
                      widget.projection.profileRetained ||
                      overview.refreshFailed ||
                      communication.readOnly,
                  collapsed: collapsed,
                  onToggleCollapsed: () => collapsed
                      ? setState(() => _detail = false)
                      : _enter(widget.section),
                  onDetails: _openDetails,
                  onRefresh: widget.projection.isRefreshing
                      ? null
                      : () => officialFleetRefresh(context, widget.module),
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<
                      OfficialFleetMemberDirectoryProjection
                    >(
                      valueListenable: widget.module.members.projection,
                      builder: (context, members, _) =>
                          !collapsed &&
                              OfficialFleetCommandRow.holdsPlace(members)
                          ? const SizedBox.shrink()
                          : OfficialFleetRallyStartButton(
                              controller: widget.module.rally,
                            ),
                    ),
                    headerActions,
                  ],
                );
              }

              final rail =
                  ValueListenableBuilder<
                    OfficialFleetMemberDirectoryProjection
                  >(
                    valueListenable: widget.module.members.projection,
                    builder: (context, members, _) => ListenableBuilder(
                      listenable: _railChanges,
                      builder: (context, _) => _sectionRail(
                        context,
                        overview,
                        communication,
                        actionsFor(false),
                        members,
                        compact: railCompact,
                      ),
                    ),
                  );
              // Wide lower screens carry the tabs and controls in the bar.
              final barTabs = !stacked && constraints.maxWidth >= 1100 * scale;
              final deck = officialFleetHoloDeck(
                context,
                fleet: fleet,
                overview: overview,
                members: widget.module.members.projection.value,
                announcementEntry: communication.announcementsAvailable
                    ? communication.announcement()
                    : null,
              );
              Widget headerFor(bool collapsed) => ConstrainedBox(
                constraints: BoxConstraints(maxHeight: headerMax(collapsed)),
                child: UnconstrainedBox(
                  constrainedAxis: Axis.horizontal,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: collapsed
                      ? OfficialFleetHoloBar(
                          deck: deck,
                          tabs: barTabs ? _navigation() : null,
                          trailing: barTabs ? actionsFor(true) : null,
                        )
                      : OfficialFleetHoloHeader(
                          deck: deck,
                          maxBannerHeight: maxBanner,
                          entry: entry,
                        ),
                ),
              );
              // The wheel (or a touchpad swipe) anywhere on the workspace,
              // banner included, scrolls the header away; scrolling up at the
              // top of the members list brings it back. No button needed.
              Widget screen(bool collapsed) {
                final header = headerFor(collapsed);
                final actions = actionsFor(collapsed);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The top screen's header takes what the rows below
                    // leave, clipped rather than leaving a gap at the bottom.
                    if (collapsed || tiles) header else Flexible(child: header),
                    if (stacked && collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: actions,
                        ),
                      ),
                    if (!collapsed)
                      ValueListenableBuilder<
                        OfficialFleetMemberDirectoryProjection
                      >(
                        valueListenable: widget.module.members.projection,
                        builder: (context, members, _) =>
                            OfficialFleetCommandRow(
                              members: members,
                              rally: widget.module.rally,
                              sourceRef: fleet.sourceRef,
                              onAnnounce:
                                  communication.announcementManagementVisible
                                  ? () => _enter(
                                      OfficialFleetWorkspaceSection.broadcasts,
                                    )
                                  : null,
                            ),
                      ),
                    // The activity page carries the rally itself.
                    if (!collapsed ||
                        widget.section !=
                            OfficialFleetWorkspaceSection.broadcasts)
                      OfficialFleetRallyStrip(controller: widget.module.rally),
                    if (collapsed)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            stacked ? 4 : 12,
                            20,
                            20,
                          ),
                          child: OrganizationWorkspaceSurface(
                            child: _frame(
                              fleet,
                              viewport,
                              actions: stacked || barTabs ? null : actions,
                              navigation: !barTabs,
                            ),
                          ),
                        ),
                      )
                    else if (tiles)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                          child: rail,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        child: rail,
                      ),
                  ],
                );
              }

              return Listener(
                // Blank parts of a screen hit-test through to the backdrop;
                // the wheel still belongs to the switch (2026-10-24).
                behavior: HitTestBehavior.translucent,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _onWheel(event.scrollDelta.dy, collapsed);
                  }
                },
                onPointerPanZoomUpdate: (event) {
                  _pan += event.panDelta.dy;
                  if (_pan.abs() < 24) return;
                  _onWheel(-_pan, collapsed);
                  _pan = 0;
                },
                onPointerPanZoomEnd: (_) => _pan = 0,
                child: OfficialFleetScreenSwitch(
                  lower: collapsed,
                  // The upper screen is what a visit lands on; the members
                  // list (and its probe) only paints on the lower screen.
                  upper: (_) => LoadingContentProbe(
                    route: '/fleet',
                    status:
                        widget.projection.refreshFailed ||
                            widget.projection.profileRetained
                        ? LoadingContentStatus.partial
                        : LoadingContentStatus.data,
                    items: 1,
                    child: screen(false),
                  ),
                  lowerBuilder: (_) => screen(true),
                  banner: OrganizationHoloArt.fromUrl(fleet.profile?.bannerUrl),
                  bannerHeight: math.min(maxBanner, constraints.maxWidth / 3),
                  barHeight: 64 * scale,
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _onWheel(double dy, bool collapsed) {
    if (dy > 0 && !collapsed) {
      _enter(widget.section);
    } else if (dy < 0 && collapsed && _wheel.up(-dy, bodyAtTop: _bodyAtTop)) {
      setState(() => _detail = false);
    }
  }

  void _enter(OfficialFleetWorkspaceSection section) {
    setState(() {
      _detail = true;
      _bodyAtTop = true;
      _lastVisited = section;
    });
    if (section != widget.section) widget.onSectionChanged(section);
  }

  bool _onBodyScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) _wheel.bodyMoved();
    // Visual top: reversed lists (chat) start at their newest end.
    _bodyAtTop =
        (metrics.axisDirection == AxisDirection.up
            ? metrics.extentAfter
            : metrics.extentBefore) <=
        0;
    return false;
  }

  Widget _sectionRail(
    BuildContext context,
    OfficialFleetOverviewProjection overview,
    OrganizationCommunication communication,
    Widget actions,
    OfficialFleetMemberDirectoryProjection members, {
    required bool compact,
  }) => OfficialFleetSectionRail(
    enterLabel: AppStrings.of(context).text('officialFleet.rail.enter'),
    lastVisited: _lastVisited,
    trailing: actions,
    compact: compact,
    onSelected: _enter,
    items: OfficialFleetRailPreviews.items(
      context,
      overview: overview,
      communication: communication,
      members: members,
      sourceRef: widget.projection.fleet!.sourceRef,
      isOwner: widget.module.rally.eligibility.canStart,
      rally: widget.module.rally,
      chatTileOnScreen: !_detail,
      shipCount: _shipCount,
      shipsPort: widget.sharedShipsPort,
    ),
  );

  @override
  void didUpdateWidget(covariant _FleetWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) _bodyAtTop = true;
  }

  void _toMembers() =>
      widget.onSectionChanged(OfficialFleetWorkspaceSection.members);

  Widget _navigation() {
    final communication = widget.module.communication;
    return OfficialFleetWorkspaceNavigation(
      selected: widget.section,
      chatUnreadCount: communication.chatUnreadCount,
      availableSections: {
        OfficialFleetWorkspaceSection.members,
        OfficialFleetWorkspaceSection.ships,
        OfficialFleetWorkspaceSection.manage,
        if (communication.chatAvailable) OfficialFleetWorkspaceSection.channel,
        if (officialFleetActivityAvailable(communication, widget.module.rally))
          OfficialFleetWorkspaceSection.broadcasts,
      },
      onSelected: widget.onSectionChanged,
    );
  }

  Widget _frame(
    OfficialFleetSummary fleet,
    Widget Function(Widget child, {EdgeInsetsGeometry? padding}) viewport, {
    required Widget? actions,
    required bool navigation,
  }) {
    final communication = widget.module.communication;
    return OrganizationWorkspaceFrame(
      key: const Key('official-fleet-workspace'),
      header: const SizedBox.shrink(),
      actions: actions,
      feedback: [
        officialFleetAnnouncementOutcomesFor(communication, widget.section),
        ValueListenableBuilder<OfficialFleetOverviewProjection>(
          valueListenable: widget.module.overview.projection,
          builder: (context, overview, _) => OfficialFleetWorkspaceSyncNotice(
            projection: widget.projection,
            overview: overview,
            communication: communication,
            key: const Key('official-fleet-refreshing'),
          ),
        ),
      ],
      navigation: navigation ? _navigation() : null,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onBodyScroll,
        child: OrganizationSectionStack(
          key: ValueKey((
            widget.module,
            widget.module.contextRevision,
            fleet.sourceRef,
          )),
          selected: widget.section.name,
          sections: {
            'manage': (_) => OfficialFleetManageWorkspace(
              fleet: fleet,
              projection: widget.projection,
              communication: communication,
              rally: widget.module.rally,
              hangarSharingPort: widget.hangarSharingPort,
              onBack: () async => widget.onSectionChanged(
                OfficialFleetWorkspaceSection.members,
              ),
            ),
            if (communication.chatAvailable)
              'channel': (_) => OfficialFleetChatWorkspace(
                pinned: communication.announcementsAvailable
                    ? communication.announcement()
                    : null,
                resetKey: fleet.sourceRef,
                online: OfficialFleetOnlinePane.dock(
                  widget.module.members.projection,
                  _toMembers,
                ),
                chat: communication.chat(onBack: _toMembers),
              ),
            if (officialFleetActivityAvailable(
              communication,
              widget.module.rally,
            ))
              'broadcasts': (_) => viewport(
                OfficialFleetActivitySection(
                  rally: widget.module.rally,
                  communication: communication,
                ),
                padding: const EdgeInsetsDirectional.only(end: 16),
              ),
            'members': (_) => viewport(
              OfficialFleetMembersSection(
                sourceRef: fleet.sourceRef,
                module: widget.module.members,
                retained: widget.projection.refreshFailed,
                officialMemberCount: fleetRsiMemberCount(widget.module, fleet),
              ),
              padding: const EdgeInsetsDirectional.only(end: 16),
            ),
            // Panel owns its bounded scroll viewport, as it does in community.
            'ships': (_) => CommunityShipsPanel(
              port: communication.verifiedWorkspaceTargetRef == null
                  ? const UnavailableOfficialFleetSharedShips()
                  : widget.sharedShipsPort ??
                        const UnavailableOfficialFleetSharedShips(),
              // Missing context is an unavailable display; no fabricated target
              // is ever sent to a real public ships adapter.
              targetRef: communication.verifiedWorkspaceTargetRef ?? '',
              name: fleet.name,
              onBack: _toMembers,
              onRefreshMembership: widget.module.refresh,
              retryInvalidatedScope: true,
              ownerTargetFactory:
                  widget.sharedShipsPort is OfficialFleetShipOwnerAccess
                  ? (widget.sharedShipsPort as OfficialFleetShipOwnerAccess)
                        .ownerTarget
                  : null,
              avatarAccess:
                  widget.sharedShipsPort is OfficialFleetShipOwnerAccess
                  ? (widget.sharedShipsPort as OfficialFleetShipOwnerAccess)
                        .avatarAccess
                  : const CommunityShipAvatarAccess(),
              includeSocialActions: false,
              hangarSharingPort: widget.hangarSharingPort,
              hangarSharingSourceRef: fleet.sourceRef,
            ),
          },
        ),
      ),
    );
  }
}
