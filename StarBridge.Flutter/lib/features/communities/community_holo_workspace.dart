import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_chat_preview.dart';
import '../common/organization_holo_art.dart';
import '../common/organization_holo_deck.dart';
import '../official_fleet/official_fleet_models.dart';
import '../official_fleet/official_fleet_section_rail.dart';
import '../official_fleet/organization_holo_shell.dart';
import 'community_announcements_dialog.dart';
import 'community_announcements_port.dart';
import 'community_admissions_port.dart';
import 'community_management_dialog.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_workspace_controller.dart';
import 'community_workspace_copy.dart';
import 'community_ship_owner_avatar.dart';
import 'community_ships_copy.dart';
import 'community_workspace_image.dart';
import 'community_workspace_information.dart';
import 'community_workspace_port.dart';

/// Community workspace sections and the shared shell's sections: the same
/// five places as the main fleet (user decision 2026-10-23, communities use
/// exactly the main fleet's two-screen look).
const communityHoloSections = <String, OfficialFleetWorkspaceSection>{
  'members': OfficialFleetWorkspaceSection.members,
  'chat': OfficialFleetWorkspaceSection.channel,
  'ships': OfficialFleetWorkspaceSection.ships,
  'broadcast': OfficialFleetWorkspaceSection.broadcasts,
  'manage': OfficialFleetWorkspaceSection.manage,
};

String _sectionId(OfficialFleetWorkspaceSection section) =>
    communityHoloSections.entries
        .firstWhere((entry) => entry.value == section)
        .key;

/// Whether the viewer may open the community's management section.
/// A management grant, not membership: creating invites is open to every
/// member under the common "all members" policy, so it alone never opens the
/// management tab (user report 2026-10-29); those members get
/// [communityCanOnlyInvite]'s deck action instead.
bool communityCanManage(CommunityWorkspace workspace) => const [
  'isOwner',
  'canEditProfile',
  'canEditLogo',
  'canEditBanner',
  'canReviewApplications',
  'canRemoveMembers',
  'canManageAnnouncements',
  'canViewLogs',
].any((key) => workspace.access[key] == true);

bool communityCanOnlyInvite(CommunityWorkspace workspace) =>
    !communityCanManage(workspace) &&
    workspace.access['canCreateInvite'] == true;

/// The workspace sections and whether each can be opened, in tab order.
Map<String, bool> communityWorkspaceSections({
  required bool chat,
  required bool ships,
  required bool manage,
  bool announcements = false,
}) => {
  'members': true,
  'chat': chat,
  'ships': ships,
  // The organization's activity page: what the port really offers.
  'broadcast': announcements,
  if (manage) 'manage': true,
};

/// A joined community in the main fleet's holo shell: its banner and logo,
/// code, counts and current announcement on the deck; the five sections in
/// the rail; the classic workspace body on the lower screen's surface.
class CommunityHoloWorkspace extends StatelessWidget {
  const CommunityHoloWorkspace({
    required this.port,
    required this.model,
    required this.workspace,
    required this.section,
    required this.sections,
    required this.onSection,
    required this.tabs,
    required this.body,
    required this.onRefresh,
    required this.onDetails,
    required this.information,
    this.actions,
    super.key,
  });

  final CommunityWorkspacePort port;
  final CommunityWorkspaceController model;
  final CommunityWorkspace workspace;
  final String section;

  /// Which sections can be opened (as given to the section tabs).
  final Map<String, bool> sections;
  final ValueChanged<String> onSection;
  final Widget tabs;
  final Widget Function(BuildContext context, {required bool tabsInBar}) body;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Widget) onDetails;

  /// The organization's facts: online, activity and contacts stay visible on
  /// the upper screen; details and announcements open from the bar.
  final CommunityWorkspaceInformation information;

  /// Membership commands (leave, …) from the community page.
  final Widget? actions;

  // The broadcast tile names the same current announcement as the deck's
  // bar (user report 2026-10-28: the bar showed one, the tile said none).
  @override
  Widget build(BuildContext context) {
    final announcements = model.announcements;
    return announcements == null
        ? _shell(context)
        : _AfterFrameListener(
            listenable: announcements,
            // Only the broadcast entry reads the controller; a background
            // read that changed nothing must not rebuild the deck.
            select: () => (
              announcements.page?.current?.title,
              announcements.page?.current?.announcementRef,
              announcements.error,
            ),
            builder: _shell,
          );
  }

  Widget _shell(BuildContext context) {
    String t(String key) => workspaceText(context, key);
    String fleet(String key) => AppStrings.of(context).text(key);
    final online = workspace.members.where((member) => member.online).length;
    final inGame = workspace.members
        .where(
          (member) =>
              member.online && member.liveStatus.toLowerCase() == 'ingame',
        )
        .length;
    final announcements =
        port is CommunityAnnouncementsPort &&
        (port as CommunityAnnouncementsPort).announcementsAvailable;
    final owner = workspace.access['isOwner'] == true;
    final activity = information.activityText;
    final viewerActivity = information.viewerActivityText;
    final ships = sections['ships'] == true;
    if (ships) model.loadShipSummary(communityShipsCulture(context));
    final summary = model.shipSummary;
    final shipsInGame =
        summary?.available
            .where((s) => communityShipPresenceKey(s) == 'presence.inGame')
            .length ??
        0;
    final contacts = information.contactEntries;
    final unread = model.chatUnreadCount;
    final banner = OrganizationHoloArt.fromBytes(model.image('banner'));
    final deck = OrganizationHoloDeck(
      name: workspace.name,
      code: workspace.code,
      banner: banner,
      logo: OrganizationHoloArt.fromBytes(model.image('logo')),
      tag: owner ? t('owner') : null,
      line: announcements
          ? (_) => CommunityAnnouncementEntry(
              key: ValueKey('holo-announcements:${model.targetRef}'),
              controller: model.announcements,
              port: port as CommunityAnnouncementsPort,
              targetRef: model.targetRef,
            )
          : workspace.description.isEmpty
          ? null
          : (narrow) => Text(
              workspace.description,
              maxLines: narrow ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
      readoutsKey: const Key('community-header-information'),
      readouts: [
        OrganizationHoloReadout(
          t('activity'),
          activity.isEmpty ? t('hidden') : activity,
          muted: activity.isEmpty,
        ),
        if (viewerActivity.isNotEmpty)
          OrganizationHoloReadout(t('viewerTime'), viewerActivity),
        if (contacts.isEmpty)
          OrganizationHoloReadout(t('contacts'), t('hidden'), muted: true),
        for (final (platform, value) in contacts)
          OrganizationHoloReadout(
            platform,
            value,
            onCopy: () => information.copy(value),
            copyLabel: t('copy'),
            copyKey: ValueKey('community-copy-contact-$platform-$value'),
          ),
      ],
      stats: [
        OrganizationHoloStat(t('members'), workspace.totalCount),
        OrganizationHoloStat(t('online'), online, accent: true),
        OrganizationHoloStat(t('gaming'), inGame),
      ],
    );
    final unavailable = t('sectionUnavailable');
    OfficialFleetRailItem item(
      String id, {
      required String summary,
      String note = '',
      Widget? preview,
      Widget Function(double height)? previewFit,
      bool highlight = false,
      int count = 0,
    }) => OfficialFleetRailItem(
      section: communityHoloSections[id]!,
      label: t('section.$id'),
      summary: summary,
      note: note,
      preview: preview,
      previewFit: previewFit,
      highlight: highlight,
      count: count,
      enabled: sections[id] == true,
      hint: sections[id] == true ? '' : unavailable,
    );
    final rail = [
      item(
        'members',
        summary: fleet('officialFleet.rail.members')
            .replaceAll('{count}', '${workspace.totalCount}')
            .replaceAll('{online}', '$online'),
        note: fleet('officialFleet.tile.presence')
            .replaceAll('{inGame}', '$inGame')
            .replaceAll('{online}', '$online'),
        preview: _OnlineAvatars(
          model: model,
          members: [
            for (final member in workspace.members)
              if (member.online) member,
          ],
          tally: fleet('officialFleet.tile.presence')
              .replaceAll('{inGame}', '$inGame')
              .replaceAll('{online}', '$online'),
        ),
      ),
      item(
        'chat',
        summary: unread > 0
            ? fleet('officialFleet.rail.unread')
                  .replaceAll('{count}', '$unread')
            : t('holo.chat'),
        highlight: unread > 0,
        count: unread,
        note: fleet('officialFleet.tile.chatNote'),
        previewFit: (height) => OrganizationChatPreview(
          key: const Key('community-tile-chat'),
          messages: model.chatRecent,
          unread: unread,
          height: height,
        ),
      ),
      item(
        'ships',
        summary: !ships
            ? fleet('officialFleet.rail.shipsNone')
            : summary == null
            ? t(
                model.shipSummaryFailed
                    ? 'holo.shipsFailed'
                    : 'holo.shipsLoading',
              )
            : summary.ships.isEmpty
            ? t('holo.shipsNone')
            : t('holo.ships').replaceAll('{count}', '${summary.ships.length}'),
        note: fleet('officialFleet.tile.shipsNote'),
        preview: summary == null || summary.ships.isEmpty
            ? null
            : CommunityHoloShipsPreview(
                online: summary.available.length - shipsInGame,
                inGame: shipsInGame,
                offline: summary.ownerOffline,
              ),
      ),
      item(
        'broadcast',
        summary:
            (announcements
                ? model.announcements?.page?.current?.title
                : null) ??
            fleet('officialFleet.rail.noAnnouncement'),
        note: fleet('officialFleet.tile.broadcastNote'),
      ),
      item(
        'manage',
        summary: owner ? t('holo.owner') : fleet('officialFleet.rail.settings'),
        note: fleet('officialFleet.tile.settingsNote'),
      ),
    ];
    return OrganizationHoloShell(
      key: ValueKey('community-holo:${model.targetRef}'),
      deck: deck,
      // The page background prefers the dedicated background image.
      backdrop:
          OrganizationHoloArt.fromBytes(model.image('background')) ?? banner,
      railItems: rail,
      section:
          communityHoloSections[section] ??
          OfficialFleetWorkspaceSection.members,
      onSection: (value) => onSection(_sectionId(value)),
      tabs: tabs,
      body: body,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?actions,
          if (communityCanOnlyInvite(workspace) &&
              port is CommunityAdmissionsPort)
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('community-holo-invite'),
              onActivate: (source) => showStarBridgeDialog<void>(
                context,
                source: source,
                builder: (_) => CommunityManagementDialog(
                  port: port as CommunityAdmissionsPort,
                  targetRef: model.targetRef,
                  name: workspace.name,
                  initialSection: 'invites',
                  sections: const ['invites'],
                ),
              ),
              child: Text(t('inviteMembers')),
            ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('community-holo-details'),
            onActivate: (_) => onDetails(information.detailsPanel(port)),
            child: Text(t('details')),
          ),
          StarBridgeIconAction(
            controlKey: const Key('community-holo-refresh'),
            label: t('refresh'),
            onActivate: model.busy ? null : (_) => onRefresh(),
            icon: const StandardIcon(StandardIconSemantic.refresh, size: 20),
          ),
        ],
      ),
    );
  }
}

/// The members tile's preview: online members' avatars in their own shape
/// (never clipped), as many as fit, then +N, over the in-game/online tally
/// (user decision 2026-10-28: the avatars stay, under the members tile).
class _OnlineAvatars extends StatelessWidget {
  const _OnlineAvatars({
    required this.model,
    required this.members,
    required this.tally,
  });

  final CommunityWorkspaceController model;
  final List<CommunityWorkspaceMember> members;
  final String tally;

  @override
  Widget build(BuildContext context) {
    final muted = context.tokens.colors.textDisabled;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: muted);
    return Column(
      key: const Key('community-tile-members'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final fit = ((box.maxWidth - 36) / 28).floor().clamp(1, 7);
            final shown = members.take(fit).toList();
            final rest = members.length - shown.length;
            return Row(
              children: [
                for (final (index, member) in shown.indexed)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: index == 0 ? 0 : 4,
                    ),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CommunityWorkspaceImage(
                        bytes: model.image(member.memberRef),
                        decoder: model.avatars.images.decode,
                        peek: model.avatars.images.peek,
                        maxWidth: 48,
                        loading: model.imageLoading(member.memberRef),
                        loadFailed: model.imageFailed(member.memberRef),
                        icon: StandardIconSemantic.person,
                      ),
                    ),
                  ),
                if (rest > 0) ...[
                  const SizedBox(width: 8),
                  Text('+$rest', style: small),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(tally, style: small),
      ],
    );
  }
}

/// Rebuilds on [listenable] without marking itself during another build:
/// the announcements controller can change while the page is building
/// (it is created or replaced on read), so a change then waits a frame.
class _AfterFrameListener extends StatefulWidget {
  const _AfterFrameListener({
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;

  /// What the builder reads; a change that leaves it equal is ignored.
  final Object? Function() select;
  final WidgetBuilder builder;

  @override
  State<_AfterFrameListener> createState() => _AfterFrameListenerState();
}

class _AfterFrameListenerState extends State<_AfterFrameListener> {
  bool _scheduled = false;
  Object? _seen;

  @override
  void initState() {
    super.initState();
    _seen = widget.select();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_AfterFrameListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted || _scheduled) return;
    final next = widget.select();
    if (next == _seen) return;
    _seen = next;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _seen = widget.select();
    return widget.builder(context);
  }
}

/// The chat tile's preview: the unread count in the accent and the newest
/// message (sender and one line of text) the unread read already holds.
/// The ships tile's preview: what can fly now and what waits on its owner.
class CommunityHoloShipsPreview extends StatelessWidget {
  const CommunityHoloShipsPreview({
    super.key,
    required this.online,
    required this.inGame,
    required this.offline,
  });

  /// Separate counts in the same colors as the people's own status dots:
  /// online means online only, not also in game (user 2026-10-30).
  final int online, inGame, offline;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      key: const Key('community-tile-ships'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          workspaceText(
            context,
            'holo.shipsReady',
          ).replaceAll('{count}', '$online'),
          key: const Key('community-tile-ships-online'),
          style: small?.copyWith(
            color: online > 0 ? tokens.colors.info : tokens.colors.textDisabled,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          workspaceText(
            context,
            'holo.shipsInGame',
          ).replaceAll('{count}', '$inGame'),
          key: const Key('community-tile-ships-in-game'),
          style: small?.copyWith(
            color: inGame > 0
                ? tokens.colors.success
                : tokens.colors.textDisabled,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          workspaceText(
            context,
            'holo.shipsOffline',
          ).replaceAll('{count}', '$offline'),
          style: small?.copyWith(color: tokens.colors.textDisabled),
        ),
      ],
    );
  }
}
