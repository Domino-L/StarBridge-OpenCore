import 'package:flutter/material.dart';

import '../shell/widgets/attention_badge.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_logo.dart';
import 'menu_organization_view.dart';

class MenuOrganizationSidebar extends StatefulWidget {
  const MenuOrganizationSidebar({
    super.key,
    required this.items,
    required this.onSelect,
    required this.busy,
  });
  final List<MenuOrganizationNavigationItem> items;
  final ValueChanged<String> onSelect;
  final bool busy;
  @override
  State<MenuOrganizationSidebar> createState() =>
      _MenuOrganizationSidebarState();
}

class _MenuOrganizationSidebarState extends State<MenuOrganizationSidebar> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final items = widget.items.where(
      (item) => item.name.toLowerCase().contains(query.toLowerCase()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('我的组织', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            key: const ValueKey('menu-organization-search'),
            decoration: const InputDecoration(
              hintText: '搜索已加入的组织',
              isDense: true,
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有匹配的组织'),
                ),
              for (final item in items)
                Material(
                  color: item.selected
                      ? colors.info.withValues(alpha: .12)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: widget.busy ? null : () => widget.onSelect(item.key),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CommunityLogo(
                            data: item.avatar,
                            size: 40,
                            framed: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                if (item.time.isNotEmpty)
                                  Text(
                                    item.time,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if ((item.unread ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: AttentionCount(count: item.unread!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
