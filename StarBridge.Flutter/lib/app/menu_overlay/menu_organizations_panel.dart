import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/icons/standard_icon.dart';

import '../../features/communities/community_catalog_ship_image.dart';
import '../../features/communities/community_member_banner.dart';
import '../../features/communities/community_ship_banner.dart';
import '../../features/communities/community_fleet_statistics_dialog.dart';
import '../../features/communities/community_ship_row_surface.dart';
import '../../features/communities/community_announcement_card.dart';
import '../../features/communities/community_announcements_copy.dart';
import '../../features/direct_messages/communication_time_formatter.dart';
import '../localization/app_strings.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../features/communities/community_ships_copy.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'menu_bridge_style.dart';
import 'menu_feature_view.dart';
import 'menu_friends_view.dart' show menuPresenceColor;
import 'menu_organization_view.dart';
import 'menu_announcement_details_control.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_avatar_actions.dart';
import 'menu_organization_directory.dart';
import 'menu_organization_header.dart';
import 'menu_organization_sidebar.dart';
import 'menu_organization_navigation.dart';
import 'menu_channel_panel.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// WPF-style collaboration hierarchy, with stacked fields at narrow widths.
/// This renderer has no service or authority references.
class MenuOrganizationsPanel extends StatefulWidget {
  const MenuOrganizationsPanel({
    super.key,
    required this.view,
    required this.onAction,
    this.onProfile,
    this.active = false,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final bool active;
  @override
  State<MenuOrganizationsPanel> createState() => _MenuOrganizationsPanelState();
}

class _MenuOrganizationsPanelState extends State<MenuOrganizationsPanel> {
  final _query = TextEditingController();
  String _filter = '';
  bool _showOrganizations = false;
  bool _statisticsDismissed = false;
  @override
  void initState() {
    super.initState();
    _query.text = widget.view.organization?.query ?? '';
  }

  @override
  void didUpdateWidget(MenuOrganizationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.scope != widget.view.scope ||
        (oldWidget.view.organization != null &&
            widget.view.organization != null &&
            oldWidget.view.organization?.tab !=
                widget.view.organization?.tab)) {
      _filter = '';
      _statisticsDismissed = false;
      _query.text = widget.view.organization?.query ?? '';
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _action(MenuFeatureButton action, {bool selected = false}) => selected
      ? FilledButton.tonal(
          onPressed: widget.view.busy
              ? null
              : () {
                  if (action.label == '舰队统计') {
                    setState(() => _statisticsDismissed = false);
                  }
                  widget.onAction(action.key, '');
                },
          child: Text(action.label),
        )
      : OutlinedButton(
          onPressed: widget.view.busy
              ? null
              : () {
                  if (action.label == '舰队统计') {
                    setState(() => _statisticsDismissed = false);
                  }
                  widget.onAction(action.key, '');
                },
          child: Text(action.label),
        );

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = view.organization;
    if (org == null) {
      return MenuFeaturePanel(view: view, onAction: widget.onAction);
    }
    if (org.tab == 'directory') {
      return MenuOrganizationDirectory(view: view, onAction: widget.onAction);
    }
    final search = view.buttons
        .where((a) => a.label == '搜索成员' || a.label == '搜索舰船')
        .firstOrNull;
    final footer = view.buttons.where(
      (a) => const {'首页', '下一页', '较早消息'}.contains(a.label),
    );
    final form = view.buttons.where((a) => a.input != null && a != search);
    final statistics = view.buttons.where((a) => a.label == '舰队统计').firstOrNull;
    final indices = [
      for (var i = 0; i < view.rows.length; i++)
        if (_filter.isEmpty || org.rows[i].presence == _filter) i,
    ];
    final layout = LayoutBuilder(
      builder: (context, constraints) {
        final normalText = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final showSidebar =
            org.navigation.isNotEmpty &&
            constraints.maxWidth >= 860 &&
            normalText;
        final sidebarWidth = constraints.maxWidth >= 1100 ? 260.0 : 220.0;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (view.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  view.notice,
                  style: const TextStyle(color: BridgeInk.amber),
                ),
              ),
            if (view.busy) const BridgeCaption('正在处理…'),
            if (search != null) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      enabled: !view.busy,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(search.limit),
                      ],
                      decoration: InputDecoration(
                        hintText: search.input,
                        isDense: true,
                      ),
                      onSubmitted: view.busy
                          ? null
                          : (value) => widget.onAction(search.key, value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: view.busy
                        ? null
                        : () => widget.onAction(search.key, _query.text),
                    child: const Text('搜索'),
                  ),
                  if (org.tab == 'ships' && statistics != null) ...[
                    const SizedBox(width: 8),
                    _action(statistics),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (org.tab == 'members')
                Wrap(
                  spacing: 4,
                  children: [
                    for (final status in const [
                      '',
                      'inGame',
                      'online',
                      'away',
                      'offline',
                      'unknown',
                    ])
                      OutlinedButton(
                        key: ValueKey('menu-org-filter-$status'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _filter == status
                              ? context.tokens.colors.info.withValues(
                                  alpha: .16,
                                )
                              : null,
                        ),
                        onPressed: () => setState(() => _filter = status),
                        child: Text(
                          status.isEmpty
                              ? '本页全部'
                              : organizationPresenceText(status),
                          style: TextStyle(
                            color: status.isEmpty
                                ? BridgeInk.text
                                : menuPresenceColor(status),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
            ],
            if (org.tab == 'members')
              const CommunityMemberHeader(showActions: false),
            if (org.tab == 'ships')
              const CommunityShipColumnHeader(showImportedAt: false),
            if (indices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _filter.isNotEmpty
                      ? '当前页没有符合条件的成员或舰船。'
                      : org.query.isNotEmpty
                      ? '没有匹配结果，请调整搜索条件。'
                      : switch (org.tab) {
                          'directory' => '尚未加入组织，可在客户端的社区组织页面查找。',
                          'ships' => '暂无向组织共享的舰船。',
                          'announcements' => '暂无组织公告。',
                          'chat' => '暂无消息。',
                          _ => '暂无可查看的成员。',
                        },
                ),
              ),
            for (final i in indices) _row(view.rows[i], org.rows[i], org.tab),
            if (org.tab == 'members' || org.tab == 'ships')
              BridgeCaption(
                org.matched == 0
                    ? '0 条结果'
                    : '${org.offset + 1}–${org.offset + view.rows.length} / ${org.matched}',
              ),
            Wrap(children: [for (final action in footer) _action(action)]),
            for (final action in form)
              MenuFeatureAction(
                key: ValueKey('${view.scope}/${action.label}'),
                action: action,
                enabled: !view.busy,
                onAction: widget.onAction,
              ),
          ],
        );
        final Widget content = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: MenuOrganizationHeader(
                view: view,
                onAction: widget.onAction,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MenuOrganizationNavigation(
                view: view,
                onAction: widget.onAction,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: BridgeInk.divider),
            ),
            Expanded(
              child: org.bodyLoading
                  ? const Center(child: BridgeCaption('正在读取…'))
                  : org.bodyError
                  ? Center(
                      child: TextButton(
                        onPressed: () => widget.onAction('refresh', ''),
                        child: const Text('暂时无法读取，点击重试'),
                      ),
                    )
                  : org.tab == 'chat' && view.chat != null
                  ? MenuChannelPanel(
                      view: view,
                      embeddedOrganization: true,
                      onAction: widget.onAction,
                      active: widget.active,
                      onProfile: widget.onProfile,
                    )
                  : SingleChildScrollView(
                      key: ValueKey('menu-org-body-${org.tab}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: body,
                      ),
                    ),
            ),
          ],
        );
        if (org.navigation.isEmpty) return content;
        final sidebar = MenuOrganizationSidebar(
          items: org.navigation,
          busy:
              view.busy ||
              view.refreshing ||
              org.sections.values.every((key) => key == null),
          onSelect: (key) {
            setState(() => _showOrganizations = false);
            widget.onAction(key, '');
          },
        );
        if (showSidebar) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: sidebar),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showOrganizations = !_showOrganizations),
                icon: StandardIcon(
                  _showOrganizations
                      ? StandardIconSemantic.arrowForward
                      : StandardIconSemantic.arrowBack,
                ),
                label: Text(_showOrganizations ? '返回当前组织' : '组织列表'),
              ),
            ),
            Expanded(child: _showOrganizations ? sidebar : content),
          ],
        );
      },
    );
    if (_statisticsDismissed ||
        org.fleetStatistics == null ||
        statistics == null ||
        org.tab != 'ships') {
      return layout;
    }
    void closeStatistics() {
      setState(() => _statisticsDismissed = true);
      final close = view.buttons.where((b) => b.label == '关闭统计').firstOrNull;
      if (close != null) widget.onAction(close.key, '');
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): closeStatistics,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            layout,
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Colors.black54),
            ),
            Positioned.fill(
              child: CommunityFleetStatisticsDialog(
                statistics: org.fleetStatistics!,
                onClose: closeStatistics,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(MenuFeatureRow row, MenuOrganizationRow data, String tab) {
    Widget name() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row.title}${data.isSelf ? ' · 你' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (data.handle.isNotEmpty && data.handle != row.title)
          BridgeCaption(
            data.handle.startsWith('@') ? data.handle : '@${data.handle}',
            color: MenuBridgeColors.of(context).blue,
          ),
      ],
    );
    Widget identity() => tab != 'members'
        ? name()
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MenuAvatarActions(
                name: row.title,
                onProfile:
                    data.profileKey == null ||
                        widget.onProfile == null ||
                        widget.view.busy
                    ? null
                    : () => widget.onProfile!(data.profileKey!),
                child: MenuInlineAvatar(name: row.title, source: data.avatar),
              ),
              const SizedBox(width: 10),
              Expanded(child: name()),
            ],
          );
    Widget status() => Text(
      organizationPresenceText(data.presence),
      style: TextStyle(color: menuPresenceColor(data.presence)),
    );
    final roleColor = data.roleColor.isEmpty
        ? BridgeInk.muted
        : Color(int.parse('ff${data.roleColor.substring(1)}', radix: 16));
    if (tab == 'announcements') {
      final date = DateTime.tryParse(data.announcementTime);
      final colors = context.tokens.colors;
      return CommunityAnnouncementCard(
        title: row.title,
        content: row.detail.isEmpty
            ? communityAnnouncementText(context, 'emptyBody')
            : row.detail,
        maxLines: data.currentAnnouncement ? 4 : 2,
        metadata: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (const {
              'published',
              'archived',
              'withdrawn',
            }.contains(data.announcementState))
              Text(
                communityAnnouncementText(context, data.announcementState),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: data.announcementState == 'published'
                      ? colors.success
                      : data.announcementState == 'withdrawn'
                      ? colors.warning
                      : colors.textSecondary,
                ),
              ),
            if (date != null)
              Text(
                communicationTime(date, AppStrings.of(context).locale),
                style: TextStyle(color: colors.textSecondary),
              ),
          ],
        ),
        actions: data.announcement == null
            ? const SizedBox.shrink()
            : MenuAnnouncementDetailsControl(
                key: ValueKey('${widget.view.scope}/${data.announcement!.key}'),
                view: data.announcement!,
                active: widget.active,
                action: row.buttons.firstOrNull?.key,
                enabled: !widget.view.busy,
                dispatch: widget.onAction,
              ),
      );
    }
    if (tab == 'ships') {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CommunityShipRowSurface(
          child: CommunityShipBanner(
            showImportedAt: false,
            identity: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 48,
                  child: CommunityCatalogShipImage(
                    asset: data.image,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name(),
                      if (row.detail.isNotEmpty) BridgeCaption(row.detail),
                    ],
                  ),
                ),
              ],
            ),
            spec: ShipClassificationTag(
              label: communityShipDisplayText(context, data.spec),
              color: shipSizeColor(context, data.spec),
            ),
            role: ShipClassificationTag(
              label: communityShipDisplayText(context, data.role),
              color: shipCategoryColor(context, data.role),
            ),
            vehicleIcon: CatalogVehicleIcon.supportsKey(data.iconKey)
                ? CatalogVehicleIcon.byKey(iconKey: data.iconKey)
                : const SizedBox.square(dimension: 28),
            status: Text(communityShipDisplayText(context, data.status)),
            price: Text(
              data.price,
              style: TextStyle(color: context.tokens.colors.info),
            ),
            owner: Row(
              children: [
                MenuInlineAvatar(source: data.avatar, name: data.owner),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: data.owner,
                        child: Text(
                          data.owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      status(),
                    ],
                  ),
                ),
              ],
            ),
            importedAt: const SizedBox.shrink(),
            action: const SizedBox.shrink(),
          ),
        ),
      );
    }
    if (tab == 'members') {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: CommunityMemberCard(
          status: menuPresenceColor(data.presence),
          child: CommunityMemberBanner(
            identity: identity(),
            role: CommunityRoleBadge(
              label: data.role.isEmpty ? '组织成员' : data.role,
              color: roleColor,
            ),
            server: data.server,
            ship: data.ship,
            location: data.location,
            status: status(),
            actions: null,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.panel.fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data.isSelf
              ? context.tokens.colors.info
              : context.tokens.surfaces.panel.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity(),
          if (row.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(row.detail),
            ),
          for (final action in row.buttons)
            MenuFeatureAction(
              key: ValueKey(
                '${widget.view.scope}/${row.title}/${action.label}',
              ),
              action: action,
              enabled: !widget.view.busy,
              onAction: widget.onAction,
            ),
        ],
      ),
    );
  }
}
