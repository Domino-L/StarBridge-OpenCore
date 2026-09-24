import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_logo.dart';
import '../../features/communities/community_gameplay_tags.dart';
import '../../features/communities/community_directory_card.dart'
    show communityLanguageLabel;
import 'menu_feature_view.dart';

/// Joined-organization chooser using the client's card, logo and tag language.
/// Only display data and expiring action keys are accepted here.
class MenuOrganizationDirectory extends StatefulWidget {
  const MenuOrganizationDirectory({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  @override
  State<MenuOrganizationDirectory> createState() =>
      _MenuOrganizationDirectoryState();
}

class _MenuOrganizationDirectoryState extends State<MenuOrganizationDirectory> {
  late final _query = TextEditingController(
    text: widget.view.organization!.query,
  );
  @override
  void didUpdateWidget(MenuOrganizationDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.scope != widget.view.scope) {
      _query.text = widget.view.organization!.query;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = view.organization!, tokens = context.tokens;
    final colors = tokens.colors, text = Theme.of(context).textTheme;
    final search = view.buttons.where((a) => a.label == '搜索组织').firstOrNull;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('我的组织', style: text.titleLarge)),
                OutlinedButton(
                  onPressed: view.busy
                      ? null
                      : () => widget.onAction('refresh', ''),
                  child: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '选择组织，查看成员、舰船、公告与聊天。',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (search != null)
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
            if (view.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  view.notice,
                  style: TextStyle(color: colors.warning),
                ),
              ),
            const SizedBox(height: 16),
            if (view.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  org.query.isEmpty
                      ? '尚未加入组织，可在客户端的社区组织页面查找。'
                      : '没有匹配的已加入组织，请调整搜索条件。',
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 760 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.5
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < view.rows.length; i++)
                      SizedBox(width: width, child: _card(context, i)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final action in view.buttons.where(
                  (a) => a.label != '搜索组织',
                ))
                  OutlinedButton(
                    onPressed: view.busy
                        ? null
                        : () => widget.onAction(action.key, ''),
                    child: Text(action.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, int index) {
    final view = widget.view,
        row = view.rows[index],
        data = view.organization!.rows[index];
    final tokens = context.tokens, text = Theme.of(context).textTheme;
    final open = row.buttons.where((a) => a.label == '打开组织').firstOrNull;
    void Function()? onOpen = view.busy || open == null
        ? null
        : () => widget.onAction(open.key, '');
    final relation = switch (data.relationship) {
      'owner' => '组织负责人',
      'member' => '已加入',
      _ => '组织成员',
    };
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommunityLogo(data: data.logo, size: 48, framed: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                relation,
                style: text.bodySmall?.copyWith(
                  color: data.relationship == 'owner'
                      ? tokens.colors.warning
                      : tokens.colors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: tokens.surfaces.panel.border),
      ),
      child: InkWell(
        key: ValueKey('menu-organization-choice-$index'),
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text(
                    '${data.memberCount ?? '—'} 位成员',
                    style: text.titleMedium?.copyWith(
                      color: tokens.colors.info,
                    ),
                  ),
                  if (data.language.isNotEmpty)
                    Text(
                      communityLanguageLabel(context, data.language),
                      style: text.bodySmall,
                    ),
                ],
              ),
              if (data.activeTime.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '活动时间 · ${data.activeTime}',
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
              if (data.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CommunityGameplayTags(value: data.tags),
                ),
              if (row.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    row.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onOpen,
                  child: const Text('进入组织'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
