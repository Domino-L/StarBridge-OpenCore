import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
import '../party_rooms/room_display.dart' show roomDate, roomServerRegion;
import 'community_workspace_controller.dart';
import 'community_member_banner.dart';
import 'community_member_runtime.dart';
import 'community_workspace_copy.dart';
import 'community_workspace_port.dart';
import 'community_workspace_image.dart';
import 'community_member_role_port.dart';
import 'community_member_role_dialog.dart';
import 'community_member_role_copy.dart';
import 'community_member_removal_port.dart';
import 'community_member_removal_dialog.dart';
import 'community_member_removal_copy.dart';
import 'community_ownership_transfer_port.dart';
import 'community_ownership_transfer_dialog.dart';
import 'community_ownership_transfer_copy.dart';
import '../../design_system/controls/semantic_action_style.dart';

/// Member presentation and governance actions share the live workspace guard.
final class CommunityWorkspaceMembers {
  CommunityWorkspaceMembers({
    required this.context,
    required this.currentModel,
    required this.isMounted,
    required this.port,
    required this.organizationKey,
    required this.search,
    required this.contextInvalidations,
    required this.onGovernanceChanged,
  });
  final BuildContext context;
  final CommunityWorkspaceController Function() currentModel;
  final bool Function() isMounted;
  final CommunityWorkspacePort port;
  final String? organizationKey;
  final TextEditingController search;
  final Stream<void> contextInvalidations;
  final Future<void> Function() onGovernanceChanged;
  CommunityWorkspaceController get model => currentModel();
  String t(String key) => workspaceText(context, key);
  Widget build() {
    final workspace = model.workspace!;
    final memberContent = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            '${t('members')} · ${workspace.matchedCount} / ${workspace.totalCount}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${t('updated')} · ${roomDate(context, workspace.fetchedAt)}',
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: t('search'),
                counterText: '',
              ),
              onSubmitted: (_) => model.load(search: search.text),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => model.load(search: search.text),
            child: Text(t('searchButton')),
          ),
        ],
      ),
      if (model.mediaFailed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            t('mediaFailed'),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        ),
      if (workspace.members.isEmpty)
        Padding(padding: const EdgeInsets.all(24), child: Text(t('empty'))),
      CommunityMemberHeader(showActions: _showMemberActions),
      for (final member in model.displayMembers)
        Padding(
          key: ValueKey('member-row-${member.memberRef}'),
          padding: const EdgeInsets.only(top: 8),
          child: _member(member),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: workspace.offset == 0
                ? null
                : () => model.load(
                    offset: (workspace.offset - 20).clamp(0, 1000000),
                  ),
            child: Text(t('previous')),
          ),
          OutlinedButton(
            onPressed: workspace.next == null
                ? null
                : () => model.load(offset: workspace.next!),
            child: Text(t('next')),
          ),
        ],
      ),
    ];
    return MouseRegion(
      onEnter: (_) => model.setMemberListHovered(true),
      onExit: (_) => model.setMemberListHovered(false),
      child: ListView(
        key: PageStorageKey((
          port,
          organizationKey ?? model.targetRef,
          'members',
        )),
        padding: const EdgeInsetsDirectional.only(end: 16),
        children: memberContent,
      ),
    );
  }

  bool get _showMemberActions {
    final workspace = model.workspace;
    if (workspace == null ||
        !workspace.members.any((member) => !member.isSelf && !member.isOwner)) {
      return false;
    }

    final owner = workspace.access['isOwner'] == true;
    return (owner &&
            port is CommunityOwnershipTransferPort &&
            (port as CommunityOwnershipTransferPort)
                .ownershipTransferAvailable) ||
        (owner &&
            port is CommunityMemberRolePort &&
            (port as CommunityMemberRolePort).memberRoleAvailable) ||
        ((owner || workspace.access['canRemoveMembers'] == true) &&
            port is CommunityMemberRemovalPort &&
            (port as CommunityMemberRemovalPort).memberRemovalAvailable);
  }

  Widget _box(Widget child, {Color? status}) => Container(
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Stack(
      children: [
        if (status != null)
          PositionedDirectional(
            start: 0,
            top: 8,
            bottom: 8,
            width: 3,
            child: ColoredBox(color: status),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Material(color: Colors.transparent, child: child),
        ),
      ],
    ),
  );

  Widget _member(CommunityWorkspaceMember member) {
    final transferPort = port is CommunityOwnershipTransferPort
        ? port as CommunityOwnershipTransferPort
        : null;
    final canTransfer =
        transferPort != null &&
        transferPort.ownershipTransferAvailable &&
        model.workspace?.access['isOwner'] == true &&
        !member.isSelf &&
        !member.isOwner;
    Future<void> transfer() async {
      final current = model;
      final workspace = model.workspace;
      if (!canTransfer ||
          workspace == null ||
          !workspace.members.contains(member)) {
        return;
      }
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityOwnershipTransferDialog(
          port: transferPort,
          targetRef: model.targetRef,
          memberRef: member.memberRef,
          organizationName: workspace.name,
          contextInvalidations: contextInvalidations,
        ),
      );
      if (changed == true &&
          isMounted() &&
          model == current &&
          model.workspace != null) {
        await model.load();
        if (isMounted() && model == current && model.workspace != null) {
          await onGovernanceChanged();
        }
      }
    }

    final transferButton = OutlinedButton(
      key: ValueKey('transfer-owner-${member.memberRef}'),
      onPressed: transfer,
      style: semanticActionStyle(
        context,
        ActionTone.danger,
        emphasis: ActionEmphasis.outlined,
      ),
      child: Text(ownershipTransferText(context, 'transfer')),
    );
    final removalPort = port is CommunityMemberRemovalPort
        ? port as CommunityMemberRemovalPort
        : null;
    final canOpenRemoval =
        removalPort != null &&
        removalPort.memberRemovalAvailable &&
        (model.workspace?.access['isOwner'] == true ||
            model.workspace?.access['canRemoveMembers'] == true) &&
        !member.isSelf &&
        !member.isOwner;
    Future<void> remove() async {
      final current = model;
      final workspace = model.workspace;
      if (!canOpenRemoval ||
          workspace == null ||
          !workspace.members.contains(member)) {
        return;
      }
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityMemberRemovalDialog(
          port: removalPort,
          targetRef: model.targetRef,
          memberRef: member.memberRef,
          organizationName: workspace.name,
          contextInvalidations: contextInvalidations,
        ),
      );
      if (changed == true &&
          isMounted() &&
          model == current &&
          model.workspace != null) {
        // Removal can empty the final page; reload from the first page with the current search.
        await model.load(offset: 0);
      }
    }

    final removalButton = OutlinedButton(
      key: ValueKey('remove-member-${member.memberRef}'),
      onPressed: remove,
      style: semanticActionStyle(
        context,
        ActionTone.danger,
        emphasis: ActionEmphasis.outlined,
      ),
      child: Text(memberRemovalText(context, 'remove')),
    );
    final assignmentPort = port is CommunityMemberRolePort
        ? port as CommunityMemberRolePort
        : null;
    final canAssign =
        assignmentPort != null &&
        assignmentPort.memberRoleAvailable &&
        model.workspace?.access['isOwner'] == true &&
        !member.isSelf &&
        !member.isOwner;
    Future<void> assign() async {
      final current = model;
      final workspace = model.workspace;
      if (!canAssign ||
          workspace == null ||
          !workspace.members.contains(member)) {
        return;
      }
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityMemberRoleDialog(
          port: assignmentPort,
          targetRef: model.targetRef,
          memberRef: member.memberRef,
          contextInvalidations: contextInvalidations,
        ),
      );
      if (changed == true &&
          isMounted() &&
          model == current &&
          model.workspace != null) {
        await model.load(offset: workspace.offset);
      }
    }

    final key = switch (member.liveStatus.toLowerCase()) {
      'paused' => 'paused',
      _ when !member.online => 'presence.offline',
      'ingame' => 'presence.inGame',
      'away' => 'presence.away',
      _ => 'presence.online',
    };
    final runtime = communityMemberRuntime(
      member,
      text: t,
      regionText: (region) => roomServerRegion(context, region),
    );
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatarMenu(
          name: member.displayName,
          avatarBytes: model.image(member.memberRef),
          isSelf: member.isSelf,
          target: UserTarget.community(
            model.targetRef,
            member.memberRef,
            query: member.gameName,
          ),
          actions: [
            if (canTransfer)
              AvatarMenuAction(
                ownershipTransferText(context, 'transfer'),
                () => unawaited(transfer()),
                color: context.tokens.colors.danger,
              ),
            if (canOpenRemoval)
              AvatarMenuAction(
                memberRemovalText(context, 'remove'),
                () => unawaited(remove()),
                color: context.tokens.colors.danger,
              ),
            if (canAssign)
              AvatarMenuAction(
                memberRoleText(context, 'assignRole'),
                () => unawaited(assign()),
              ),
          ],
          child: SizedBox(
            width: 48,
            height: 48,
            child: CommunityWorkspaceImage(
              bytes: model.image(member.memberRef),
              decoder: model.avatars.images.decode,
              maxWidth: 96,
              loading: model.imageLoading(member.memberRef),
              loadFailed: model.imageFailed(member.memberRef),
              icon: StandardIconSemantic.person,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${member.displayName}${member.isSelf ? ' · ${t('self')}' : ''}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (member.gameName.isNotEmpty &&
                  member.gameName != member.displayName)
                Text(member.gameName),
            ],
          ),
        ),
      ],
    );
    final roleColor = Color(
      int.parse('ff${member.roleColor.substring(1)}', radix: 16),
    );
    final role = Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.08),
          border: Border.all(color: roleColor.withValues(alpha: 0.6)),
        ),
        child: Text(
          member.roleTitle.isNotEmpty
              ? member.roleTitle
              : member.isOwner
              ? t('owner')
              : t('member'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: roleColor),
        ),
      ),
    );
    final status = Text(
      key == 'paused' ? t('paused') : AppStrings.of(context).text(key),
      style: TextStyle(color: presenceColor(context.tokens.colors, key)),
    );
    final actions = canTransfer || canOpenRemoval || canAssign
        ? MenuAnchor(
            menuChildren: [
              if (canTransfer) transferButton,
              if (canOpenRemoval) removalButton,
              if (canAssign)
                OutlinedButton(
                  key: ValueKey('assign-member-${member.memberRef}'),
                  onPressed: assign,
                  child: Text(memberRoleText(context, 'assignRole')),
                ),
            ],
            builder: (context, controller, _) => IconButton(
              key: ValueKey('member-actions-${member.memberRef}'),
              tooltip: t('actions'),
              icon: const StandardIcon(StandardIconSemantic.moreHoriz),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          )
        : _showMemberActions
        ? const SizedBox(width: 40)
        : null;
    return _box(
      CommunityMemberBanner(
        key: ValueKey('member-banner-${member.memberRef}'),
        identity: identity,
        role: role,
        server: runtime.server,
        ship: runtime.ship,
        location: runtime.location,
        status: status,
        actions: actions,
      ),
      status: presenceColor(context.tokens.colors, key),
    );
  }
}
