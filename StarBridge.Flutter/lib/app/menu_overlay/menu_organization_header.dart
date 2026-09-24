import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_logo.dart';
import 'menu_feature_view.dart';
import 'menu_friends_view.dart' show menuPresenceColor;

class MenuOrganizationHeader extends StatelessWidget {
  const MenuOrganizationHeader({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  @override
  Widget build(BuildContext context) {
    final org = view.organization!,
        tokens = context.tokens,
        text = Theme.of(context).textTheme;
    final change = view.buttons.where((a) => a.label == '返回组织列表').firstOrNull;
    final identity = Row(
      children: [
        CommunityLogo(data: org.logo, size: 44, framed: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(view.title, style: text.titleLarge),
              if (org.code.isNotEmpty)
                Text(
                  org.code,
                  style: text.bodySmall?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    Widget metric(String label, int count, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: Border.all(color: tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (change != null)
                    OutlinedButton(
                      onPressed: view.busy
                          ? null
                          : () => onAction(change.key, ''),
                      child: const Text('切换组织'),
                    ),
                  OutlinedButton(
                    onPressed: view.busy ? null : () => onAction('refresh', ''),
                    child: const Text('刷新'),
                  ),
                ],
              );
              return constraints.maxWidth >= 600 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5
                  ? Row(
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 16),
                        actions,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [identity, const SizedBox(height: 12), actions],
                    );
            },
          ),
          if (org.tab == 'members' || org.tab == 'ships') ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 36,
              runSpacing: 12,
              children: [
                if (org.tab == 'members') ...[
                  metric(
                    '应用在线',
                    org.rows.where((r) => r.presence == 'online').length,
                    menuPresenceColor('online'),
                  ),
                  metric(
                    '游戏中',
                    org.rows.where((r) => r.presence == 'inGame').length,
                    menuPresenceColor('inGame'),
                  ),
                ],
                metric(
                  org.tab == 'members' ? '成员' : '共享舰船',
                  org.total,
                  tokens.colors.textPrimary,
                ),
              ],
            ),
            if (org.tab == 'members')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '状态统计 · 当前页',
                  style: text.bodySmall?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ),
          ],
          if (org.description.isNotEmpty || org.activeTime.isNotEmpty) ...[
            Divider(height: 24, color: tokens.surfaces.panel.border),
            if (org.description.isNotEmpty)
              Text(org.description, style: text.bodyMedium),
            if (org.activeTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '活动时间 · ${org.activeTime}',
                  style: text.bodySmall?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
