import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_chat_controller.dart';
import 'marketplace_trade_chat_copy.dart';
import 'marketplace_trade_chat_parts.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// 好友与私信 · 交易消息 (0.7.2 G9, approved preview trade-chat-preview):
/// SCM trade chat, two-way with the SCM site and live. The list and the open
/// conversation side by side; below 680 px one at a time, like the messages
/// page. [header] is the 私信 / 交易消息 switch from the messages page.
class MarketplaceTradeChatView extends StatefulWidget {
  const MarketplaceTradeChatView(
    this.c, {
    required this.header,
    this.recentOrders,
    super.key,
  });
  final MarketplaceChatController c;
  final Widget header;
  final List<MarketChatAttachment> Function()? recentOrders;
  @override
  State<MarketplaceTradeChatView> createState() => _TradeChatState();
}

class _TradeChatState extends State<MarketplaceTradeChatView> {
  final _scroll = ScrollController();
  int? _lastTail;
  String? _lastRef;

  MarketplaceChatController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.setVisible(true);
    _scroll.addListener(_loadOnScroll);
    unawaited(c.loadConversations());
    c.requests.addListener(_request);
    _request();
    c.addListener(_follow);
  }

  @override
  void dispose() {
    c.setVisible(false);
    c.requests.removeListener(_request);
    c.removeListener(_follow);
    unawaited(c.close());
    _scroll.dispose();
    super.dispose();
  }

  /// Another surface asked for a conversation (交易单「私信对方」).
  void _request() {
    final reference = c.takeRequest();
    if (reference != null && reference.isNotEmpty && reference != c.openRef) {
      unawaited(c.open(reference));
    }
  }

  /// Keep the newest message in view when one arrives at the bottom.
  void _follow() {
    final tail = c.thread.lastOrNull?['id'] as int?;
    final changed = tail != _lastTail || c.openRef != _lastRef;
    _lastTail = tail;
    _lastRef = c.openRef;
    if (!changed ||
        _scroll.hasClients &&
            _scroll.position.maxScrollExtent - _scroll.offset > 80) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return c.openRef == null
              ? _directory(context)
              : _thread(context, narrow: true);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth < 900 ? 248 : 280,
              child: _directory(context),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _thread(context)),
          ],
        );
      },
    ),
  );

  void _loadOnScroll() {
    if (_scroll.hasClients &&
        _scroll.offset <= 24 &&
        !c.threadLoading &&
        (!c.threadEnd || c.hasGap)) {
      unawaited(c.loadOlder());
    }
  }

  Widget _directory(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaces.panel.fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header,
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Text(
              chatText(context, '与 SCM 网站互通 · 实时同步'),
              style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
            ),
          ),
          if (c.loading && c.conversations.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: c.conversations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: c.failed
                        ? marketTextAction(
                            key: const Key('trade-chat-retry'),
                            onPressed: c.loadConversations,
                            child: Text(
                              chatText(
                                context,
                                c.error == 'marketplace.reauthorize_required'
                                    ? '交易消息需要 SCM 授权更新后才能使用。'
                                    : '读取失败，点此重试',
                              ),
                            ),
                          )
                        : c.loading
                        ? const SizedBox.shrink()
                        : Text(
                            chatText(context, '还没有交易消息。在交易单或订单详情里可以私信对方。'),
                            style: TextStyle(
                              fontSize: 12,
                              color: t.colors.textSecondary,
                            ),
                          ),
                  )
                : ListView(
                    children: [
                      for (final row in c.conversations)
                        TradeChatConversationRow(
                          row,
                          selected: row['ref'] == c.openRef,
                          onOpen: () => unawaited(c.open('${row['ref']}')),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 解除拉黑 here, with the same confirmation as 我的交易 → 举报与拉黑.
  Future<void> _unblock(BuildContext context, String name) async {
    final ok = await tradeMotionDialog<bool>(
      context,
      (dialog) => AlertDialog(
        title: Text(chatText(context, '解除拉黑 {name}？', {'name': name})),
        content: Text(chatText(context, '解除后，对方可以再次向你发起交易和发私信，你也能看到对方的挂单。')),
        actions: [
          marketButtonAction(
            key: const Key('trade-chat-unblock-cancel'),
            TextButton(
              autofocus: true,
              onPressed: () => dismissStarBridgeDialog<bool>(
                dialog,
                source: StarBridgeActivationOrigin.sourceOf(dialog),
                result: false,
              ),
              child: Text(chatText(context, '取消')),
            ),
          ),
          marketButtonAction(
            key: const Key('trade-chat-unblock-confirm'),
            FilledButton(
              style: tradePrimaryStyle(dialog),
              onPressed: () => dismissStarBridgeDialog<bool>(
                dialog,
                source: StarBridgeActivationOrigin.sourceOf(dialog),
                result: true,
              ),
              child: Text(chatText(context, '解除拉黑')),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final confirmed = await c.unblock();
    if (!confirmed && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showOnly(
        starBridgeTimedSnackBar(content: Text(chatText(context, '没有解除成功，会话已刷新为 SCM 上的当前状态。'))),
      );
    }
  }

  Widget _thread(BuildContext context, {bool narrow = false}) {
    final t = context.tokens;
    final row = c.openConversation;
    if (c.openRef == null || row == null) {
      return Center(
        child: Text(
          chatText(context, '选择一个会话'),
          style: TextStyle(color: t.colors.textSecondary),
        ),
      );
    }
    final name = '${row['name'] ?? ''}';
    final blocked = row['blockedByMe'] == true || row['blockedMe'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: t.surfaces.panel.fill,
            border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
          ),
          child: Row(
            children: [
              if (narrow) ...[
                StarBridgeActionButton(
                  controlKey: const Key('trade-chat-back'),
                  kind: StarBridgeActionKind.quiet,
                  semanticLabel: chatText(context, '返回'),
                  onActivate: (_) => unawaited(c.close()),
                  child: const Text('←'),
                ),
                const SizedBox(width: 6),
              ],
              TradeChatAvatar(name, row['online']),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tradeChatPresence(context, row['online']),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              StarBridgeActionButton(
                controlKey: const Key('trade-chat-open-scm'),
                onActivate: (_) => unawaited(c.openInScm()),
                child: Text(chatText(context, '在 SCM 打开')),
              ),
            ],
          ),
        ),
        if (row['banHistory'] == true)
          _Banner(
            color: MarketplacePalette.attention,
            text: chatText(
              context,
              '该用户在 SCM 有 {n} 次封禁记录（最近原因：{reason}，{state}）。交易前请核对对方信誉。',
              {
                'n': '${(row['banCount'] as num?)?.toInt() ?? 1}',
                'reason': '${row['banReason'] ?? '—'}',
                'state': chatText(
                  context,
                  row['banActive'] == true ? '封禁中' : '已解封',
                ),
              },
            ),
          ),
        if (row['blockedByMe'] == true)
          _Banner(
            color: t.colors.danger,
            text: chatText(
              context,
              c.blockRef == null
                  ? '你已拉黑该用户，双方都不能再发消息或发起交易。可在“我的交易 → 举报与拉黑”解除。'
                  : '你已拉黑该用户，双方都不能再发消息或发起交易。',
            ),
            action: c.blockRef == null
                ? null
                : c.unblocking
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : marketTextAction(
                    key: const Key('trade-chat-unblock'),
                    onPressed: () => unawaited(_unblock(context, name)),
                    child: Text(chatText(context, '解除拉黑')),
                  ),
          )
        else if (row['blockedMe'] == true)
          _Banner(
            color: t.colors.danger,
            text: chatText(context, '对方已将你拉黑，无法发送消息或发起交易。'),
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              if (!c.threadEnd && c.thread.isNotEmpty)
                Center(
                  child: marketTextAction(
                    key: const Key('trade-chat-older'),
                    onPressed: c.threadLoading ? null : c.loadOlder,
                    child: Text(chatText(context, '加载更早的消息')),
                  ),
                ),
              if (c.threadFailed)
                Center(
                  child: marketTextAction(
                    key: const Key('trade-chat-thread-retry'),
                    onPressed: () => unawaited(c.open(c.openRef!)),
                    child: Text(chatText(context, '读取失败，点此重试')),
                  ),
                ),
              if (c.threadLoading && c.thread.isEmpty)
                const LinearProgressIndicator(minHeight: 2),
              for (final message in c.thread) ...[
                if (c.hasGap && message['id'] == c.gapStartId)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        const Divider(),
                        Text(
                          chatText(context, '更早的消息尚未同步，请向上滚动加载。'),
                          key: const Key('trade-chat-history-gap'),
                          style: TextStyle(
                            fontSize: 12,
                            color: t.colors.textSecondary,
                          ),
                        ),
                        marketTextAction(
                          key: const Key('trade-chat-gap-load'),
                          onPressed: c.threadLoading ? null : c.loadOlder,
                          child: Text(chatText(context, '加载更早的消息')),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TradeChatBubble(
                    message,
                    key: ValueKey(('trade-chat-message', message['id'])),
                  ),
                ),
              ],
              for (final pending in c.outgoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TradeChatOutgoingBubble(
                    pending,
                    refresh: () => unawaited(c.open(c.openRef!)),
                    resend: () => unawaited(c.resend(pending)),
                    remove: () => c.dismiss(pending),
                  ),
                ),
            ],
          ),
        ),
        TradeChatComposer(
          c,
          enabled: !blocked,
          recentOrders: widget.recentOrders,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text, this.action});
  final Color color;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    // The action button brings its own tap height.
    padding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: action == null ? 8 : 0,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      border: Border(left: BorderSide(color: color, width: 3)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, height: 1.55)),
        ),
        if (action != null) ...[const SizedBox(width: 10), action!],
      ],
    ),
  );
}
