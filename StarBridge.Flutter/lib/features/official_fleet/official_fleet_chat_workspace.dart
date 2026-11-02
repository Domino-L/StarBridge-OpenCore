import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_online.dart';
import '../common/organization_member_row.dart';
import 'official_fleet_member_views.dart';
import 'official_fleet_members_models.dart';

/// The main fleet's chat section (holo restyle, user decisions 2026-10-22
/// and 2026-10-29 option B): the "online now" column on the left, shared with
/// community holo chat, and the current announcement pinned above the
/// conversation.
class OfficialFleetChatWorkspace extends StatelessWidget {
  const OfficialFleetChatWorkspace({
    required this.chat,
    required this.online,
    this.pinned,
    this.resetKey,
    super.key,
  });

  final Widget chat;
  final OrganizationHoloOnlineBuilder online;
  final Object? resetKey;

  /// The compact announcement entry; it keeps opening the announcements.
  final Widget? pinned;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.colors.accent;
    return OrganizationHoloChatDock(
      key: const Key('official-fleet-chat-dock'),
      resetKey: resetKey,
      closeKey: const Key('official-fleet-online-close'),
      online: online,
      chat: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pinned != null) ...[
            Container(
              key: const Key('official-fleet-chat-pinned'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: .12),
                    accent.withValues(alpha: 0),
                  ],
                ),
                border: Border(left: BorderSide(color: accent, width: 2)),
              ),
              child: Row(
                children: [
                  Text(
                    AppStrings.of(context).text('officialFleet.chat.pinned'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: pinned!),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(child: chat),
        ],
      ),
    );
  }
}

/// "Online now": its own read of the roster filtered to online members, so
/// it never depends on (or moves) the member list's page, search or filter.
/// Grouped into in game and online, refreshed on roster and presence changes.
class OfficialFleetOnlinePane extends StatelessWidget {
  const OfficialFleetOnlinePane({
    required this.members,
    this.collapsed = false,
    this.onToggle,
    this.onAllMembers,
    super.key,
  });

  /// The page's own member read. The runtime directory has no online filter,
  /// and a second read here would cost as much again for the same rows.
  final ValueListenable<OfficialFleetMemberDirectoryProjection> members;

  /// The left rail instead of the column (option B, 2026-10-29).
  final bool collapsed;
  final VoidCallback? onToggle, onAllMembers;

  /// The pane as the chat dock builds it, collapsed or expanded.
  static OrganizationHoloOnlineBuilder dock(
    ValueListenable<OfficialFleetMemberDirectoryProjection> members,
    VoidCallback onAllMembers,
  ) =>
      (_, {required collapsed, onToggle}) => OfficialFleetOnlinePane(
        members: members,
        collapsed: collapsed,
        onToggle: onToggle,
        onAllMembers: onAllMembers,
      );

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<OfficialFleetMemberDirectoryProjection>(
        valueListenable: members,
        builder: _pane,
      );

  Widget _pane(
    BuildContext context,
    OfficialFleetMemberDirectoryProjection projection,
    Widget? _,
  ) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('officialFleet.online.$key');
    final query = projection.query;
    final waiting =
        projection.availability ==
            OfficialFleetMemberDirectoryAvailability.idle ||
        projection.availability ==
            OfficialFleetMemberDirectoryAvailability.loading;
    // A search or another page in the member list is not who is online.
    final usable =
        projection.availability ==
            OfficialFleetMemberDirectoryAvailability.available &&
        projection.runtimeCapabilities.presence &&
        query?.search == '' &&
        query?.filter == OfficialFleetMemberFilter.all &&
        query?.pageNumber == 1;
    final groups = <OrganizationHoloOnlineGroup>[];
    var onlineCount = 0;
    if (usable) {
      final inGame = <OrganizationHoloOnlineMember>[];
      final online = <OrganizationHoloOnlineMember>[];
      for (final member in projection.members) {
        final playing =
            member.publicPresence == OfficialFleetMemberPresence.inGame;
        if (!playing &&
            member.publicPresence != OfficialFleetMemberPresence.online) {
          continue;
        }
        (playing ? inGame : online).add(
          _entry(
            context,
            member,
            detail: playing
                ? member.publicLocation.value ?? t('locationHidden')
                : t('notInGame'),
            dot: playing ? tokens.colors.success : tokens.colors.stateAccent,
          ),
        );
      }
      onlineCount = inGame.length + online.length;
      if (inGame.isNotEmpty) {
        groups.add(
          OrganizationHoloOnlineGroup(
            t('inGame').replaceAll('{count}', '${inGame.length}'),
            inGame,
          ),
        );
      }
      if (online.isNotEmpty) {
        groups.add(
          OrganizationHoloOnlineGroup(
            t('online').replaceAll('{count}', '${online.length}'),
            online,
          ),
        );
      }
    }
    // Beyond one page there may be more online than these rows show, so it
    // cannot say how many, or that nobody is.
    final complete = projection.hasCompletePage;
    final status = waiting
        ? t('loading')
        : !usable || groups.isEmpty && !complete
        ? t('unavailable')
        : groups.isEmpty
        ? t('none')
        : null;
    final count = !usable
        ? null
        : complete
        ? '$onlineCount'
        : '$onlineCount+';
    const keys = OrganizationHoloOnlineKeys(
      pane: Key('official-fleet-online-pane'),
      status: Key('official-fleet-online-status'),
      toggle: Key('official-fleet-online-toggle'),
      allMembers: Key('official-fleet-online-all'),
    );
    if (collapsed) {
      return OrganizationHoloOnlineRail(
        keys: keys,
        label: t('title'),
        count: count,
        members: [for (final group in groups) ...group.members],
        onExpand: onToggle ?? () {},
      );
    }
    return OrganizationHoloOnlineColumn(
      keys: keys,
      title: t('title'),
      count: count,
      status: status,
      groups: groups,
      toggleLabel: t('hide'),
      onToggle: onToggle,
      allMembersLabel: strings.text('officialFleet.members.enterAll'),
      onAllMembers: onAllMembers,
    );
  }

  OrganizationHoloOnlineMember _entry(
    BuildContext context,
    OfficialFleetMember member, {
    required String detail,
    required Color dot,
  }) {
    final identity = officialFleetMemberEntry(
      context,
      member,
      sourceRef: members.value.query?.sourceRef,
    ).identity;
    return OrganizationHoloOnlineMember(
      key: ValueKey('official-fleet-online-${member.memberRef}'),
      name: member.callsign,
      detail: detail,
      dot: dot,
      // Avatars keep their own shape (user decision 2026-10-22).
      avatar: identity is OrganizationMemberIdentity
          ? identity.avatar
          : const SizedBox.shrink(),
    );
  }
}
