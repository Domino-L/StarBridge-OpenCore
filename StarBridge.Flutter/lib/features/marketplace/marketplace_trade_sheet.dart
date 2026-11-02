import 'marketplace_trade_chat_entry.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/remote_image.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_controller.dart';
import 'marketplace_details.dart';
import 'marketplace_time.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_trades_controller.dart';
import 'marketplace_widgets.dart';
import 'marketplace_trade_status.dart';
import 'marketplace_trade_actions.dart';

Future<void> showTrade(
  BuildContext context,
  MarketplaceController c,
  MarketRow row,
) async {
  c.trades.detail = row;
  unawaited(c.trades.open(row['transactionNumber'] as String));
  await tradeMotionDialog<void>(
    context,
    (ctx) => Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.only(top: 64),
      shape: RoundedRectangleBorder(),
      child: SizedBox(
        width: MediaQuery.sizeOf(ctx).width < 980
            ? MediaQuery.sizeOf(ctx).width
            : 420,
        child: TradeSheet(c),
      ),
    ),
    barrierDismissible: true,
  );
}

class TradeSheet extends StatelessWidget {
  const TradeSheet(this.c, {super.key});
  final MarketplaceController c;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c.trades,
    builder: (context, _) {
      final t = c.trades, r = t.detail;
      if (r == null) return SizedBox.shrink();
      final action = tradeAction(r), cancelled = r['deliveryStatus'] == 4;
      final steps = cancelled
          ? [tradeText(context, '发起'), tradeText(context, '已取消')]
          : [
              tradeText(context, '发起'),
              if (r['creatorType'] == 0) tradeText(context, '待同意'),
              tradeText(context, '待发货'),
              tradeText(context, '已发货'),
              tradeText(context, '已收货'),
              tradeText(context, '评价'),
            ];
      final current = cancelled
          ? 1
          : r['deliveryStatus'] == 0
          ? 1
          : r['deliveryStatus'] == 1
          ? steps.indexOf(tradeText(context, '待发货'))
          : r['deliveryStatus'] == 2
          ? steps.indexOf(tradeText(context, '已发货'))
          : r['${r['actorRole']}CommentId'] != null
          ? steps.length
          : steps.indexOf(tradeText(context, '评价'));
      Widget info(String label, Object? value, {bool time = false}) =>
          value == null || time && scmInstant(value) == null
          ? SizedBox.shrink()
          : Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: time
                          ? DefaultTextStyle.merge(
                              style: TextStyle(
                                fontFamily:
                                    context.tokens.typography.monoFamily,
                                fontSize: 12.5,
                              ),
                              child: TradeTimestamp(value),
                            )
                          : Text(
                              value.toString(),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
      return Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  tradeText(context, '交易单'),
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Spacer(),
                if (r['transactionNumber'] is String) ...[
                  Flexible(
                    child: Text(
                      r['transactionNumber'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: context.tokens.typography.monoFamily,
                        fontSize: 11,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                ],
                TradeStatusPill(r),
                StarBridgeNativeIconAction(
                  controlKey: const Key('market-trade-sheet-close'),
                  label: tradeText(context, '关闭'),
                  onActivate: t.pending
                      ? null
                      : (source) => dismissStarBridgeDialog<void>(
                          context,
                          source: source,
                        ),
                  consumeHintEscape: false,
                  icon: MarketplaceIcon(MarketplaceGlyph.close, size: 18),
                ),
              ],
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  Semantics(
                    label: tradeText(context, 'accessibleStep', {
                      'step': '${(current + 1).clamp(1, steps.length)}',
                      'total': '${steps.length}',
                      'status': steps[current.clamp(0, steps.length - 1)],
                    }),
                    excludeSemantics: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          if (i > 0)
                            Expanded(
                              child: Container(
                                height: 1.5,
                                margin: EdgeInsets.only(top: 11),
                                color: i <= current
                                    ? context.tokens.colors.accent.withValues(
                                        alpha: .6,
                                      )
                                    : context.tokens.surfaces.panel.border,
                              ),
                            ),
                          _StepNode(
                            label: steps[i],
                            index: i,
                            done: i < current,
                            current: i == current,
                            cancelled: cancelled && i == current,
                            mine: action != null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 18),
                  TradeDeadline(r),
                  SizedBox(height: 16),
                  MarketSurface(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 56,
                          child: MarketArt.of(r),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tradeItemName(context, r),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  TradeRole(r),
                                  Text(
                                    '×${r['number'] ?? ''}',
                                    style: TextStyle(
                                      fontFamily:
                                          context.tokens.typography.monoFamily,
                                      fontSize: 12,
                                    ),
                                  ),
                                  MarketQualityBadge(r, prefixed: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MarketPrice(tradeItemsTotal(r)),
                            if (marketNumber(r['amount']) != null &&
                                r['displayType'] != 3 &&
                                r['orderType'] != 2)
                              Text(
                                '${tradeText(context, '单价')} ${marketMoney(r['amount'])}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: context.tokens.colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  MarketSurface(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.tokens.surfaces.raised.fill,
                            border: Border.all(
                              color: context.tokens.surfaces.panel.border,
                            ),
                          ),
                          // The initials, covered by the Host-validated RSI
                          // avatar; redirects are not followed, so the vetted
                          // address cannot lead elsewhere (CX-T21).
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                _initials(r['counterpartyName'] as String?),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.tokens.colors.textSecondary,
                                ),
                              ),
                              if (r['counterpartyAvatar'] case final String a
                                  when a.startsWith('https://'))
                                ClipOval(
                                  child: RemoteImage(
                                    a,
                                    key: const ValueKey(
                                      'market-trade-counterparty-avatar',
                                    ),
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.cover,
                                    cacheWidth: 72,
                                    kind: RemoteImageResourceKind.avatar,
                                    followRedirects: false,
                                    excludeFromSemantics: true,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['actorRole'] == 'seller'
                                    ? tradeText(context, '买家')
                                    : tradeText(context, '卖家'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.tokens.colors.textSecondary,
                                ),
                              ),
                              Text(
                                '${r['counterpartyName'] ?? tradeText(context, '资料待更新')}',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if ([
                                0,
                                1,
                                2,
                                3,
                                4,
                              ].contains(r['counterpartyStatus']))
                                Text(
                                  {
                                    1: tradeText(context, '在线'),
                                    2: tradeText(context, '游戏中'),
                                    0: tradeText(context, '离线'),
                                    3: tradeText(context, '离线'),
                                    4: tradeText(context, '离线'),
                                  }[r['counterpartyStatus']]!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: context.tokens.colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Semantics(container: true, child: StarBridgeMenuAnchor(
                          semanticLabel: tradeText(context, '更多'),
                          consumeOutsideTaps: true,
                          enabled: !t.pending,
                          entries: [
                            StarBridgeMenuEntry(
                              id: 'market-trade-block',
                              controlKey: const Key('market-trade-sheet-block'),
                              label: tradeText(context, '拉黑'),
                              onActivate: t.pending ? null : (source) => unawaited(
                                runStarBridgeActivation<void>(source,
                                  () => tradeDialog(context, c, 'block', r)),
                              ),
                              child: SizedBox(
                                width: 88,
                                height: 48,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(tradeText(context, '拉黑'),
                                    style: Theme.of(context).textTheme.labelLarge),
                                ),
                              ),
                            ),
                          ],
                          builder: (context, controller, focus, toggle) =>
                              StarBridgeNativeIconAction(
                                key: const Key('market-trade-sheet-more'),
                                label: tradeText(context, '更多'),
                                focusNode: focus,
                                onActivate: t.pending ? null : toggle,
                                icon: MarketplaceIcon(MarketplaceGlyph.more),
                              ),
                        )),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  info(
                    tradeText(context, '交易地点'),
                    r['transactionLocationName'] ?? r['locationName'],
                  ),
                  info(
                    tradeText(context, '交付方式'),
                    {
                      0: tradeText(context, '面交'),
                      1: tradeText(context, '代运'),
                      2: tradeText(context, '自提'),
                      3: tradeText(context, '其他'),
                    }[r['deliveryMethod']],
                  ),
                  if ((marketNumber(r['shippingFee']) ?? 0) > 0)
                    info(tradeText(context, '运费'), r['shippingFee']),
                  SizedBox(height: 12),
                  Text(
                    tradeText(context, '进度记录'),
                    style: TextStyle(fontSize: 12),
                  ),
                  info(tradeText(context, '发起'), r['createTime'], time: true),
                  info(tradeText(context, '同意'), r['approvalTime'], time: true),
                  info(tradeText(context, '发货'), r['shippedTime'], time: true),
                  info(
                    tradeText(context, '收货'),
                    r['completionTime'],
                    time: true,
                  ),
                  info(
                    tradeText(context, '取消'),
                    r['cancellationTime'],
                    time: true,
                  ),
                  info(tradeText(context, '取消原因'), r['cancellationReason']),
                  if (r['deliveryProof'] is String &&
                      (r['deliveryProof'] as String).trim().isNotEmpty) ...[
                    Text(tradeText(context, '发货凭证')),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final url
                            in (r['deliveryProof'] as String)
                                .split(',')
                                .take(6))
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: MarketArt(url.trim()),
                          ),
                      ],
                    ),
                  ],
                  for (final role in ['buyer', 'seller'])
                    if (r['${role}Rating'] != null)
                      Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: MarketSurface(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            '${role == 'buyer' ? tradeText(context, '买家') : tradeText(context, '卖家')}${tradeText(context, '评价')}  ${'★' * (r['${role}Rating'] as int)}\n${r['${role}Content'] ?? ''}',
                          ),
                        ),
                      ),
                  if (t.error != null)
                    TradeFailure(
                      c,
                      retry: () => t.open(r['transactionNumber'] as String),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                if (tradeCanCancel(r))
                  marketButtonAction(TextButton(
                    onPressed: t.pending
                        ? null
                        : () => tradeDialog(context, c, 'cancel', r),
                    child: Text(tradeText(context, '取消交易')),
                  ), key: const Key('market-trade-sheet-cancel')),
                if (r['canReport'] == true)
                  marketButtonAction(TextButton(
                    onPressed: t.pending
                        ? null
                        : () => tradeDialog(context, c, 'report', r),
                    child: Text(tradeText(context, '举报')),
                  ), key: const Key('market-trade-sheet-report')),
                // 0.7.2 G9: the trade's conversation, this order attached.
                if (c.tradeChat != null && r['counterpartyChat'] is String)
                  marketButtonAction(TextButton(
                    onPressed: () => messageTradeCounterparty(context, c, r),
                    child: Text(tradeChatEntryText(context, '私信对方')),
                  ), key: const Key('market-trade-sheet-message')),
                Spacer(),
                if (action != null)
                  marketButtonAction(FilledButton(
                    style: tradePrimaryStyle(context),
                    onPressed: t.pending
                        ? null
                        : () => tradeDialog(context, c, action, r),
                    child: Text(tradeText(context, tradeLabels[action]!)),
                  ), key: const Key('market-trade-sheet-main')),
              ],
            ),
          ],
        ),
      );
    },
  );
}

String _initials(String? name) {
  final letters = (name ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (letters.isEmpty) {
    return name == null || name.isEmpty ? '?' : name.characters.first;
  }
  return letters.length == 1
      ? letters.toUpperCase()
      : '${letters[0]}${letters[letters.length - 1]}'.toUpperCase();
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.label,
    required this.index,
    required this.done,
    required this.current,
    required this.cancelled,
    required this.mine,
  });
  final String label;
  final int index;
  final bool done, current, cancelled, mine;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = cancelled
        ? t.colors.danger
        : current && mine
        ? MarketplacePalette.attention
        : done || current
        ? t.colors.accent
        : t.surfaces.panel.border;
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? t.colors.accent
                  : cancelled
                  ? t.colors.danger
                  : Colors.transparent,
              border: Border.all(color: ring, width: 1.5),
            ),
            child: done
                ? MarketplaceIcon(MarketplaceGlyph.check, size: 13, color: t.colors.onAccent)
                : Text(
                    cancelled ? '×' : '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: t.typography.monoFamily,
                      color: cancelled
                          ? t.colors.onAccent
                          : current
                          ? ring
                          : t.colors.textSecondary,
                    ),
                  ),
          ),
          SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
              color: current || done
                  ? t.colors.textPrimary
                  : t.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
