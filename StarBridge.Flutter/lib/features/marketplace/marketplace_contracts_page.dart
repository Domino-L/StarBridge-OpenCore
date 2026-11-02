import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_contract_detail.dart';
import 'marketplace_contract_publish.dart';
import 'marketplace_contracts_controller.dart';
import 'marketplace_contracts_copy.dart';
import 'marketplace_controller.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';

/// 大厅 · 合约 (0.7.2 G1, approved preview contracts-preview): open contracts
/// with filters on the left and cards on the right; 我发布的 / 我参与的 grouped
/// by state. Every document opens in the right-side panel (rule 2.2).
class MarketplaceContractsPage extends StatefulWidget {
  const MarketplaceContractsPage(this.market, {super.key});
  final MarketplaceController market;
  @override
  State<MarketplaceContractsPage> createState() => _ContractsState();
}

class _ContractsState extends State<MarketplaceContractsPage> {
  MarketplaceContractsController? c;
  int view = 0; // 0 公开 · 1 我发布的 · 2 我参与的
  String reward = 'all', sort = 'new';
  bool eligibleOnly = false;

  @override
  void initState() {
    super.initState();
    final port = widget.market.port;
    if (port is MarketplaceContractsPort &&
        (port as MarketplaceContractsPort).contractsSupported) {
      c = MarketplaceContractsController(port as MarketplaceContractsPort);
      unawaited(c!.loadPublic());
      unawaited(c!.loadMine('created'));
      unawaited(c!.loadMine('participated'));
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  Future<void> _open(MarketRow row) async {
    final id = (row['id'] as num?)?.toInt();
    final contracts = c;
    if (id == null || contracts == null) return;
    unawaited(contracts.open(id));
    await showContractDetail(context, widget.market, contracts);
    contracts.close();
  }

  @override
  Widget build(BuildContext context) {
    final contracts = c;
    if (contracts == null) {
      return MarketNotice(contractText(context, '合约需要 SCM 授权更新后才能使用。'));
    }
    return ListenableBuilder(
      listenable: contracts,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: MarketSubTabs(key: const Key('market-contracts-view'), [
              for (final (i, label, count) in [
                (0, '公开合约', null),
                (1, '我发布的', contracts.created.total),
                (2, '我参与的', contracts.participated.total),
              ])
                MarketSubTab(
                  contractText(context, label),
                  count: count == null || count == 0 ? null : count,
                  selected: view == i,
                  onTap: () => setState(() => view = i),
                  controlKey: ValueKey(('market-contracts-view', i)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: view == 0
                ? _public(context, contracts)
                : _mine(context, contracts),
          ),
        ],
      ),
    );
  }

  Widget _public(
    BuildContext context,
    MarketplaceContractsController contracts,
  ) {
    final rows = [
      for (final row in contracts.public.rows)
        if ((reward == 'all' || row['rewardType'] == reward) &&
            (!eligibleOnly || row['eligible'] != false))
          row,
    ];
    final sorted = [...rows]
      ..sort(switch (sort) {
        'reward' => (a, b) => ((b['rewardUec'] as num?) ?? 0).compareTo(
          (a['rewardUec'] as num?) ?? 0,
        ),
        'deadline' =>
          (a, b) => ((a['expireTime'] as num?) ?? 1 << 52).compareTo(
            (b['expireTime'] as num?) ?? 1 << 52,
          ),
        _ => (a, b) => 0,
      });
    return LayoutBuilder(
      builder: (context, box) {
        final filters = SizedBox(
          width: 228,
          child: _filters(context, contracts),
        );
        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarketHeading(
              contractText(context, '公开合约'),
              trailing: Row(
                children: [
                  // Takes all the free width, so the buttons reach the right edge.
                  Expanded(
                    child: Text(
                      contractText(context, '共 {n} 个 · {sort}', {
                        'n': '${contracts.public.total}',
                        'sort': contractText(
                          context,
                          const {'reward': '报酬最高', 'deadline': '即将截止'}[sort] ??
                              '最新发布',
                        ),
                      }),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                  ),
                  for (final (key, label) in [
                    ('new', '最新发布'),
                    ('reward', '报酬最高'),
                    ('deadline', '即将截止'),
                  ]) ...[
                    MarketToggle(
                      key: ValueKey(('market-contracts-sort', key)),
                      label: Text(contractText(context, label)),
                      selected: sort == key,
                      onSelected: (_) => setState(() => sort = key),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 8),
                  marketButtonAction(
                    key: const Key('market-contracts-publish'),
                    FilledButton(
                      style: tradePrimaryStyle(context),
                      onPressed: () => showContractPublish(context, contracts),
                      child: Text('+ ${contractText(context, '发布合约')}'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _states(
                context,
                contracts.public,
                retry: contracts.loadPublic,
                child: GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 210,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  children: [
                    for (final row in sorted)
                      ContractCard(row, onOpen: () => _open(row)),
                  ],
                ),
                more: () => contracts.loadPublic(more: true),
              ),
            ),
          ],
        );
        if (box.maxWidth < 760) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            filters,
            const SizedBox(width: 18),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  Widget _filters(
    BuildContext context,
    MarketplaceContractsController contracts,
  ) {
    Widget heading(String label, {bool first = false}) => Padding(
      padding: EdgeInsets.only(top: first ? 0 : 16, bottom: 8),
      child: Row(
        children: [
          Transform.scale(
            scale: .75,
            alignment: Alignment.centerLeft,
            child: const MarketHeadingMark(),
          ),
          const SizedBox(width: 6),
          Text(
            contractText(context, label),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    Widget choices<T>(
      String group,
      Map<T, String> values,
      T selected,
      ValueChanged<T> pick,
    ) => MarketChoiceGrid(
      children: [
        for (final entry in values.entries)
          MarketToggle(
            key: ValueKey(('market-contracts-filter', group, '${entry.key}')),
            fill: true,
            label: Text(
              contractText(context, entry.value),
              maxLines: 1,
              softWrap: false,
            ),
            selected: selected == entry.key,
            onSelected: (_) => pick(entry.key),
          ),
      ],
    );
    return MarketSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          heading('类型', first: true),
          choices<String?>(
            'type',
            const {
              null: '全部',
              'BOUNTY': '悬赏',
              'SERVICE': '委托',
              'COOPERATION': '协作',
            },
            contracts.type,
            (v) =>
                unawaited(contracts.filter(type: v, status: contracts.status)),
          ),
          heading('状态'),
          choices<int?>(
            'status',
            const {1: '招募中', 2: '执行中', 3: '已完成'},
            contracts.status,
            (v) => unawaited(contracts.filter(type: contracts.type, status: v)),
          ),
          heading('报酬'),
          choices<String>(
            'reward',
            const {'all': '全部', 'UEC': 'UEC', 'ITEMS': '物品'},
            reward,
            (v) => setState(() => reward = v),
          ),
          heading('我能报名的'),
          choices<bool>(
            'eligible',
            const {false: '不限', true: '信誉够'},
            eligibleOnly,
            (v) => setState(() => eligibleOnly = v),
          ),
        ],
      ),
    );
  }

  Widget _mine(BuildContext context, MarketplaceContractsController contracts) {
    final list = view == 1 ? contracts.created : contracts.participated;
    final groups = <(String, List<MarketRow>)>[
      for (final (label, states) in [
        ('招募中', {1}),
        ('执行中', {2}),
        ('已完成', {3}),
        ('已取消', {4, 5, 0}),
      ])
        (
          label,
          [
            for (final row in list.rows)
              if (states.contains((row['status'] as num?)?.toInt())) row,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    return _states(
      context,
      list,
      retry: () => contracts.loadMine(view == 1 ? 'created' : 'participated'),
      more: () => contracts.loadMine(
        view == 1 ? 'created' : 'participated',
        more: true,
      ),
      child: ListView(
        children: [
          for (final (label, rows) in groups) ...[
            MarketHeading(
              contractText(context, label),
              trailing: Text(
                '${rows.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.tokens.colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            MarketSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final row in rows)
                    ContractRow(row, mine: view == 1, onOpen: () => _open(row)),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _states(
    BuildContext context,
    MarketRecordList list, {
    required VoidCallback retry,
    required VoidCallback more,
    required Widget child,
  }) {
    if (list.rows.isEmpty) {
      if (list.loading) {
        return const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: list.failed
            ? marketTextAction(
                key: const Key('market-contracts-retry'),
                onPressed: retry,
                child: Text(
                  contractText(
                    context,
                    list.error == 'marketplace.reauthorize_required'
                        ? '合约需要 SCM 授权更新后才能使用。'
                        : '暂时读不到合约，点此重试。',
                  ),
                ),
              )
            : Text(
                contractText(context, '还没有合约。'),
                style: TextStyle(color: context.tokens.colors.textSecondary),
              ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (event) {
        if (event.metrics.extentAfter < 400 && list.more && !list.loading) {
          more();
        }
        return false;
      },
      child: child,
    );
  }
}

/// The contract's kind color: 悬赏 red, 委托 blue, 协作 green.
Color contractTypeColor(BuildContext context, Object? type) => switch (type) {
  'BOUNTY' => context.tokens.colors.danger,
  'COOPERATION' => context.tokens.colors.success,
  _ => context.tokens.colors.accent,
};

String contractTypeLabel(BuildContext context, Object? type) =>
    contractText(context, switch (type) {
      'BOUNTY' => '悬赏',
      'COOPERATION' => '协作',
      _ => '委托',
    });

String contractStatusLabel(BuildContext context, Object? status) =>
    contractText(context, switch ((status as num?)?.toInt()) {
      0 => '草稿',
      1 => '招募中',
      2 => '执行中',
      3 => '已完成',
      4 => '已取消',
      5 => '已过期',
      _ => '招募中',
    });

/// "剩 2 天" from SCM's deadline (millis or text).
String contractRemaining(BuildContext context, Object? expire) {
  final millis = expire is num
      ? expire.toInt()
      : int.tryParse('${expire ?? ''}');
  final at = millis != null
      ? DateTime.fromMillisecondsSinceEpoch(millis)
      : DateTime.tryParse('${expire ?? ''}');
  if (at == null) return '';
  final left = at.difference(DateTime.now());
  if (left.isNegative) return contractText(context, '已截止');
  return left.inHours < 24
      ? contractText(context, '剩 {n} 小时', {'n': '${left.inHours.clamp(1, 23)}'})
      : contractText(context, '剩 {n} 天', {'n': '${left.inDays}'});
}

/// The reward: gold UEC, or the item note in gold.
class ContractReward extends StatelessWidget {
  const ContractReward(this.row, {this.size = 17, super.key});
  final MarketRow row;
  final double size;
  @override
  Widget build(BuildContext context) => row['rewardType'] == 'UEC'
      ? MarketPrice(row['rewardUec'], size: size)
      : Text(
          '${row['rewardNote'] ?? contractText(context, '物品')}',
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: size - 3,
            fontWeight: FontWeight.w600,
            color: MarketplacePalette.gold,
          ),
        );
}

class ContractCard extends StatelessWidget {
  const ContractCard(this.row, {required this.onOpen, super.key});
  final MarketRow row;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final kind = contractTypeColor(context, row['type']);
    final facts = [
      contractText(context, '名额 {n}', {
        'n': '${row['taken'] ?? 0} / ${row['slots'] ?? '—'}',
      }),
      contractText(context, '信誉 ≥ {n}', {'n': '${row['minReputation'] ?? 0}'}),
      if (row['location'] != null) '${row['location']}',
      contractRemaining(context, row['expireTime']),
    ].where((s) => s.isNotEmpty).join('   ');
    return Material(
      color: t.surfaces.panel.fill,
      child: StarBridgeActionRow(
        controlKey: ValueKey(('market-contract-card', '${row['id']}')),
        inheritContentStyle: true,
        baseRadius: 0,
        onActivate: (_, _) => onOpen(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: kind, width: 3),
              top: BorderSide(color: t.surfaces.panel.border),
              right: BorderSide(color: t.surfaces.panel.border),
              bottom: BorderSide(color: t.surfaces.panel.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MarketSlantTag(
                    contractTypeLabel(context, row['type']),
                    color: kind,
                  ),
                  const Spacer(),
                  if (row['mine'] == true)
                    MarketSlantTag(
                      contractText(context, '我的'),
                      color: t.colors.textSecondary,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${row['title'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(height: 22, child: ContractReward(row)),
              const SizedBox(height: 6),
              Text(
                facts,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
              ),
              const Spacer(),
              Divider(height: 14, color: t.surfaces.panel.border),
              Row(
                children: [
                  ContractPerson(
                    '${row['creator'] ?? ''}',
                    online: row['creatorOnline'],
                    reputation: row['creatorReputation'],
                  ),
                  const Spacer(),
                  if (row['mine'] != true &&
                      (row['status'] as num?)?.toInt() == 1)
                    MarketSlantTag(
                      contractText(
                        context,
                        row['applied'] == true ? '已报名' : '报名',
                      ),
                      color: t.colors.accent,
                      solid: row['applied'] != true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Masked name square, presence dot and reputation.
class ContractPerson extends StatelessWidget {
  const ContractPerson(this.name, {this.online, this.reputation, super.key});
  final String name;
  final Object? online, reputation;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MarketplacePalette.artBackdrop,
            border: Border.all(color: marketLine(context)),
          ),
          child: Text(
            name.isEmpty ? '?' : name.characters.first,
            style: TextStyle(fontSize: 10.5, color: t.colors.textSecondary),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (online is bool) ...[
          const SizedBox(width: 5),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online == true ? t.colors.success : t.colors.textDisabled,
            ),
          ),
        ],
        if (reputation != null) ...[
          const SizedBox(width: 6),
          Text(
            '★ $reputation',
            style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// A row of 我发布的 / 我参与的: kind, title, number and the state.
class ContractRow extends StatelessWidget {
  const ContractRow(
    this.row, {
    required this.mine,
    required this.onOpen,
    super.key,
  });
  final MarketRow row;
  final bool mine;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final kind = contractTypeColor(context, row['type']);
    final status = (row['status'] as num?)?.toInt();
    final applicants = (row['applications'] as num?)?.toInt() ?? 0;
    final waitingOnMe = mine && (status == 2 || status == 1 && applicants > 0);
    return StarBridgeActionRow(
      controlKey: ValueKey(('market-contract-row', '${row['id']}')),
      inheritContentStyle: true,
      baseRadius: 0,
      onActivate: (_, _) => onOpen(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: kind, width: 3),
            bottom: BorderSide(color: marketLine(context)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MarketSlantTag(
                        contractTypeLabel(context, row['type']),
                        color: kind,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${row['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${row['number'] ?? ''}',
                      if (!mine)
                        '${contractText(context, '发布者')} ${row['creator'] ?? ''}',
                      if (row['location'] != null) '${row['location']}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 120, child: ContractReward(row, size: 14)),
            SizedBox(
              width: 120,
              child: Text(
                contractStatusLabel(context, status),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: waitingOnMe
                      ? MarketplacePalette.attention
                      : t.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
