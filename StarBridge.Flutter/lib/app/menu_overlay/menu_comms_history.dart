import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'menu_chat_widgets.dart';
import 'menu_comms_view.dart';
import 'menu_comms_composer.dart';
import 'menu_inline_avatar.dart';
import 'menu_loading.dart';
import 'menu_avatar_actions.dart';
import 'menu_visible_receipts.dart';
import 'menu_feature_view.dart';

class MenuCommsHistory extends StatefulWidget {
  const MenuCommsHistory({
    super.key,
    required this.view,
    required this.active,
    required this.onAction,
    this.onProfile,
    this.onCompose,
    this.disconnected = false,
  });
  final MenuCommsView view;
  final bool active, disconnected;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final void Function(String, String, String, int)? onCompose;
  @override
  State<MenuCommsHistory> createState() => _MenuCommsHistoryState();
}

class _MenuCommsHistoryState extends State<MenuCommsHistory> {
  final _scroll = ScrollController();
  bool _newMessages = false;
  @override
  void didUpdateWidget(MenuCommsHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.view, next = widget.view;
    if (previous.profileKey != next.profileKey ||
        previous.pageKey != next.pageKey) {
      _newMessages = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    } else if (previous.messages.lastOrNull != next.messages.lastOrNull &&
        _scroll.hasClients &&
        _scroll.offset > 48) {
      final pixels = _scroll.offset, extent = _scroll.position.maxScrollExtent;
      _newMessages = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(
          (pixels + _scroll.position.maxScrollExtent - extent).clamp(
            0,
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget action(String key, String title) => OutlinedButton(
    key: ValueKey('menu-comms-$key'),
    onPressed: widget.view.busy ? null : () => widget.onAction(key, ''),
    child: Text(title),
  );
  Widget portrait() => MenuAvatarActions(
    name: widget.view.name ?? '',
    onProfile: widget.onProfile == null || widget.view.profileKey == null
        ? null
        : () => widget.onProfile!(widget.view.profileKey!),
    child: MenuInlineAvatar(name: widget.view.name, source: widget.view.avatar),
  );
  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (view.name == null) return const Center(child: Text('选择一个会话开始聊天'));
    final status = switch (view.conversationState) {
      'request_incoming' => '消息请求 · 回复后建立会话',
      'request_outgoing' => '消息请求已发出，等待对方回应',
      'friend' => '好友',
      'accepted' => '已建立会话',
      _ => view.request ? '消息请求' : '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuChatHeader(
          title: view.name!,
          subtitle: status,
          portrait: portrait(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            action('back', '返回会话列表'),
            if (view.hasOlder) action('older', '较早消息'),
            action('latest', view.olderPage ? '最新消息' : '刷新消息'),
            if (view.inviteAvailable && view.canSend)
              action('inviteSend', '邀请加入组织'),
            if (view.archiveAvailable)
              MenuFeatureAction(
                action: (
                  key: 'clearLocal',
                  label: '清除本机记录',
                  confirm: '清除此会话的本机缓存？在线消息不会删除，后续读取可再次缓存。',
                  input: null,
                  limit: 128,
                ),
                enabled: !view.busy,
                onAction: widget.onAction,
              ),
          ],
        ),
        if (view.notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    view.notice,
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ),
                action('retry', '重新读取'),
              ],
            ),
          ),
        if (view.readStatus == 'failed')
          Text(
            '已读状态未同步，请刷新消息重试。',
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        if (view.refreshing) const MenuLoading(),
        Divider(color: context.tokens.surfaces.panel.border),
        Expanded(
          child: MenuVisibleReceipts(
            active: widget.active && view.notice.isEmpty,
            tokens: view.receipts,
            onRead: (key) => widget.onAction('read', key),
            builder: (anchors) => view.messages.isEmpty
                ? const Center(child: Text('暂无消息，可以从下面开始聊天。'))
                : MenuChatScroll(
                    controller: _scroll,
                    child: ListView.builder(
                      key: const ValueKey('menu-message-history'),
                      controller: _scroll,
                      reverse: true,
                      itemCount: view.messages.length,
                      itemBuilder: (context, reverseIndex) {
                        final index = view.messages.length - 1 - reverseIndex,
                            message = view.messages[index];
                        final time = message.time.toLocal();
                        String pad(int n) => n.toString().padLeft(2, '0');
                        return KeyedSubtree(
                          key: anchors[index],
                          child: MenuChatMessage(
                            incoming: message.incoming,
                            sender: message.incoming ? view.name! : '我',
                            time:
                                '${time.year}/${time.month}/${time.day} ${pad(time.hour)}:${pad(time.minute)}',
                            portrait: message.incoming
                                ? portrait()
                                : MenuAvatarActions(
                                    name: '我',
                                    onProfile: widget.onProfile == null
                                        ? null
                                        : () => widget.onProfile!('self'),
                                    child: MenuInlineAvatar(
                                      name: '我',
                                      source: view.ownAvatar,
                                    ),
                                  ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message.text.isNotEmpty)
                                  SelectableText(message.text),
                                if ((view.attachments[index] ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(view.attachments[index]!),
                                ],
                                if (view.attachmentKeys[index] case final key?)
                                  OutlinedButton(
                                    onPressed:
                                        view.busy || view.notice.isNotEmpty
                                        ? null
                                        : () => widget.onAction(
                                            'attachment',
                                            key,
                                          ),
                                    child: const Text('查看组织邀请'),
                                  )
                                else if (message.attachment)
                                  const Text('此附件类型暂不支持在菜单内操作。'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        if (_newMessages)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('menu-comms-new-messages'),
              onPressed: () {
                if (_scroll.hasClients) _scroll.jumpTo(0);
                setState(() => _newMessages = false);
              },
              child: const Text('有新消息 · 回到底部'),
            ),
          ),
        if (view.compose && view.profileKey != null && widget.onCompose != null)
          MenuCommsComposer(
            key: ValueKey('composer-${view.profileKey}'),
            view: view,
            onCompose: widget.onCompose!,
            disconnected: widget.disconnected,
          )
        else
          const Padding(padding: EdgeInsets.all(12), child: Text('当前会话不可发送消息')),
      ],
    );
  }
}
