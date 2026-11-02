import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_time.dart';
import 'marketplace_port.dart';
import 'marketplace_trades_controller.dart';

const tradeLabels = {
  'approve': '同意交易',
  'ship': '发货',
  'receive': '确认收货',
  'cancel': '取消交易',
  'review': '评价交易',
  'report': '举报交易',
  'create': '确认交易',
  'block': '拉黑对方',
};
String tradeStatus(MarketRow r) => tradeAction(r) != null
    ? {
        'approve': '待我同意',
        'ship': '待我发货',
        'receive': '待我收货',
        'review': '待我评价',
      }[tradeAction(r)]!
    : {
            0: '等待收购方同意',
            1: '等待卖家发货',
            2: '等待买家收货',
            3: '已完成',
            4: '已取消',
          }[r['deliveryStatus']] ??
          '状态待确认';

class TradeRole extends StatelessWidget {
  const TradeRole(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final buyer = row['actorRole'] == 'buyer';
    final color = buyer
        ? MarketplacePalette.buyer
        : context.tokens.colors.accent;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        buyer ? tradeText(context, '我买') : tradeText(context, '我卖'),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

String _deadlineSemantics(
  BuildContext context,
  MarketRow row,
  ScmReceiptCountdown countdown,
) {
  final status = tradeText(context, tradeStatus(row));
  if (countdown.expired) {
    return '$status, ${tradeText(context, '已超时，等待 SCM 处理')}';
  }
  final duration = countdown.remaining;
  if (duration == null) return status;
  return tradeText(context, 'accessibleRemaining', {
    'status': status,
    'hours': '${duration.inHours}',
    'minutes': '${duration.inMinutes.remainder(60)}',
  });
}

class TradeDeadline extends StatefulWidget {
  const TradeDeadline(this.row, {this.compact = false, super.key});
  final MarketRow row;
  final bool compact;
  @override
  State<TradeDeadline> createState() => _DeadlineState();
}

class _DeadlineState extends State<TradeDeadline> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row, state = r['deliveryStatus'];
    // Only receiptDeadline is currently an SCM contract. No derived shipment deadline.
    final countdown = ScmReceiptCountdown(
      state == 2 ? r['receiptDeadline'] : null,
      DateTime.now(),
    );
    final remaining = countdown.expired
        ? tradeText(context, '已超时，等待 SCM 处理')
        : countdown.text;
    final deadlineText = remaining == null
        ? null
        : countdown.expired
        ? remaining
        : r['actorRole'] == 'buyer'
        ? tradeText(context, 'receiptDue', {'time': remaining})
        : tradeText(context, 'receiptCutoff', {'time': remaining});
    if (widget.compact) {
      if (remaining == null) {
        return TradeTimestamp(
          state == 4
              ? r['cancellationTime']
              : state == 3
              ? r['completionTime']
              : r['createTime'],
        );
      }
      return Text(
        semanticsLabel: _deadlineSemantics(context, r, countdown),
        countdown.expired
            ? remaining
            : tradeText(context, 'remaining', {'time': remaining}),
        style: TextStyle(
          fontSize: 11.5,
          color: countdown.warning
              ? MarketplacePalette.warning
              : context.tokens.colors.textSecondary,
        ),
      );
    }
    final text = state == 1
        ? tradeText(context, '卖家 48 小时内没发货，SCM 会自动取消。')
        : state == 2
        ? tradeText(context, '收货期限为发货后 48 小时，超时由 SCM 自动取消；已发货不能取消。')
        : state == 0
        ? tradeText(context, '收购方同意后进入待发货。')
        : state == 4
        ? '${tradeText(context, '已取消')}${scmLocalTime(r['cancellationTime']) == null ? '' : ' · ${scmLocalTime(r['cancellationTime'])}'}'
        : tradeText(context, '交易已完成，双方各可评价一次。');
    final tone = state == 4
        ? context.tokens.colors.textSecondary
        : state == 2
        ? (countdown.warning
              ? MarketplacePalette.warning
              : context.tokens.colors.accent)
        : tradeAction(r) != null
        ? MarketplacePalette.warning
        : context.tokens.colors.accent;
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .12),
        border: Border.all(color: tone.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarketplaceIcon(MarketplaceGlyph.schedule, size: 17, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  semanticsLabel: _deadlineSemantics(context, r, countdown),
                  TextSpan(
                    children: [
                      if (remaining != null &&
                          !countdown.expired &&
                          deadlineText != null) ...[
                        TextSpan(text: deadlineText.split(remaining).first),
                        TextSpan(
                          text: remaining,
                          style: TextStyle(
                            color: countdown.warning
                                ? tone
                                : context.tokens.colors.textPrimary,
                          ),
                        ),
                        TextSpan(text: deadlineText.split(remaining).last),
                      ] else
                        TextSpan(
                          text:
                              deadlineText ??
                              tradeText(context, tradeStatus(r)),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
                if (state == 2 && remaining == null)
                  Text(
                    tradeText(context, '服务器尚未提供截止时间'),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TradeStatusPill extends StatelessWidget {
  const TradeStatusPill(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final color = row['deliveryStatus'] == 4
        ? context.tokens.colors.textSecondary
        : tradeAction(row) != null
        ? MarketplacePalette.warning
        : row['deliveryStatus'] == 3
        ? MarketplacePalette.success
        : context.tokens.colors.accent;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tradeText(context, tradeStatus(row)),
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

class TradeTimestamp extends StatelessWidget {
  const TradeTimestamp(this.value, {super.key});
  final Object? value;
  @override
  Widget build(BuildContext context) {
    final full = scmLocalTime(value);
    if (full == null) return const SizedBox.shrink();
    return Tooltip(
      message: full,
      child: Text(
        scmRelativeTime(
          value,
          now: DateTime.now(),
          today: tradeText(context, '今天'),
          yesterday: tradeText(context, '昨天'),
        )!,
        style: TextStyle(
          fontSize: 11.5,
          color: context.tokens.colors.textSecondary,
        ),
      ),
    );
  }
}
