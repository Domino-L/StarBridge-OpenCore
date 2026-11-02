import '../../shared/guide/guide_empty_state.dart';
import '../../app/localization/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../settings/help_support_action.dart';
import '../common/social_read_activity.dart';

import '../../app/routing/open_destination_intent.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/notification_category_palette.dart';
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
  final _viewport = GlobalKey();
  final _rows = <String, GlobalKey>{};
  final _attempted = <InboxItem>{};
  Timer? _readTimer;
  late SocialReadActivityBinding _readActivity;

  // Both the main and detached notification views use this visibility gate.
  // Background fetching and offscreen cache construction are not reading.
  void _readVisible() {
    if (!mounted ||
        !NativeViewportScope.isActive(context) ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    final c = widget.controller;
    if (!c.ready || c.busy || c.error != null) return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final visible = <InboxItem>[];
    for (final item in c.items) {
      if (item.read || _attempted.contains(item)) continue;
      final row = _rows[item.reference]?.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) continue;
      final rect = row.localToGlobal(Offset.zero) & row.size;
      // Require meaningful content exposure, not a one-pixel edge intersection.
      final overlap = bounds.intersect(rect);
      if (overlap.width > 0 && overlap.height >= 48) visible.add(item);
    }
    if (visible.isEmpty) return;
    _attempted.addAll(visible);
    unawaited(c.markRead(visible));
  }

  @override
  void dispose() {
    _readActivity.dispose();
    _readTimer?.cancel();
    super.dispose();
  }

  void _readClicked(InboxItem item) {
    final controller = widget.controller;
    if (!item.read && !controller.busy && _attempted.add(item)) {
      unawaited(controller.markRead([item]));
    }
  }

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
    _readActivity = SocialReadActivityBinding(
      widget.controller,
      () => widget.controller.busy,
      initialRead: !widget.controller.ready,
    );
    widget.controller.refresh(reuseFresh: true);
    _readTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _readVisible(),
    );
  }

  @override
  void didUpdateWidget(NotificationInboxPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      _readActivity.dispose();
      _readActivity = SocialReadActivityBinding(
        widget.controller,
        () => widget.controller.busy,
        initialRead: !widget.controller.ready,
      );
    }
  }

  String label(String category) => switch (category) {
    'trade' => t('交易', '交易', 'Trades'),
    'tradeChat' => t('交易私信', '交易私訊', 'Trade messages'),
    'social' => t('好友', '好友', 'Social'),
    'fleet' => t('组织 / 主舰队', '組織 / 主艦隊', 'Organizations'),
    'room' => t('房间', '房間', 'Rooms'),
    'system' => t('系统', '系統', 'System'),
    'safety' => t('账号安全', '帳號安全', 'Account safety'),
    'all' => t('全部类型', '全部類型', 'All types'),
    _ => t('其他', '其他', 'Other'),
  };
  String? route(InboxItem item) => switch (item.target) {
    'friend_requests' => '/friends',
    'fleet_applications' => '/communities',
    'room_invitations' => '/rooms/invitations',
    'room_applications' => '/rooms',
    'overlay_settings' => '/overlay',
    // SCM station messages (0.7.2): 我的交易 and 交易消息.
    'marketplace_trade' => '/marketplace?section=trades',
    'marketplace_chat' => '/messages?section=trade',
    _ => null,
  };
  Widget? _local(BuildContext context) => guideOnlineRequired(
    context,
    AppStrings.of(context).text('navigation.notifications'),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      _attempted.removeWhere((item) => !c.items.contains(item));
      final references = c.items.map((item) => item.reference).toSet();
      _rows.removeWhere((reference, _) => !references.contains(reference));
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
      final content = ListView(
        key: _viewport,
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
                  HelpSupportAction(
                    controlKey: const Key('notification-refresh'),
                    onActivate: c.busy
                        ? null
                        : (_) {
                            _attempted.clear();
                            c.refresh();
                          },
                    child: Text(t('刷新', '重新整理', 'Refresh')),
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
                StarBridgeChoiceChip(
                  controlKey: Key('notification-filter-$key'),
                  selected: filter == key,
                  onSelected: (_) => setState(() => filter = key),
                  label: switch (key) {
                    'unread' => t('未读', '未讀', 'Unread'),
                    'action' => t('待处理', '待處理', 'Action required'),
                    _ => t('全部', '全部', 'All'),
                  },
                ),
              const SizedBox(width: 12),
              StarBridgeCompactSelect<String>(
                identity: 'notification-category',
                controlKey: const Key('notification-category'),
                semanticLabel: t('类别', '類別', 'Category'),
                value: category,
                options: [
                  for (final key in [
                    'all',
                    if (c.items.any((x) => x.category == 'trade')) 'trade',
                    if (c.items.any((x) => x.category == 'tradeChat'))
                      'tradeChat',
                    'social',
                    'fleet',
                    'room',
                    'system',
                    'safety',
                  ])
                    StarBridgeSelectOption(value: key, label: label(key)),
                ],
                onSelected: (value, _) => setState(() => category = value),
              ),
            ],
          ),
          if (c.busy)
            SocialReadActivity(
              key: ValueKey((widget.controller, _readActivity.revision)),
              height: 4,
              source: _readActivity.source,
              opening: _readActivity.opening,
              label: t('正在更新通知…', '正在更新通知…', 'Updating notifications…'),
            ),
          if (c.error == 'signedOut' && _local(context) != null)
            _local(context)!
          else if (c.error != null)
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
          if (c.ready &&
              visible.isEmpty &&
              !c.busy &&
              c.items.isEmpty &&
              GuideEmptyState.active(context))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: GuideEmptyState('notifications'),
            )
          else if (c.ready && visible.isEmpty && !c.busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(t('这里暂无通知', '這裡暫無通知', 'No notifications here')),
              ),
            ),
          for (final item in visible)
            Card.outlined(
              key: _rows.putIfAbsent(item.reference, GlobalKey.new),
              clipBehavior: Clip.antiAlias,
              // 0.7.2 category colors: a stripe, the icon and the name.
              child: CustomPaint(
                foregroundPainter: _CategoryStripe(
                  NotificationCategoryPalette.of(
                    item.category,
                    Theme.of(context).brightness,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StarBridgeIcon(
                                _categoryIcon(item.category),
                                size: 14,
                                color: NotificationCategoryPalette.of(
                                  item.category,
                                  Theme.of(context).brightness,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label(item.category),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: NotificationCategoryPalette.of(
                                    item.category,
                                    Theme.of(context).brightness,
                                  ),
                                ),
                              ),
                            ],
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
                          if (item.available &&
                              item.target == 'account_safety' &&
                              widget.openSafety != null)
                            HelpSupportAction(
                              kind: StarBridgeActionKind.secondary,
                              controlKey: ValueKey((
                                'notification-safety',
                                item.reference,
                              )),
                              onActivate: (_) {
                                _readClicked(item);
                                widget.openSafety?.call();
                              },
                              child: Text(
                                t('查看账号状态', '查看帳號狀態', 'View account status'),
                              ),
                            ),
                          if (item.available && route(item) != null)
                            HelpSupportAction(
                              kind: StarBridgeActionKind.secondary,
                              controlKey: ValueKey((
                                'notification-destination',
                                item.reference,
                              )),
                              onActivate: (_) {
                                _readClicked(item);
                                Actions.invoke(
                                  context,
                                  OpenDestinationIntent(route(item)!),
                                );
                              },
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
            ),
        ],
      );
      return LoadingContentProbe(
        route: '/notifications',
        status: c.busy
            ? (c.items.isEmpty
                  ? LoadingContentStatus.waiting
                  : LoadingContentStatus.partial)
            : c.error != null
            ? (c.error == 'signedOut' || c.error == 'unavailable'
                  ? LoadingContentStatus.unavailable
                  : LoadingContentStatus.failed)
            : !c.ready
            ? LoadingContentStatus.unavailable
            : visible.isEmpty
            ? LoadingContentStatus.empty
            : LoadingContentStatus.data,
        items: visible.length,
        child: content,
      );
    },
  );
}

StarBridgeIconSemantic _categoryIcon(String category) => switch (category) {
  'trade' => StarBridgeIconSemantic.marketplace,
  'tradeChat' => StarBridgeIconSemantic.messages,
  'social' => StarBridgeIconSemantic.friends,
  'fleet' => StarBridgeIconSemantic.community,
  'room' => StarBridgeIconSemantic.room,
  'safety' => StarBridgeIconSemantic.privacy,
  _ => StarBridgeIconSemantic.notifications,
};

/// The category stripe along the card's leading edge, painted over the card
/// so its layout (and every measured control inside) stays as it was.
class _CategoryStripe extends CustomPainter {
  const _CategoryStripe(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromLTWH(0, 0, 3, size.height),
    Paint()..color = color,
  );
  @override
  bool shouldRepaint(_CategoryStripe old) => old.color != color;
}
