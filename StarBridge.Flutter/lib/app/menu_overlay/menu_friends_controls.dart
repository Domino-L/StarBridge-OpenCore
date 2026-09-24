import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_style.dart';
import 'menu_friends_view.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import '../presence/manual_presence_widgets.dart';

String menuFriendActionLabel(String action) => switch (action) {
  'send' => '发送好友申请',
  'accept' => '接受申请',
  'reject' => '拒绝申请',
  'cancel' => '撤回申请',
  'remove' => '移除好友',
  'block' => '屏蔽此人',
  'unblock' => '解除屏蔽',
  _ => '',
};

class MenuFriendsControls extends StatefulWidget {
  const MenuFriendsControls({
    super.key,
    required this.view,
    required this.onAction,
    this.onFilter,
  });
  final MenuFriendsView view;
  final void Function(String action, String key, String value) onAction;
  final ValueChanged<String>? onFilter;
  @override
  State<MenuFriendsControls> createState() => _MenuFriendsControlsState();
}

class _MenuFriendsControlsState extends State<MenuFriendsControls> {
  late final _query = TextEditingController(text: widget.view.query);
  final _confirmationAnchor = GlobalKey(), _feedbackAnchor = GlobalKey();
  @override
  void didUpdateWidget(MenuFriendsControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.query != widget.view.query ||
        oldWidget.view.section != widget.view.section) {
      _query.text = widget.view.query;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFilter?.call(_query.text);
      });
    }
    final token = widget.view.confirmation?.token;
    final anchor = token != null && token != oldWidget.view.confirmation?.token
        ? _confirmationAnchor
        : widget.view.feedback.isNotEmpty &&
              widget.view.feedback != oldWidget.view.feedback
        ? _feedbackAnchor
        : null;
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = anchor.currentContext;
        if (target != null) {
          unawaited(Scrollable.ensureVisible(target, alignment: .15));
        }
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, pending = widget.view.confirmation;
    Widget action(
      String label,
      String command, {
      String key = '',
      String value = '',
    }) => BridgeMenuAction(
      key: ValueKey('friends-$command-${key.isEmpty ? value : key}'),
      label: label,
      onPressed: view.busy ? null : () => widget.onAction(command, key, value),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(label),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.self case final own?) ...[
          Row(
            children: [
              MenuInlineAvatar(
                source: view.identity?.avatar,
                name: view.identity?.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.identity?.name.isNotEmpty == true
                          ? view.identity!.name
                          : '我的状态',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (view.identity?.handle.isNotEmpty == true)
                      Text(
                        view.identity!.handle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BridgeInk.muted,
                        ),
                      ),
                    MenuAnchor(
                      style: const MenuStyle(
                        backgroundColor: WidgetStatePropertyAll(
                          BridgeInk.ground,
                        ),
                      ),
                      menuChildren: [
                        for (final mode in const ['online', 'invisible'])
                          MenuItemButton(
                            onPressed: own.change && !own.busy
                                ? () =>
                                      widget.onAction('presence', own.key, mode)
                                : null,
                            child: Text(
                              mode == 'online' ? '在线' : '隐身',
                              style: TextStyle(color: menuPresenceColor(mode)),
                            ),
                          ),
                      ],
                      builder: (context, controller, child) => BridgeMenuAction(
                        label: '更改我的在线状态',
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        onPressed: own.change && !own.busy
                            ? () => controller.isOpen
                                  ? controller.close()
                                  : controller.open()
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: menuPresenceColor(
                                  own.status.replaceFirst('presence.', ''),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                manualPresenceText(context, own.status),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: menuPresenceColor(
                                    own.status.replaceFirst('presence.', ''),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const MenuGlyphView(
                              MenuGlyph.down,
                              size: 16,
                              color: BridgeInk.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (own.busy) const BridgeCaption('正在切换状态…'),
          if (own.failed) const BridgeCaption('状态未更新，请核对后重试。'),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('friends-account-search'),
                controller: _query,
                readOnly: view.busy,
                style: const TextStyle(
                  fontSize: 13,
                  color: BridgeInk.text,
                  fontFamily: 'Source Sans 3',
                  fontFamilyFallback: ['Source Han Sans CN'],
                ),
                onChanged: widget.onFilter,
                onSubmitted: view.busy
                    ? null
                    : (value) => widget.onAction('search', '', value),
                textInputAction: TextInputAction.search,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.text.length <= 128 ? newValue : oldValue,
                  ),
                ],
                decoration: const InputDecoration(
                  hintText: '搜索好友 / 添加好友',
                  hintStyle: TextStyle(
                    color: BridgeInk.muted,
                    fontSize: 13,
                    fontFamily: 'Source Sans 3',
                    fontFamilyFallback: ['Source Han Sans CN'],
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: BridgeInk.ground,
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: BridgeInk.line),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: BridgeInk.blue),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: '搜索账号（Enter）',
              child: BridgeMenuAction(
                key: const ValueKey('friends-search'),
                label: '搜索账号',
                onPressed: view.busy
                    ? null
                    : () => widget.onAction('search', '', _query.text),
                padding: const EdgeInsets.all(8),
                child: const MenuGlyphView(
                  MenuGlyph.search,
                  size: 18,
                  color: BridgeInk.blue,
                ),
              ),
            ),
            Tooltip(
              message: '刷新列表',
              child: BridgeMenuAction(
                key: const ValueKey('friends-refresh-'),
                label: '刷新列表',
                onPressed: view.busy
                    ? null
                    : () => widget.onAction('refresh', '', ''),
                padding: const EdgeInsets.all(8),
                child: const MenuGlyphView(
                  MenuGlyph.refresh,
                  size: 18,
                  color: BridgeInk.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: view.section == 'friends'
                  ? const Text(
                      '查看状态 · 点选好友开始聊天',
                      style: TextStyle(fontSize: 12, color: BridgeInk.muted),
                    )
                  : BridgeMenuAction(
                      key: const ValueKey('friends-section-friends'),
                      label: '返回好友列表',
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      onPressed: view.busy
                          ? null
                          : () => widget.onAction('section', '', 'friends'),
                      child: const Text(
                        '‹ 返回好友列表',
                        style: TextStyle(color: BridgeInk.blue, fontSize: 13),
                      ),
                    ),
            ),
            MenuAnchor(
              style: const MenuStyle(
                backgroundColor: WidgetStatePropertyAll(BridgeInk.ground),
              ),
              menuChildren: [
                for (final section in const {
                  'incoming': '收到的申请',
                  'outgoing': '已发出的申请',
                  'blocked': '屏蔽名单',
                }.entries)
                  MenuItemButton(
                    key: ValueKey('friends-section-${section.key}'),
                    onPressed: view.busy
                        ? null
                        : () => widget.onAction('section', '', section.key),
                    child: Text(section.value),
                  ),
              ],
              builder: (context, controller, child) => BridgeMenuAction(
                key: const ValueKey('friends-manage'),
                label: '好友管理',
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                child: const Text(
                  '管理 ▾',
                  style: TextStyle(fontSize: 13, color: BridgeInk.blue),
                ),
              ),
            ),
          ],
        ),
        if (view.busy) const BridgeCaption('正在处理，请勿重复操作…'),
        if (view.feedback.isNotEmpty)
          BridgeCaption(key: _feedbackAnchor, switch (view.feedback) {
            'invalidSearch' => '请输入 2–128 个字符的账号或呼号。',
            'expired' => '此操作已失效，请刷新列表后重新选择。',
            'rejected' => '操作未完成。请刷新列表确认关系与权限后再试。',
            'unknown' => '操作结果尚未确认。请刷新列表核对，勿重复操作。',
            'reviewed' => '列表已更新，请核对当前关系。',
            _ =>
              '${menuFriendActionLabel(view.feedback.replaceFirst('success.', ''))}已完成。',
          }),
        if (view.requiresRefresh) const BridgeCaption('核对列表前暂不可继续好友操作。'),
        if (pending != null)
          Container(
            key: const ValueKey('friends-confirmation'),
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: BridgeInk.blue)),
            ),
            child: Column(
              key: _confirmationAnchor,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${menuFriendActionLabel(pending.action)}：${pending.name}？',
                ),
                if (pending.action == 'remove')
                  const BridgeCaption('移除后需要重新发送好友申请才能恢复好友关系。'),
                if (pending.action == 'block')
                  const BridgeCaption('现有好友或申请关系会被移除，对方无法再向你发送好友申请。可在屏蔽名单中解除。'),
                Wrap(
                  children: [
                    action(
                      menuFriendActionLabel(pending.action),
                      'confirm',
                      key: pending.token,
                    ),
                    action('取消', 'dismiss'),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
