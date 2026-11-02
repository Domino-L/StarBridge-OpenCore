import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../common/organization_member_board.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';

import '../common/user_avatar_menu.dart';
import '../party_rooms/room_display.dart' show roomDate, roomServerRegion;
import 'community_workspace_controller.dart';
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
    required this.openDialog,
    this.refreshingIndicator,
  });
  final BuildContext context;
  final CommunityWorkspaceController Function() currentModel;
  final bool Function() isMounted;
  final CommunityWorkspacePort port;
  final String? organizationKey;
  final TextEditingController search;
  final Stream<void> contextInvalidations;
  final Future<void> Function() onGovernanceChanged;
  final Future<bool?> Function(WidgetBuilder builder) openDialog;
  final Widget? refreshingIndicator;
  CommunityWorkspaceController get model => currentModel();
  String t(String key) => workspaceText(context, key);
  Widget build() {
    final workspace = model.workspace!;
    final members = model.displayMembers;
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
        children: [
          OrganizationMemberBoard(
            key: ValueKey((
              port,
              model.targetRef,
              workspace.offset,
              workspace.query,
            )),
            namespace: 'community-member',
            roleLabel: memberBoardText(context, 'role'),
            columns: const OrganizationMemberColumns.all(),
            rows: members.map(_member).toList(),
            searchController: search,
            onSearch: (value) => unawaited(model.load(search: value)),
            totalCount: workspace.matchedCount,
            summaryText:
                '${t('members')} · ${workspace.matchedCount} / ${workspace.totalCount}',
            updatedText:
                '${t('updated')} · ${roomDate(context, workspace.fetchedAt)}',
            searchLabel: t('search'),
            searchButtonLabel: t('searchButton'),
            onlineCount: workspace.members
                .where((member) => member.publicOnline)
                .length,
            inGameCount: workspace.members
                .where((member) => member.publicInGame)
                .length,
            countsArePageScoped: true,
            hasMultiplePages:
                workspace.offset > 0 ||
                workspace.next != null ||
                workspace.matchedCount > workspace.members.length,
            fetchedAt: workspace.fetchedAt,
            refreshing: model.busy,
            refreshingIndicator: refreshingIndicator == null
                ? null
                : Row(
                    children: [
                      Expanded(
                        child: Text(memberBoardText(context, 'refreshing')),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(width: 80, child: refreshingIndicator),
                    ],
                  ),
            error: model.error == null
                ? null
                : memberBoardText(context, 'refreshFailed'),
            onRetry: () => unawaited(model.load()),
            note: model.mediaFailed ? t('mediaFailed') : null,
            pagination: OrganizationMemberPagination(
              showNavigationWhenDisabled: true,
              onPrevious: workspace.offset == 0
                  ? null
                  : () => unawaited(
                      model.load(
                        offset: (workspace.offset - 20).clamp(0, 1000000),
                      ),
                    ),
              onNext: workspace.next == null
                  ? null
                  : () => unawaited(model.load(offset: workspace.next!)),
            ),
          ),
        ],
      ),
    );
  }

  OrganizationMemberEntry _member(CommunityWorkspaceMember member) {
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
      final changed = await openDialog(
        (_) => CommunityOwnershipTransferDialog(
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
      final changed = await openDialog(
        (_) => CommunityMemberRemovalDialog(
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
      final changed = await openDialog(
        (_) => CommunityMemberRoleDialog(
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

    final runtime = communityMemberRuntimeCells(
      member,
      text: (key) => memberBoardText(context, key),
      regionText: (region) => roomServerRegion(context, region),
      locale: AppStrings.of(context).locale,
    );
    final identity = OrganizationMemberIdentity(
      name: member.displayName,
      gameId: member.gameName,
      isSelf: member.isSelf,
      avatarBytes: model.image(member.memberRef),
      target: model.error != null
          ? null
          : UserTarget.community(
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
      avatar: CommunityWorkspaceImage(
        bytes: model.image(member.memberRef),
        decoder: model.avatars.images.decode,
        peek: model.avatars.images.peek,
        maxWidth: 96,
        loading: model.imageLoading(member.memberRef),
        loadFailed: model.imageFailed(member.memberRef),
        icon: StandardIconSemantic.person,
      ),
    );
    // This is the source's existing neutral default, not a custom role color.
    final roleColor = member.roleColor.toUpperCase() == '#9DAAB3'
        ? null
        : Color(int.parse('ff${member.roleColor.substring(1)}', radix: 16));
    final actions = canTransfer || canOpenRemoval || canAssign
        ? StarBridgeMenuAnchor(
            semanticLabel: t('actions'),
            entries: [
              if (canTransfer)
                StarBridgeMenuEntry(
                  id: 'transfer-owner-${member.memberRef}',
                  label: ownershipTransferText(context, 'transfer'),
                  child: Text(
                    ownershipTransferText(context, 'transfer'),
                    style: TextStyle(color: context.tokens.colors.danger),
                  ),
                  onActivate: (source) => unawaited(
                    runStarBridgeActivation<void>(source, transfer),
                  ),
                ),
              if (canOpenRemoval)
                StarBridgeMenuEntry(
                  id: 'remove-member-${member.memberRef}',
                  label: memberRemovalText(context, 'remove'),
                  child: Text(
                    memberRemovalText(context, 'remove'),
                    style: TextStyle(color: context.tokens.colors.danger),
                  ),
                  onActivate: (source) =>
                      unawaited(runStarBridgeActivation<void>(source, remove)),
                ),
              if (canAssign)
                StarBridgeMenuEntry(
                  id: 'assign-member-${member.memberRef}',
                  label: memberRoleText(context, 'assignRole'),
                  onActivate: (source) =>
                      unawaited(runStarBridgeActivation<void>(source, assign)),
                  child: Text(memberRoleText(context, 'assignRole')),
                ),
            ],
            builder: (context, controller, focus, toggle) =>
                StarBridgeIconAction(
                  controlKey: ValueKey('member-actions-${member.memberRef}'),
                  focusNode: focus,
                  label: t('actions'),
                  icon: const StandardIcon(StandardIconSemantic.moreHoriz),
                  onActivate: toggle,
                ),
          )
        : null;
    return OrganizationMemberEntry(
      reference: member.memberRef,
      identity: identity,
      roleColor: roleColor,
      role: member.roleTitle.isNotEmpty
          ? member.roleTitle
          : member.isOwner
          ? t('owner')
          : t('member'),
      presence: OrganizationMemberPresence.values.byName(member.publicPresence),
      runtime: runtime,
      actions: actions,
    );
  }
}
