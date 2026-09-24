import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/communities/community_catalog_ship_image.dart';
import '../../features/communities/community_ships_copy.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'menu_bridge_style.dart';
import 'menu_feature_view.dart';
import 'menu_friends_view.dart' show menuPresenceColor;
import 'menu_organization_view.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_avatar_actions.dart';
import 'menu_organization_directory.dart';
import 'menu_organization_header.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// WPF-style collaboration hierarchy, with stacked fields at narrow widths.
/// This renderer has no service or authority references.
class MenuOrganizationsPanel extends StatefulWidget {
  const MenuOrganizationsPanel({
    super.key,
    required this.view,
    required this.onAction,
    this.onProfile,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  @override
  State<MenuOrganizationsPanel> createState() => _MenuOrganizationsPanelState();
}

class _MenuOrganizationsPanelState extends State<MenuOrganizationsPanel> {
  final _query = TextEditingController();
  String _filter = '';
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
              : () => widget.onAction(action.key, ''),
          child: Text(action.label),
        )
      : OutlinedButton(
          onPressed: widget.view.busy
              ? null
              : () => widget.onAction(action.key, ''),
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
    const tabs = {
      'members': '成员',
      'ships': '舰船',
      'announcements': '公告',
      'chat': '聊天',
    };
    final search = view.buttons
        .where((a) => a.label == '搜索成员' || a.label == '搜索舰船')
        .firstOrNull;
    final footer = view.buttons.where(
      (a) => const {'首页', '下一页', '较早消息'}.contains(a.label),
    );
    final form = view.buttons.where((a) => a.input != null && a != search);
    final indices = [
      for (var i = 0; i < view.rows.length; i++)
        if (_filter.isEmpty || org.rows[i].presence == _filter) i,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 700 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuOrganizationHeader(view: view, onAction: widget.onAction),
            if (org.tab != 'directory') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in view.buttons.where(
                    (a) => tabs.values.contains(a.label),
                  ))
                    _action(action, selected: action.label == tabs[org.tab]),
                ],
              ),
              const Divider(color: BridgeInk.divider),
            ],
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
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  for (final status in const [
                    '',
                    'inGame',
                    'online',
                    'offline',
                    'unknown',
                  ])
                    OutlinedButton(
                      key: ValueKey('menu-org-filter-$status'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _filter == status
                            ? context.tokens.colors.info.withValues(alpha: .16)
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
            if (org.tab == 'members' && wide)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: _Columns(
                  children: [
                    BridgeCaption('成员'),
                    BridgeCaption('角色'),
                    BridgeCaption('服务器'),
                    BridgeCaption('当前飞船'),
                    BridgeCaption('位置'),
                    BridgeCaption('状态'),
                  ],
                ),
              ),
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
            for (final i in indices)
              _row(view.rows[i], org.rows[i], org.tab, wide),
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
        return SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        );
      },
    );
  }

  Widget _row(
    MenuFeatureRow row,
    MenuOrganizationRow data,
    String tab,
    bool wide,
  ) {
    Widget name() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row.title}${data.isSelf ? ' · 你' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (data.handle.isNotEmpty && data.handle != row.title)
          BridgeCaption(data.handle),
      ],
    );
    Widget identity() => tab != 'members'
        ? name()
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
    Widget role() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.role.isEmpty ? '组织成员' : data.role,
          style: TextStyle(color: roleColor),
        ),
        status(),
      ],
    );
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
          if (tab == 'members')
            if (wide)
              _Columns(
                children: [
                  identity(),
                  Text(
                    data.role.isEmpty ? '组织成员' : data.role,
                    style: TextStyle(color: roleColor),
                  ),
                  Text(data.server),
                  Text(data.ship),
                  Text(data.location),
                  status(),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity(),
                  const SizedBox(height: 6),
                  role(),
                  const SizedBox(height: 8),
                  Text('飞船 · ${data.ship}'),
                  Text('位置 · ${data.location}'),
                  BridgeCaption('服务器 · ${data.server}'),
                ],
              )
          else if (tab == 'ships') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      identity(),
                      if (row.detail.isNotEmpty) BridgeCaption(row.detail),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  communityShipDisplayText(context, data.spec),
                  style: TextStyle(color: shipSizeColor(context, data.spec)),
                ),
                Text(communityShipDisplayText(context, data.role)),
                Text(communityShipDisplayText(context, data.status)),
                Text(
                  data.price,
                  style: TextStyle(color: menuPresenceColor('online')),
                ),
                Text('所有者 · ${data.owner}'),
                status(),
              ],
            ),
          ] else ...[
            identity(),
            if (row.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(row.detail),
              ),
          ],
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

class _Columns extends StatelessWidget {
  const _Columns({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++)
        Expanded(
          flex: i == 0 ? 3 : 2,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: children[i],
          ),
        ),
    ],
  );
}
