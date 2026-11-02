import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'marketplace_states.dart' show marketButtonAction;

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_controller.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_port.dart';
import 'marketplace_trades_controller.dart';
import 'marketplace_trade_status.dart';
import 'marketplace_trade_sheet.dart';

Future<void> tradeDialog(
  BuildContext context,
  MarketplaceController c,
  String action,
  MarketRow row,
) => tradeMotionDialog<void>(context, (_) => _TradeDialog(c, action, row));

class _TradeDialog extends StatefulWidget {
  const _TradeDialog(this.c, this.action, this.row);
  final MarketplaceController c;
  final String action;
  final MarketRow row;
  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  final text = TextEditingController();
  late final contextRevision = widget.c.contextRevision;
  bool received = false;
  int rating = 5;
  int? reportType;
  bool attempted = false, submitted = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.c.trades, action = widget.action, r = widget.row;
    final danger = const ['cancel', 'report', 'block'].contains(action);
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => PopScope(
        canPop: !t.pending,
        child: Dialog(
          backgroundColor: context.tokens.surfaces.floating.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tradeText(context, tradeLabels[action]!),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        StarBridgeNativeIconAction(
                          key: const Key('market-trade-action-close'),
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          label: tradeText(context, '关闭'),
                          onActivate: t.pending
                              ? null
                              : (source) => dismissStarBridgeDialog<void>(context, source: source),
                          icon: const MarketplaceIcon(
                            MarketplaceGlyph.close,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    TradeMiniCard({...r, 'amount': tradeItemsTotal(r)}),
                    SizedBox(height: 12),
                    TradeNoticeBox(
                      switch (action) {
                        'ship' => tradeText(context, '先在游戏里交给买家再点发货。发货后不能取消。'),
                        'receive' => tradeText(context, '请先在游戏里核对物品，再确认收货。'),
                        'cancel' =>
                          r['actorRole'] == 'buyer' && r['deliveryStatus'] == 1
                              ? tradeText(context, '取消可能影响你的信誉。请先和对方确认。')
                              : tradeText(context, '取消后交易结束，库存由 SCM 退回。'),
                        'review' => tradeText(context, '评价提交后不能修改，会计入对方信誉。'),
                        'approve' => tradeText(context, '同意后进入待发货，请与卖家确认交付安排。'),
                        'block' => tradeText(
                          context,
                          '确认将此交易的对方加入 SCM 黑名单？现有交易仍需按当前状态处理。',
                        ),
                        _ => tradeText(context, 'reportHint'),
                      },
                      warning: action == 'receive',
                      danger: false,
                    ),
                    if (action == 'receive' || action == 'ship')
                      StarBridgeCheckboxTile(
                        controlKey: const Key('market-trade-action-received'),
                        autofocus: true,
                        dense: false,
                        checkboxScale: .9,
                        compactTarget: true,
                        contentPadding: EdgeInsets.zero,
                        value: received,
                        onChanged: t.pending
                            ? null
                            : (v) => setState(() => received = v),
                        label: action == 'ship'
                            ? tradeText(context, '我已在游戏里交给买家')
                            : tradeText(context, '我已在游戏里收到'),
                        titleWidget: Text(
                          action == 'ship'
                              ? tradeText(context, '我已在游戏里交给买家')
                              : tradeText(context, '我已在游戏里收到'),
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    if (action == 'review') ...[
                      const SizedBox(height: 14),
                      _FieldLabel(tradeText(context, 'rvScore')),
                      Row(
                        children: [
                          for (var i = 1; i <= 5; i++)
                            StarBridgeNativeIconAction(
                              controlKey: ValueKey(('market-trade-rating', i)),
                              // Original 30×30 InkResponse target, not the
                              // padded 48 px IconButton default.
                              style: const ButtonStyle(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              label: '$i',
                              selected: i <= rating,
                              autofocus: i == 1,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: const EdgeInsets.all(3),
                              onActivate: t.pending
                                  ? null
                                  : (_) => setState(() => rating = i),
                              icon: MarketplaceIcon(
                                i <= rating
                                    ? MarketplaceGlyph.rating
                                    : MarketplaceGlyph.ratingEmpty,
                                size: 24,
                                color: MarketplacePalette.attention,
                              ),
                            ),
                          const SizedBox(width: 10),
                          Text(
                            tradeText(context, 'rv$rating'),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.tokens.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (action == 'report') ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 1; i <= 4; i++)
                            StarBridgeChoiceChip(
                              controlKey: ValueKey(('market-trade-report', i)),
                              label: tradeText(
                                context,
                                ['欺诈行为', '辱骂骚扰', '虚假交易', 'RMT（现实金钱交易）'][i - 1],
                              ),
                              autofocus: i == 1,
                              selected: reportType == i,
                              showCheckmark: false,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              side: BorderSide(
                                color: attempted && reportType == null
                                    ? Theme.of(context).colorScheme.error
                                    : context.tokens.colors.textSecondary
                                          .withValues(alpha: .3),
                              ),
                              onSelected: t.pending
                                  ? null
                                  : (selected) => setState(
                                      () => reportType = selected ? i : null,
                                    ),
                            ),
                        ],
                      ),
                      if (attempted && reportType == null)
                        Text(
                          tradeText(context, 'reportTypeRequired'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (['review', 'report'].contains(action))
                      _FieldLabel(
                        action == 'review'
                            ? tradeText(context, '评价内容')
                            : tradeText(context, 'rpText'),
                      ),
                    if (['review', 'report'].contains(action))
                      TextField(
                        controller: text,
                        enabled: !t.pending,
                        maxLength: action == 'review' ? 100 : 200,
                        maxLines: 3,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: context.tokens.surfaces.ground.fill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          errorText:
                              action == 'report' &&
                                  attempted &&
                                  text.text.trim().isEmpty
                              ? tradeText(context, 'reportTextRequired')
                              : null,
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: BorderSide(
                              color: context.tokens.surfaces.panel.border,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    if (submitted && t.writeError != null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: TradeFailure(
                          widget.c,
                          writing: true,
                          retry: () async {
                            if (!t.writeUncertain) return;
                            final source = StarBridgeActivationOrigin.sourceOf(context);
                            final route = ModalRoute.of(context);
                            if (await t.inspectUncertainWrite(
                                  r['transactionNumber'] as String?,
                                ) &&
                                context.mounted && route?.isCurrent == true) {
                              dismissStarBridgeDialog<void>(context, source: source);
                            }
                          },
                        ),
                      ),
                    if (['receive', 'ship'].contains(action) && !received)
                      Text(
                        tradeText(
                          context,
                          action == 'ship' ? '请先勾选已交付' : '请先勾选已收到',
                        ),
                      ),
                    SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        marketButtonAction(OutlinedButton(
                          autofocus: ![
                            'receive',
                            'ship',
                            'review',
                            'report',
                          ].contains(action),
                          style: tradeCancelStyle(),
                          onPressed: t.pending
                              ? null
                              : () => dismissStarBridgeDialog<void>(context,
                                  source: StarBridgeActivationOrigin.sourceOf(context)),
                          child: Text(tradeText(context, '取消')),
                        ), key: const Key('market-trade-action-cancel')),
                        SizedBox(width: 8),
                        if (!t.writeUncertain)
                          marketButtonAction(FilledButton(
                            style: tradePrimaryStyle(
                              context,
                              danger: danger,
                            ),
                            onPressed:
                                t.pending ||
                                    t.writeUncertain ||
                                    contextRevision !=
                                        widget.c.contextRevision ||
                                    ['receive', 'ship'].contains(action) &&
                                        !received
                                ? null
                                : () async {
                                    setState(() => attempted = true);
                                    if (action == 'report' &&
                                        (reportType == null ||
                                            text.text.trim().isEmpty)) {
                                      return;
                                    }
                                    setState(() => submitted = true);
                                    final source = StarBridgeActivationOrigin.sourceOf(context);
                                    final hostContext = Navigator.of(context)
                                        .overlay!
                                        .context;
                                    final pageContext = widget.c;
                                    final result = await t.submit(action, {
                                      'transactionNumber':
                                          r['transactionNumber'],
                                      'rating': rating,
                                      'reportType': reportType,
                                      'content': text.text.trim(),
                                    });
                                    if (!context.mounted || result == null) {
                                      return;
                                    }
                                    showTradeSuccess(
                                      hostContext,
                                      message: tradeText(context, 'confirmed', {
                                        'action': tradeText(
                                          context,
                                          tradeLabels[action]!,
                                        ),
                                      }),
                                      open: () => showTrade(
                                        hostContext,
                                        pageContext,
                                        {'transactionNumber': result},
                                      ),
                                    );
                                    dismissStarBridgeDialog<void>(context, source: source);
                                  },
                            child: Text(
                              t.pending
                                  ? tradeText(context, '正在提交…')
                                  : !submitted || t.writeError == null
                                  ? tradeText(
                                      context,
                                      {
                                            'ship': '确认发货',
                                            'review': '提交评价',
                                            'report': '提交举报',
                                          }[action] ??
                                          tradeLabels[action]!,
                                    )
                                  : tradeText(context, '重试'),
                            ),
                          ), key: const Key('market-trade-action-submit'), danger: danger),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: context.tokens.colors.textSecondary,
      ),
    ),
  );
}
