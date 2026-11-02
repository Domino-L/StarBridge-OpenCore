import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_chat_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_port.dart';
import 'marketplace_records_page.dart' show marketRecordTime;
import 'marketplace_surfaces.dart';
import 'marketplace_trade_chat_copy.dart';
import 'marketplace_widgets.dart';

/// Initial square with the SCM presence dot (online / away / offline).
class TradeChatAvatar extends StatelessWidget {
  const TradeChatAvatar(this.name, this.online, {this.size = 36, super.key});
  final String name;
  final Object? online;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = (online as num?)?.toInt();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MarketplacePalette.artBackdrop,
              border: Border.all(color: marketLine(context)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.colors.textSecondary,
              ),
            ),
          ),
          if (status != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == 1
                      ? t.colors.success
                      : status == 2
                      ? MarketplacePalette.attention
                      : t.colors.textDisabled,
                  border: Border.all(color: t.surfaces.panel.fill, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String tradeChatPresence(BuildContext context, Object? online) =>
    switch ((online as num?)?.toInt()) {
      1 => chatText(context, '在线'),
      2 => chatText(context, '离开'),
      0 => chatText(context, '离线'),
      _ => '',
    };

/// One row of the 交易消息 list: full handle (as on SCM), last line, time,
/// unread count and a ban-history hint.
class TradeChatConversationRow extends StatelessWidget {
  const TradeChatConversationRow(
    this.row, {
    required this.selected,
    required this.onOpen,
    super.key,
  });
  final MarketRow row;
  final bool selected;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unread = (row['unread'] as num?)?.toInt() ?? 0;
    final bans = (row['banCount'] as num?)?.toInt() ?? 0;
    return StarBridgeActionRow(
      controlKey: ValueKey(('trade-chat-conversation', '${row['ref']}')),
      inheritContentStyle: true,
      baseRadius: 0,
      onActivate: (_, _) => onOpen(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
        decoration: BoxDecoration(
          color: selected ? t.colors.accent.withValues(alpha: .10) : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? t.colors.accent : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TradeChatAvatar('${row['name'] ?? ''}', row['online']),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${row['lastMessage'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.colors.textSecondary,
                    ),
                  ),
                  if (row['banHistory'] == true)
                    Text(
                      '⚠ ${chatText(context, '封禁记录 {n}', {'n': '${bans > 0 ? bans : 1}'})}',
                      style: TextStyle(
                        fontSize: 11,
                        color: MarketplacePalette.attention,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (row['lastTime'] != null) MarketPublished(row['lastTime']),
                if (unread > 0) ...[
                  const SizedBox(height: 3),
                  TradeChatCount(unread),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The red unread count used on the 交易消息 group and rows.
class TradeChatCount extends StatelessWidget {
  const TradeChatCount(this.count, {super.key});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MarketplacePalette.heart,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        fontFamily: context.tokens.typography.monoFamily,
        color: MarketplacePalette.onHeart,
      ),
    ),
  );
}

/// A message: SCM's order card when quoted, the risky-link warning, the time
/// and (for mine) read state.
class TradeChatBubble extends StatelessWidget {
  const TradeChatBubble(this.message, {super.key});
  final MarketRow message;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mine = message['mine'] == true;
    final quote = message['quote'];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mine
                    ? t.colors.accent.withValues(alpha: .16)
                    : t.surfaces.panel.fill,
                border: Border.all(
                  color: mine
                      ? t.colors.accent.withValues(alpha: .35)
                      : t.surfaces.panel.border,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: Radius.circular(mine ? 8 : 2),
                  bottomRight: Radius.circular(mine ? 2 : 8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ('${message['content'] ?? ''}'.isNotEmpty)
                    SelectableText(
                      '${message['content']}',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  if (quote is Map) ...[
                    const SizedBox(height: 6),
                    TradeChatOrderCard(quote.cast<String, Object?>()),
                  ],
                ],
              ),
            ),
            if (message['risky'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '⚠ ${chatText(context, '含外部链接，谨慎打开；SCM 不会通过链接收款。')}',
                  style: TextStyle(fontSize: 11, color: t.colors.danger),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  marketRecordTime(message['time']).split(' ').last,
                  if (mine)
                    chatText(context, message['read'] == true ? '已读' : '已送达'),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 10.5, color: t.colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SCM's order snapshot as a card (read only).
class TradeChatOrderCard extends StatelessWidget {
  const TradeChatOrderCard(this.quote, {super.key});
  final MarketRow quote;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (quote['type'] != 'order') {
      return Text(
        '[${chatText(context, '图片')}]',
        style: TextStyle(color: t.colors.textSecondary),
      );
    }
    final en = marketLocale(context) == 'en';
    final name =
        '${(en ? quote['itemNameEn'] : null) ?? quote['itemName'] ?? chatText(context, '订单')}';
    return Container(
      constraints: const BoxConstraints(minWidth: 260),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: t.surfaces.panel.fill,
        border: Border(
          left: const BorderSide(color: MarketplacePalette.gold, width: 3),
          top: BorderSide(color: t.surfaces.panel.border),
          right: BorderSide(color: t.surfaces.panel.border),
          bottom: BorderSide(color: t.surfaces.panel.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (quote['amount'] != null)
                MarketPrice(quote['amount'], size: 13),
              Text(
                [
                  if (quote['orderNo'] != null) '#${quote['orderNo']}',
                  if (quote['statusText'] != null) '${quote['statusText']}',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A message this client sent that is not yet confirmed, unconfirmed (never
/// resent automatically) or refused by SCM.
class TradeChatOutgoingBubble extends StatelessWidget {
  const TradeChatOutgoingBubble(
    this.message, {
    required this.refresh,
    required this.resend,
    required this.remove,
    super.key,
  });
  final MarketChatOutgoing message;
  final VoidCallback refresh, resend, remove;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, label) = switch (message.status) {
      'uncertain' => (
        MarketplacePalette.attention,
        chatText(context, '未确认：没有收到 SCM 回执，不会自动重发'),
      ),
      'rejected' => (
        t.colors.danger,
        chatText(context, '未发出：{reason}', {
          'reason':
              message.reason != null &&
                  !message.reason!.startsWith('marketplace.')
              ? message.reason!
              : chatText(context, 'SCM 未接受'),
        }),
      ),
      _ => (t.colors.textSecondary, chatText(context, '发送中…')),
    };
    Widget link(String text, VoidCallback onTap, String key) =>
        StarBridgeActionButton(
          controlKey: ValueKey(('trade-chat-outgoing', key, message.hashCode)),
          kind: StarBridgeActionKind.quiet,
          hoverFace: false,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minHeight: 20,
          onActivate: (_) => onTap(),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              decoration: TextDecoration.underline,
            ),
          ),
        );
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.colors.accent.withValues(alpha: .10),
              border: Border.all(color: color.withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message.content,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: color)),
              if (message.status == 'uncertain') ...[
                link(chatText(context, '刷新查看'), refresh, 'refresh'),
                link(chatText(context, '再发一次'), resend, 'resend'),
              ],
              if (message.status == 'rejected')
                link(chatText(context, '移除'), remove, 'remove'),
            ],
          ),
        ],
      ),
    );
  }
}

/// The composer: 150 characters (SCM's limit), Enter sends, Shift+Enter
/// breaks the line; an attached order shows above the box.
class TradeChatComposer extends StatefulWidget {
  const TradeChatComposer(
    this.c, {
    required this.enabled,
    this.recentOrders,
    super.key,
  });
  final MarketplaceChatController c;
  final bool enabled;
  final List<MarketChatAttachment> Function()? recentOrders;
  @override
  State<TradeChatComposer> createState() => _ComposerState();
}

class _ComposerState extends State<TradeChatComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  // SCM counts UTF-16 code units (an emoji is 2): over the limit the text
  // stays in the box with a hint instead of being cleared and dropped.
  bool get _tooLong =>
      _text.text.trim().length > MarketplaceChatController.maxLength;

  void _send() {
    final text = _text.text.trim();
    if (!widget.enabled || text.isEmpty || _tooLong) return;
    setState(_text.clear);
    widget.c.send(text);
  }

  Future<void> _pickOrder() async {
    final orders = widget.recentOrders?.call() ?? const [];
    if (orders.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset.zero);
    final picked = await showMenu<MarketChatAttachment>(
      context: context,
      position: RelativeRect.fromLTRB(
        at.dx + box.size.width - 320,
        at.dy - 8,
        at.dx + box.size.width,
        at.dy,
      ),
      items: [
        PopupMenuItem<MarketChatAttachment>(
          enabled: false,
          child: Text(chatText(context, '最近的交易单')),
        ),
        for (final order in orders.take(8))
          PopupMenuItem(
            value: order,
            child: Text(
              order.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
      ],
    );
    if (picked != null && mounted) setState(() => widget.c.attachment = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final attach = widget.c.attachment;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: t.surfaces.panel.fill,
        border: Border(top: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attach != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const Key('trade-chat-attachment'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
                decoration: BoxDecoration(
                  border: Border(
                    left: const BorderSide(
                      color: MarketplacePalette.gold,
                      width: 3,
                    ),
                    top: BorderSide(color: t.surfaces.panel.border),
                    right: BorderSide(color: t.surfaces.panel.border),
                    bottom: BorderSide(color: t.surfaces.panel.border),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chatText(context, '附上订单：{label}', {
                        'label': attach.label,
                      }),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    StarBridgeActionButton(
                      controlKey: const Key('trade-chat-attachment-remove'),
                      kind: StarBridgeActionKind.quiet,
                      hoverFace: false,
                      semanticLabel: chatText(context, '移除'),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minHeight: 22,
                      onActivate: (_) =>
                          setState(() => widget.c.attachment = null),
                      child: Text(
                        '✕',
                        style: TextStyle(color: t.colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) &&
                        !HardwareKeyboard.instance.isShiftPressed &&
                        !_text.value.composing.isValid) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    key: const Key('trade-chat-input'),
                    controller: _text,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: chatText(
                        context,
                        '输入消息，Enter 发送，Shift+Enter 换行',
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.recentOrders != null)
                    StarBridgeActionButton(
                      controlKey: const Key('trade-chat-attach'),
                      onActivate: widget.enabled ? (_) => _pickOrder() : null,
                      child: Text(chatText(context, '附上订单')),
                    ),
                  const SizedBox(height: 6),
                  StarBridgeActionButton(
                    controlKey: const Key('trade-chat-send'),
                    kind: StarBridgeActionKind.primary,
                    onActivate: widget.enabled && !_tooLong
                        ? (_) => _send()
                        : null,
                    child: Text(chatText(context, '发送')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  chatText(
                    context,
                    !widget.enabled
                        ? '无法发送：你们之间存在拉黑关系。'
                        : _tooLong
                        ? '最多 150 个字符（表情算 2 个），请删减后再发送。'
                        : '消息会同步到 SCM 网站；请勿在私信里交换账号密码。',
                  ),
                  key: const Key('trade-chat-hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _tooLong && widget.enabled
                        ? t.colors.danger
                        : t.colors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${_text.text.trim().length}/${MarketplaceChatController.maxLength}',
                key: const Key('trade-chat-count'),
                style: TextStyle(
                  fontSize: 11,
                  color: _tooLong ? t.colors.danger : t.colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
