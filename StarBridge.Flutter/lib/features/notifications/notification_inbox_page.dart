import 'package:flutter/material.dart';

import '../../app/routing/open_destination_intent.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_inbox_controller.dart';

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({
    required this.controller,
    this.openSafety,
    super.key,
  });
  final NotificationInboxController controller;
  final VoidCallback? openSafety;
  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  String filter = 'all', category = 'all';
  String t(String cn, String tw, String en) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode != 'zh'
        ? en
        : locale.countryCode == 'TW'
        ? tw
        : cn;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.refresh(reuseFresh: true);
  }

  String label(String category) => switch (category) {
    'social' => t('好友', '好友', 'Social'),
    'fleet' => t('组织', '組織', 'Organizations'),
    'room' => t('房间', '房間', 'Rooms'),
    'system' => t('系统', '系統', 'System'),
    'safety' => t('账号安全', '帳號安全', 'Account safety'),
    'all' => t('全部类型', '全部類型', 'All types'),
    _ => t('其他', '其他', 'Other'),
  };
  String? route(InboxItem item) => switch (item.target) {
    'friend_requests' => '/friends',
    'fleet_applications' => '/communities',
    'room_invitations' || 'room_applications' => '/rooms',
    'overlay_settings' => '/overlay',
    _ => null,
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final colors = context.tokens.colors;
      final visible = c.items
          .where(
            (x) =>
                (category == 'all' || x.category == category) &&
                (filter == 'all' ||
                    filter == 'unread' && !x.read ||
                    filter == 'action' &&
                        x.available &&
                        x.priority == 'action_required'),
          )
          .toList();
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('通知中心', '通知中心', 'Notifications'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(
                      '系统消息、邀请、加入申请与处理结果。',
                      '系統訊息、邀請、加入申請與處理結果。',
                      'System messages, invitations, applications and outcomes.',
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: c.busy ? null : c.refresh,
                    child: Text(t('刷新', '重新整理', 'Refresh')),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !visible.any((x) => !x.read)
                        ? null
                        : () => c.markRead(visible),
                    child: Text(t('当前列表标为已读', '目前清單標為已讀', 'Mark list as read')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in ['all', 'unread', 'action'])
                ChoiceChip(
                  selected: filter == key,
                  onSelected: (_) => setState(() => filter = key),
                  label: Text(switch (key) {
                    'unread' => t('未读', '未讀', 'Unread'),
                    'action' => t('待处理', '待處理', 'Action required'),
                    _ => t('全部', '全部', 'All'),
                  }),
                ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: category,
                items: [
                  for (final key in [
                    'all',
                    'social',
                    'fleet',
                    'room',
                    'system',
                    'safety',
                  ])
                    DropdownMenuItem(value: key, child: Text(label(key))),
                ],
                onChanged: (value) => setState(() => category = value!),
              ),
            ],
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                c.error == 'signedOut'
                    ? t(
                        '登录后查看通知。',
                        '登入後查看通知。',
                        'Sign in to view notifications.',
                      )
                    : c.error == 'write'
                    ? t(
                        '未能确认已读结果，请刷新后重试。',
                        '未能確認已讀結果，請重新整理後重試。',
                        'Read status could not be confirmed. Refresh before retrying.',
                      )
                    : t(
                        '暂时无法读取通知，请稍后刷新。',
                        '暫時無法讀取通知，請稍後重新整理。',
                        'Notifications unavailable. Try refreshing shortly.',
                      ),
                style: TextStyle(color: colors.warning),
              ),
            ),
          if (c.ready && visible.isEmpty && !c.busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(t('这里暂无通知', '這裡暫無通知', 'No notifications here')),
              ),
            ),
          for (final item in visible)
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          label(item.category),
                          style: TextStyle(color: colors.info),
                        ),
                        Text(
                          MaterialLocalizations.of(context)
                              .formatShortDate(item.created.toLocal()),
                        ),
                        if (!item.read)
                          Text(
                            t('未读', '未讀', 'Unread'),
                            style: TextStyle(color: colors.info),
                          ),
                        if (item.available &&
                            item.priority == 'action_required')
                          Text(
                            t('需要处理', '需要處理', 'Action required'),
                            style: TextStyle(color: colors.warning),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(item.body),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (!item.read)
                          TextButton(
                            onPressed: c.busy ? null : () => c.markRead([item]),
                            child: Text(t('标为已读', '標為已讀', 'Mark as read')),
                          ),
                        if (item.available &&
                            item.target == 'account_safety' &&
                            widget.openSafety != null)
                          OutlinedButton(
                            onPressed: widget.openSafety,
                            child: Text(
                              t('查看账号状态', '查看帳號狀態', 'View account status'),
                            ),
                          ),
                        if (item.available && route(item) != null)
                          OutlinedButton(
                            onPressed: () => Actions.invoke(
                              context,
                              OpenDestinationIntent(route(item)!),
                            ),
                            child: Text(
                              t('前往相关页面', '前往相關頁面', 'Open related page'),
                            ),
                          ),
                        if (!item.available)
                          Text(
                            t(
                              '该事项已失效',
                              '該事項已失效',
                              'This item is no longer available',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
