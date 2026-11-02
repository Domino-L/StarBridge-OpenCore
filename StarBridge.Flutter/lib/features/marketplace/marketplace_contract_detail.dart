import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_contracts_controller.dart';
import 'marketplace_contracts_copy.dart';
import 'marketplace_copy.dart';
import 'marketplace_contract_dialogs.dart';
import 'marketplace_contracts_page.dart';
import 'marketplace_controller.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_records_page.dart' show marketRecordTime;
import 'marketplace_surfaces.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// The contract in the right-side panel (approved preview, 合约详情): progress,
/// reward and slots, description, milestones, participants and the publisher;
/// the footer offers what this member may do now. Every action goes once and
/// the panel then shows SCM's state.
Future<void> showContractDetail(
  BuildContext context,
  MarketplaceController market,
  MarketplaceContractsController contracts,
) => tradeMotionDialog<void>(
  context,
  (dialog) => Dialog(
    alignment: Alignment.centerRight,
    insetPadding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(),
    elevation: 0,
    backgroundColor: dialog.tokens.surfaces.panel.fill,
    surfaceTintColor: Colors.transparent,
    child: SizedBox(
      height: MediaQuery.sizeOf(dialog).height,
      width: MediaQuery.sizeOf(dialog).width < 980
          ? MediaQuery.sizeOf(dialog).width
          : 480,
      child: _Detail(market, contracts),
    ),
  ),
  barrierDismissible: true,
);

class _Detail extends StatelessWidget {
  const _Detail(this.market, this.c);
  final MarketplaceController market;
  final MarketplaceContractsController c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final t = context.tokens;
      final data = c.detail;
      final contract = data?['contract'] is Map
          ? (data!['contract'] as Map).cast<String, Object?>()
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    contractText(context, '合约详情'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                marketButtonAction(
                  key: const Key('market-contract-close'),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: MarketplaceIcon(
                      MarketplaceGlyph.close,
                      size: 18,
                      color: t.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.detailLoading && contract == null)
            const LinearProgressIndicator(minHeight: 2),
          if (c.detailFailed && contract == null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: marketTextAction(
                key: const Key('market-contract-retry'),
                onPressed: () => c.open(c.openId!),
                child: Text(contractText(context, '暂时读不到合约，点此重试。')),
              ),
            ),
          if (contract != null) ...[
            Expanded(child: _body(context, contract, data!)),
            _footer(context, contract, data),
          ],
        ],
      );
    },
  );

  Widget _body(BuildContext context, MarketRow contract, MarketRow data) {
    final t = context.tokens;
    final status = (contract['status'] as num?)?.toInt() ?? 1;
    final milestones = [
      for (final m in data['milestones'] as List? ?? const [])
        if (m is Map) m.cast<String, Object?>(),
    ];
    final people = data['participants'] is Map
        ? (data['participants'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final rows = [
      for (final p in people['rows'] as List? ?? const [])
        if (p is Map) p.cast<String, Object?>(),
    ];
    Widget section(String title, Widget child, {String? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarketHeading(
            contractText(context, title),
            titleSize: 13.5,
            trailing: trailing == null
                ? null
                : Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.colors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Row(
          children: [
            MarketSlantTag(
              contractTypeLabel(context, contract['type']),
              color: contractTypeColor(context, contract['type']),
            ),
            const SizedBox(width: 8),
            Text(
              '${contract['number'] ?? ''}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: t.typography.monoFamily,
                color: t.colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          '${contract['title'] ?? ''}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _Steps(status),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: t.surfaces.panel.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (label, value)) in [
                  ('报酬', ContractReward(contract, size: 14) as Widget),
                  (
                    '名额',
                    Text(
                      '${contract['taken'] ?? 0} / ${contract['slots'] ?? '—'}',
                      style: _mono(context),
                    ),
                  ),
                  (
                    '信誉门槛',
                    Text(
                      '≥ ${contract['minReputation'] ?? 0}',
                      style: _mono(context),
                    ),
                  ),
                  (
                    '截止',
                    Text(
                      contractRemaining(context, contract['expireTime']),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ].indexed)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : Border(
                                left: BorderSide(
                                  color: t.surfaces.panel.border,
                                ),
                              ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contractText(context, label),
                            style: TextStyle(
                              fontSize: 11,
                              color: t.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          value,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        section(
          '说明',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                '${contract['description'] ?? '—'}',
                style: const TextStyle(fontSize: 13, height: 1.65),
              ),
              if (contract['requirements'] != null ||
                  contract['location'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (contract['requirements'] != null)
                      '${contractText(context, '其他要求：')}${contract['requirements']}',
                    if (contract['location'] != null)
                      '${contractText(context, '地点：')}${contract['location']}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.colors.textSecondary,
                  ),
                ),
              ],
              if (contract['eligible'] == false &&
                  contract['mine'] != true) ...[
                const SizedBox(height: 6),
                Text(
                  contractText(context, '你的信誉未达到门槛'),
                  style: TextStyle(
                    fontSize: 12,
                    color: MarketplacePalette.attention,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (milestones.isNotEmpty)
          section(
            '里程碑',
            Column(
              children: [
                for (final m in milestones)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: t.surfaces.panel.border),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Check(((m['status'] as num?)?.toInt() ?? 0) >= 1),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m['title'] ?? ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (m['completeTime'] != null)
                                Text(
                                  marketRecordTime(
                                    m['completeTime'],
                                    date: true,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: t.colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        section(
          '参与者',
          rows.isEmpty
              ? Text(
                  contractText(context, '还没有人报名。'),
                  style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
                )
              : Column(
                  children: [
                    for (final p in rows) _participant(context, contract, p),
                  ],
                ),
          trailing: '${contract['taken'] ?? 0} / ${contract['slots'] ?? '—'}',
        ),
        section(
          '发布者',
          Row(
            children: [
              ContractPerson(
                '${contract['creator'] ?? ''}',
                online: contract['creatorOnline'],
                reputation: contract['creatorReputation'],
              ),
              if (contract['fleet'] == true &&
                  contract['fleetName'] != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    contractText(context, '舰队合约 · {name}', {
                      'name': '${contract['fleetName']}',
                    }),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.colors.textSecondary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (contract['mine'] != true &&
                  contract['creatorChat'] is String &&
                  market.tradeChat != null)
                marketButtonAction(
                  key: const Key('market-contract-message'),
                  TextButton(
                    onPressed: () =>
                        _message(context, '${contract['creatorChat']}'),
                    child: Text(contractText(context, '私信')),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _participant(BuildContext context, MarketRow contract, MarketRow p) {
    final t = context.tokens;
    final completed = (contract['status'] as num?)?.toInt() == 3;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContractPerson(
                  '${p['name'] ?? ''}',
                  reputation: p['reputation'],
                ),
                if ('${p['message'] ?? ''}'.isNotEmpty ||
                    (p['ships'] as List?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if ('${p['message'] ?? ''}'.isNotEmpty)
                          '“${p['message']}”',
                        if ((p['ships'] as List?)?.isNotEmpty == true)
                          (p['ships'] as List).join(
                            marketLocale(context) == 'en' ? ', ' : '、',
                          ),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _participantStatus(context, p['status']),
            style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
          ),
          if (contract['mine'] == true &&
              completed &&
              p['reviewedByCreator'] != true) ...[
            const SizedBox(width: 6),
            marketButtonAction(
              key: ValueKey(('market-contract-review', '${p['id']}')),
              TextButton(
                onPressed: () => _review(context, (p['id'] as num).toInt()),
                child: Text(contractText(context, '去评价')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, MarketRow contract, MarketRow data) {
    final t = context.tokens;
    final status = (contract['status'] as num?)?.toInt() ?? 1;
    final mine = contract['mine'] == true;
    final me = data['me'] is Map
        ? (data['me'] as Map).cast<String, Object?>()
        : null;
    final myState = (me?['status'] as num?)?.toInt();
    final joined =
        me != null && myState != null && myState != 2 && myState != 6;
    final busy = c.acting != null;
    final actions = <(String, String, bool, Future<void> Function())>[
      if (!mine && status == 1 && !joined)
        ('apply', '报名（可附留言）', true, () => _apply(context)),
      if (!mine && joined && (myState == 0 || myState == 1) && status <= 2)
        ('quit', '退出', false, () => _act(context, 'quit')),
      if (mine && status == 1) ...[
        ('cancel', '取消合约', false, () => _reason(context, 'cancel')),
        ('start', '开始合约', true, () => _act(context, 'start')),
      ],
      if (mine && status == 2)
        ('complete', '完成合约', true, () => _act(context, 'complete')),
      if (!mine && joined && status == 3 && me['reviewedByParticipant'] != true)
        (
          'review',
          '去评价',
          true,
          () => _review(context, (me['id'] as num).toInt()),
        ),
      if ((mine || joined) && (status == 2 || status == 3))
        ('dispute', '发起争议', false, () => _reason(context, 'dispute')),
    ];
    if (actions.isEmpty) return const SizedBox(height: 12);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (key, label, primary, run) in actions)
            primary
                ? marketButtonAction(
                    key: ValueKey(('market-contract-action', key)),
                    FilledButton(
                      style: tradePrimaryStyle(context),
                      onPressed: busy ? null : run,
                      child: Text(contractText(context, label)),
                    ),
                  )
                : marketButtonAction(
                    key: ValueKey(('market-contract-action', key)),
                    OutlinedButton(
                      style: tradeCancelStyle(),
                      onPressed: busy ? null : run,
                      child: Text(contractText(context, label)),
                    ),
                  ),
        ],
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    String operation, [
    MarketRow input = const {},
  ]) async {
    final ok = await c.act(operation, input);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showOnly(
      starBridgeTimedSnackBar(
        content: Text(
          contractText(
            context,
            ok ? '操作已完成。' : 'SCM 未接受这个操作，详情已按 SCM 的最新状态刷新。',
          ),
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context) async {
    final text = await _ask(
      context,
      contractText(context, '报名（可附留言）'),
      contractText(context, '留言（可选，最多 1000 字）'),
      required: false,
    );
    if (text == null || !context.mounted) return;
    await _act(context, 'apply', {
      if (text.trim().isNotEmpty) 'message': text.trim(),
    });
  }

  Future<void> _reason(BuildContext context, String operation) async {
    final text = await _ask(
      context,
      contractText(context, operation == 'cancel' ? '取消合约' : '发起争议'),
      contractText(context, '原因（必填）'),
      required: true,
    );
    if (text == null || !context.mounted) return;
    await _act(context, operation, {'reason': text.trim()});
  }

  Future<void> _review(BuildContext context, int participantId) async {
    final result = await tradeMotionDialog<(int, String)>(
      context,
      (dialog) => const ContractReviewDialog(),
    );
    if (result == null || !context.mounted) return;
    final (rating, text) = result;
    await _act(context, 'review', {
      'participantId': participantId,
      'rating': rating,
      if (text.isNotEmpty) 'comment': text,
    });
  }

  Future<String?> _ask(
    BuildContext context,
    String title,
    String hint, {
    required bool required,
  }) => tradeMotionDialog<String>(
    context,
    (dialog) =>
        ContractTextDialog(title: title, hint: hint, required: required),
  );

  Future<void> _message(BuildContext context, String reference) async {
    market.tradeChat?.requestOpen(reference);
    await Navigator.of(context).maybePop();
    market.openDestination?.call('/messages');
  }

  static TextStyle _mono(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFamily: context.tokens.typography.monoFamily,
  );

  static String _participantStatus(BuildContext context, Object? status) =>
      contractText(context, switch ((status as num?)?.toInt()) {
        1 => '已接受',
        2 => '已拒绝',
        3 => '进行中',
        4 => '已完成',
        5 => '已违约',
        6 => '已退出',
        _ => '待审核',
      });
}

/// 发布 → 招募中 → 执行中 → 已完成, the current step marked.
class _Steps extends StatelessWidget {
  const _Steps(this.status);
  final int status;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = switch (status) {
      1 => 1,
      2 => 2,
      3 => 3,
      _ => 0,
    };
    final ended = status == 4 || status == 5;
    return Row(
      children: [
        for (final (i, label) in [
          (0, '发布'),
          (1, '招募中'),
          (2, '执行中'),
          (3, ended ? (status == 4 ? '已取消' : '已过期') : '已完成'),
        ])
          Expanded(
            child: Column(
              children: [
                Text(
                  contractText(context, label),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: i == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: i == current
                        ? t.colors.accent
                        : i < current
                        ? t.colors.textSecondary
                        : t.colors.textDisabled,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  height: 2,
                  color: i <= current
                      ? t.colors.accent
                      : t.surfaces.panel.border,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.done);
  final bool done;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? t.colors.success : null,
        border: Border.all(
          color: done ? t.colors.success : t.colors.textSecondary,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: done
          ? MarketplaceIcon(
              MarketplaceGlyph.check,
              size: 12,
              color: t.colors.onAccent,
            )
          : null,
    );
  }
}
