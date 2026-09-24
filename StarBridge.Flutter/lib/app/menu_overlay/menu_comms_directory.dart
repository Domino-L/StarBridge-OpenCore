import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/direct_messages/communication_time_formatter.dart';
import 'menu_comms_view.dart';
import 'menu_inline_avatar.dart';
import 'menu_avatar_actions.dart';
import 'menu_feature_view.dart';
import 'menu_loading.dart';

class MenuCommsDirectory extends StatelessWidget {
  const MenuCommsDirectory({
    super.key,
    required this.view,
    required this.query,
    required this.group,
    required this.onQuery,
    required this.onGroup,
    required this.onAction,
    this.onProfile,
    this.organization,
    this.organizationSelected = false,
    this.onOrganizationAction,
  });
  final MenuCommsView view;
  final String query, group;
  final ValueChanged<String> onQuery, onGroup;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final MenuFeatureView? organization;
  final bool organizationSelected;
  final void Function(String, String)? onOrganizationAction;
  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final channels = (organization?.channels ?? const <MenuFeatureRow>[])
        .where(
          (row) => group == 'all' && row.title.toLowerCase().contains(needle),
        )
        .toList();
    final rows = view.rows
        .where(
          (r) =>
              (group == 'all' ||
                  (group == 'unread' ? r.unread > 0 : r.request)) &&
              (needle.isEmpty ||
                  '${r.name} ${view.previews[r.key] ?? ''}'
                      .toLowerCase()
                      .contains(needle)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('会话', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (view.name == null)
              TextButton(
                onPressed: view.busy ? null : () => onAction('retry', ''),
                child: const Text('刷新'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (view.name == null && view.refreshing) const MenuLoading(),
        TextFormField(
          key: const ValueKey('menu-comms-search'),
          initialValue: query,
          decoration: const InputDecoration(
            hintText: '搜索会话或消息摘要',
            isDense: true,
          ),
          onChanged: onQuery,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in const {
              'all': '全部',
              'unread': '未读',
              'requests': '消息请求',
            }.entries)
              OutlinedButton(
                key: ValueKey('menu-comms-group-${entry.key}'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: group == entry.key
                      ? context.tokens.colors.info.withValues(alpha: .16)
                      : null,
                ),
                onPressed: () => onGroup(entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty && channels.isEmpty
              ? const Center(
                  child: Text(
                    '暂无匹配会话\n可从好友面板发起聊天。',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('menu-conversation-list'),
                  itemCount: rows.length + channels.length,
                  itemBuilder: (context, index) {
                    if (index < channels.length) {
                      final row = channels[index];
                      return ListTile(
                        key: ValueKey(
                          'menu-organization-conversation-${row.title}',
                        ),
                        selected:
                            organizationSelected && row.detail == '当前组织频道',
                        selectedTileColor: context.tokens.surfaces.raised.fill,
                        leading: MenuInlineAvatar(
                          name: row.title,
                          source: row.avatar,
                        ),
                        title: Text(
                          row.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('组织频道'),
                        onTap: organization?.busy == true || row.buttons.isEmpty
                            ? null
                            : () => onOrganizationAction?.call(
                                row.buttons.first.key,
                                '',
                              ),
                      );
                    }
                    final row = rows[index - channels.length];
                    return Material(
                      color: !organizationSelected && row.key == view.profileKey
                          ? context.tokens.surfaces.raised.fill
                          : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('menu-conversation-${row.key}'),
                        onTap: () => onAction('select', row.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MenuAvatarActions(
                                name: row.name,
                                onProfile: onProfile == null
                                    ? null
                                    : () => onProfile!(row.key),
                                child: MenuInlineAvatar(
                                  name: row.name,
                                  source: view.avatars[row.key],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            row.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (row.unread > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: context.tokens.colors.info,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              row.unread > 99
                                                  ? '99+'
                                                  : '${row.unread}',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if ((view.previews[row.key] ?? '')
                                        .isNotEmpty)
                                      Text(
                                        view.previews[row.key]!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      '${row.request ? '消息请求 · ' : ''}${communicationTime(row.time, Localizations.localeOf(context))}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: context
                                                .tokens
                                                .colors
                                                .textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (organization?.state == 'unavailable')
          TextButton(
            onPressed: () => onOrganizationAction?.call('refresh', ''),
            child: const Text('组织会话加载失败 · 重试'),
          ),
        for (final action
            in organization?.buttons ?? const <MenuFeatureButton>[])
          if (const {'下一页', '首页', '更多组织会话', '组织会话首页'}.contains(action.label))
            TextButton(
              onPressed: organization?.busy == true
                  ? null
                  : () => onOrganizationAction?.call(action.key, ''),
              child: Text(action.label),
            ),
      ],
    );
  }
}
