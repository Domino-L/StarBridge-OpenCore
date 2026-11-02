import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../features/common/organization_member_board.dart';
import 'menu_avatar_actions.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_feature_view.dart';
import 'menu_loading.dart';
import 'menu_organization_view.dart';

/// Adapts display-only menu data to the same member board as the main client.
/// Every callback retains the opaque authority supplied by the primary engine.
class MenuOrganizationMembersBoard extends StatefulWidget {
  const MenuOrganizationMembersBoard({
    required this.view,
    required this.searchController,
    required this.onAction,
    this.onProfile,
    super.key,
  });

  final MenuFeatureView view;
  final TextEditingController searchController;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;

  @override
  State<MenuOrganizationMembersBoard> createState() => _MenuMemberBoardState();
}

class _MenuMemberBoardState extends State<MenuOrganizationMembersBoard> {
  OrganizationMemberFilter _filter = OrganizationMemberFilter.all;

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = view.organization!;
    final blocked = view.busy || view.refreshing || org.bodyLoading;
    final processingOnly = view.busy && !view.refreshing && !org.bodyLoading;
    final search = view.buttons
        .where((b) => b.role == 'searchMembers')
        .firstOrNull;
    final previous = view.buttons
        .where((b) => b.role == 'previousPage')
        .firstOrNull;
    final next = view.buttons.where((b) => b.role == 'nextPage').firstOrNull;
    final first = view.buttons.where((b) => b.role == 'firstPage').firstOrNull;
    final allRows = <OrganizationMemberEntry>[
      for (var i = 0; i < view.rows.length; i++)
        _entry(
          context,
          view.rows[i],
          org.rows[i],
          i,
          allowProfile: !blocked && !org.bodyError,
        ),
    ];
    final canCount =
        allRows.isNotEmpty ||
        view.state == 'ready' && !org.bodyLoading && !org.bodyError;
    bool online(OrganizationMemberEntry row) => const {
      OrganizationMemberPresence.online,
      OrganizationMemberPresence.away,
      OrganizationMemberPresence.inGame,
    }.contains(row.presence);
    final visible = allRows
        .where(
          (row) => switch (_filter) {
            OrganizationMemberFilter.all => true,
            OrganizationMemberFilter.online => online(row),
            OrganizationMemberFilter.inGame =>
              row.presence == OrganizationMemberPresence.inGame,
          },
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrganizationMemberBoard(
          key: ValueKey('menu-members/${view.scope}/${org.identity}'),
          namespace: 'menu-org',
          rows: visible,
          searchController: widget.searchController,
          searchHint: search?.input,
          showSearch: search != null,
          controlsEnabled: !blocked,
          onSearch: (value) {
            if (!blocked && search != null) widget.onAction(search.key, value);
          },
          roleLabel: memberBoardText(context, 'role'),
          columns: const OrganizationMemberColumns.all(),
          totalCount: canCount ? org.matched : null,
          onlineCount: canCount ? allRows.where(online).length : null,
          inGameCount: canCount
              ? allRows
                    .where(
                      (r) => r.presence == OrganizationMemberPresence.inGame,
                    )
                    .length
              : null,
          countsArePageScoped: true,
          hasMultiplePages: org.offset > 0 || org.matched > allRows.length,
          filters: OrganizationMemberFilter.values,
          filter: _filter,
          onFilter: blocked ? null : (value) => setState(() => _filter = value),
          pagination: OrganizationMemberPagination(
            enabled: !blocked,
            showPrevious: previous != null,
            showNext: next != null,
            onPrevious: previous == null
                ? null
                : () {
                    if (!blocked) widget.onAction(previous.key, '');
                  },
            onNext: next == null
                ? null
                : () {
                    if (!blocked) widget.onAction(next.key, '');
                  },
            onFirst: first == null
                ? null
                : () {
                    if (!blocked) widget.onAction(first.key, '');
                  },
          ),
          loading: org.bodyLoading || view.state == 'loading',
          loadingIndicator: ExcludeSemantics(
            child: MenuLoading(feedback: view.readFeedback),
          ),
          refreshing:
              view.refreshing ||
              view.busy ||
              org.bodyLoading && allRows.isNotEmpty,
          refreshingIndicator: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: MenuLoading(
                  feedback: processingOnly ? null : view.readFeedback,
                  label: processingOnly
                      ? menuText(context, 'menu.overlay.window.working')
                      : menuText(context, 'menu.overlay.window.reading'),
                ),
              ),
              Text(
                processingOnly
                    ? menuText(context, 'menu.display.busy')
                    : memberBoardText(context, 'refreshing'),
              ),
            ],
          ),
          error: org.bodyError
              ? memberBoardText(context, 'refreshFailed')
              : null,
          onRetry: blocked ? null : () => widget.onAction('refresh', ''),
          note: view.notice,
        ),
      ],
    );
  }

  OrganizationMemberEntry _entry(
    BuildContext context,
    MenuFeatureRow row,
    MenuOrganizationRow data,
    int index, {
    required bool allowProfile,
  }) {
    final identity = OrganizationMemberIdentity(
      name: row.title,
      gameId: data.handle,
      isSelf: data.isSelf,
      avatar: MenuInlineAvatar(name: row.title, source: data.avatar),
    );
    final profileKey = data.profileKey;
    final canProfile =
        allowProfile &&
        widget.onProfile != null &&
        profileKey != null &&
        RegExp(r'^om[1-9][0-9]{0,13}$').hasMatch(profileKey);
    return OrganizationMemberEntry(
      reference: '${widget.view.scope}/$index',
      identity: canProfile
          ? MenuAvatarActions(
              identity: (widget.view.scope, profileKey),
              name: row.title,
              onProfile: () => widget.onProfile!(profileKey),
              child: identity,
            )
          : identity,
      role: data.role.isEmpty ? memberBoardText(context, 'role') : data.role,
      roleColor:
          data.roleColor.toUpperCase() != '#9DAAB3' &&
              RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(data.roleColor)
          ? Color(int.parse('ff${data.roleColor.substring(1)}', radix: 16))
          : null,
      presence: switch (data.presence) {
        'inGame' => OrganizationMemberPresence.inGame,
        'online' => OrganizationMemberPresence.online,
        'away' => OrganizationMemberPresence.away,
        'offline' => OrganizationMemberPresence.offline,
        _ => OrganizationMemberPresence.unknown,
      },
      runtime: data.presence != 'inGame'
          ? const MemberRuntimeCells.empty()
          : MemberRuntimeCells(
              server: _cell(
                context,
                data.server,
                data.serverKind,
                data.serverTextKey,
              ),
              ship: _cell(context, data.ship, data.shipKind, data.shipTextKey),
              location: _cell(
                context,
                data.location,
                data.locationKind,
                data.locationTextKey,
              ),
            ),
    );
  }

  MemberRuntimeCell _cell(
    BuildContext context,
    String text,
    String kind,
    String textKey,
  ) => kind == 'value'
      ? MemberRuntimeCell.value(text)
      : MemberRuntimeCell.placeholder(
          textKey.isEmpty ? text : memberBoardText(context, textKey),
        );
}
