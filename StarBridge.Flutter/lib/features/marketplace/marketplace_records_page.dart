import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_details.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';
import 'marketplace_records_copy.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// 我的交易 · 评价 (0.7.2 G5, approved preview `trade-records-preview`):
/// reviews other members gave me, with the average and star spread on top.
class MarketplaceReviewsView extends StatefulWidget {
  const MarketplaceReviewsView(this.c, {super.key});
  final MarketplaceRecordsController c;
  @override
  State<MarketplaceReviewsView> createState() => _ReviewsState();
}

class _ReviewsState extends State<MarketplaceReviewsView> {
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// The summary needs every review; members have few, so read them all
  /// (bounded at 10 pages).
  Future<void> _loadAll() async {
    final list = widget.c.reviews;
    await widget.c.load('reviews');
    for (var i = 0; i < 9 && list.more && !list.failed && mounted; i++) {
      await widget.c.load('reviews', more: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final list = widget.c.reviews;
      final public = list.rows
          .where((r) => _audit(r) == _Audit.public)
          .toList();
      final pending = list.rows
          .where((r) => _audit(r) == _Audit.pending)
          .length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarketHeading(
            recordsText(context, '收到的评价'),
            trailing: _Muted(
              recordsText(context, '共 {n} 条 · 来自交易和合约', {'n': '${list.total}'}),
            ),
          ),
          const SizedBox(height: 12),
          if (public.isNotEmpty || pending > 0) ...[
            _ReviewSummary(public, pending),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _RecordList(
              list,
              retry: _loadAll,
              empty: recordsText(context, '还没有收到评价。'),
              row: (r, last) => _ReviewRow(r, last: last),
            ),
          ),
        ],
      );
    },
  );
}

enum _Audit { public, pending, rejected }

_Audit _audit(MarketRow r) => switch ((r['auditStatus'] as num?)?.toInt()) {
  0 => _Audit.pending,
  2 => _Audit.rejected,
  _ => _Audit.public,
};

int _rating(MarketRow r) => ((r['rating'] as num?)?.toInt() ?? 0).clamp(0, 5);

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary(this.public, this.pending);
  final List<MarketRow> public;
  final int pending;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final counts = List.filled(6, 0);
    for (final r in public) {
      counts[_rating(r)]++;
    }
    final average = public.isEmpty
        ? 0.0
        : public.fold<int>(0, (s, r) => s + _rating(r)) / public.length;
    final most = counts.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Container(
      key: const Key('market-reviews-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: t.surfaces.panel.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surfaces.panel.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                public.isEmpty ? '—' : average.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFamily: t.typography.monoFamily,
                  color: MarketplacePalette.gold,
                ),
              ),
              _Stars(average.round()),
              const SizedBox(height: 4),
              _Muted(
                recordsText(context, '{n} 条已公开 · {p} 条审核中', {
                  'n': '${public.length}',
                  'p': '$pending',
                }),
              ),
            ],
          ),
          const SizedBox(width: 28),
          SizedBox(
            width: 240,
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: _Muted(
                            recordsText(context, '{n} 星', {'n': '$star'}),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: counts[star] / most,
                              minHeight: 5,
                              color: MarketplacePalette.gold,
                              backgroundColor: marketLine(context),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${counts[star]}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: t.typography.monoFamily,
                              color: t.colors.textSecondary,
                            ),
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
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars(this.value, {this.size = 14});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        MarketplaceIcon(
          i <= value ? MarketplaceGlyph.rating : MarketplaceGlyph.ratingEmpty,
          size: size,
          color: i <= value
              ? MarketplacePalette.gold
              : context.tokens.colors.textSecondary,
        ),
    ],
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.r, {required this.last});
  final MarketRow r;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final contract =
        '${r['source'] ?? ''}'.contains('合约') ||
        '${r['source'] ?? ''}'.toLowerCase().contains('contract');
    final content = '${r['content'] ?? ''}'.trim();
    final audit = _audit(r);
    return _RowShell(
      last: last,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Initial('${r['reviewer'] ?? ''}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MarketSlantTag(
                      recordsText(context, contract ? '合约' : '交易'),
                      color: contract
                          ? MarketplacePalette.buyer
                          : t.colors.accent,
                    ),
                    Text(
                      '${r['reviewer'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _Stars(_rating(r), size: 13),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  content.isEmpty
                      ? recordsText(context, '（只打了分，没有写评价）')
                      : content,
                  style: TextStyle(
                    fontSize: 13,
                    color: content.isEmpty
                        ? t.colors.textSecondary
                        : t.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (r['transactionId'] != null) _Mono('#${r['transactionId']}'),
              MarketPublished(r['createTime']),
              if (audit != _Audit.public) ...[
                const SizedBox(height: 4),
                MarketSlantTag(
                  recordsText(context, audit == _Audit.pending ? '审核中' : '未通过'),
                  color: audit == _Audit.pending
                      ? MarketplacePalette.attention
                      : t.colors.textSecondary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 我的交易 · 举报与拉黑 (0.7.2 G6/G7): my reports with SCM's outcome, and
/// my blocklist with a confirmed unblock.
class MarketplaceReportsBlocksView extends StatefulWidget {
  const MarketplaceReportsBlocksView(this.c, {super.key});
  final MarketplaceRecordsController c;
  @override
  State<MarketplaceReportsBlocksView> createState() => _ReportsBlocksState();
}

class _ReportsBlocksState extends State<MarketplaceReportsBlocksView> {
  bool blocks = false;
  @override
  void initState() {
    super.initState();
    widget.c.load('reports');
  }

  void _show(bool value) {
    setState(() => blocks = value);
    widget.c.load(value ? 'blocklist' : 'reports');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final list = blocks ? widget.c.blocklist : widget.c.reports;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: MarketSubTabs(key: const Key('market-records-kind'), [
              MarketSubTab(
                recordsText(context, '我的举报'),
                selected: !blocks,
                onTap: () => _show(false),
                controlKey: const ValueKey(('market-records-kind', 0)),
              ),
              MarketSubTab(
                recordsText(context, '黑名单'),
                selected: blocks,
                onTap: () => _show(true),
                controlKey: const ValueKey(('market-records-kind', 1)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          MarketHeading(
            recordsText(context, blocks ? '黑名单' : '我的举报'),
            trailing: _Muted(
              recordsText(
                context,
                blocks ? '共 {n} 人 · 拉黑后对方不能向你发起交易' : '共 {n} 条 · 处理结果来自 SCM',
                {'n': '${list.total}'},
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _RecordList(
              list,
              retry: () => widget.c.load(blocks ? 'blocklist' : 'reports'),
              more: () =>
                  widget.c.load(blocks ? 'blocklist' : 'reports', more: true),
              empty: recordsText(
                context,
                blocks ? '黑名单是空的。拉黑从交易单或订单面板发起。' : '还没有举报记录。新建举报从交易单里发起。',
              ),
              row: (r, last) => blocks
                  ? _BlockRow(r, widget.c, last: last)
                  : _ReportRow(r, last: last),
            ),
          ),
        ],
      );
    },
  );
}

Color _reportColor(BuildContext context, String status) =>
    status.contains('驳回') || status.toLowerCase().contains('reject')
    ? context.tokens.colors.textSecondary
    : status.contains('已处理') || status.toLowerCase().contains('handled')
    ? MarketplacePalette.success
    : MarketplacePalette.attention;

class _ReportRow extends StatelessWidget {
  const _ReportRow(this.r, {required this.last});
  final MarketRow r;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = '${r['status'] ?? ''}';
    final color = _reportColor(context, status);
    final result = '${r['result'] ?? ''}'.trim();
    final content = '${r['content'] ?? ''}'.trim();
    return _RowShell(
      last: last,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${r['transactionNumber'] ?? ''} · ${recordsText(context, '举报 {name}', {'name': '${r['reported'] ?? ''}'})}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${recordsText(context, '类型：')}${r['reportType'] ?? ''}${content.isEmpty ? '' : ' · “$content”'}',
                  style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
                ),
                if (result.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .08),
                      border: Border(left: BorderSide(color: color, width: 2)),
                    ),
                    child: Text(
                      '${recordsText(context, '处理结果：')}$result',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Muted(marketRecordTime(r['createTime'])),
                if (r['handleTime'] != null)
                  _Muted(
                    recordsText(context, '处理于 {time}', {
                      'time': marketRecordTime(r['handleTime'], date: true),
                    }),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerRight,
              child: MarketSlantTag(status, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow(this.r, this.c, {required this.last});
  final MarketRow r;
  final MarketplaceRecordsController c;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final reference = '${r['ref'] ?? ''}';
    final busy = c.unblocking.contains(reference);
    return _RowShell(
      last: last,
      child: Row(
        children: [
          _Initial('${r['name'] ?? ''}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['name'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                _Muted('${recordsText(context, '原因：')}${r['reason'] ?? '—'}'),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: _Muted(
              recordsText(context, '{time} 拉黑', {
                'time': marketRecordTime(r['createTime'], date: true),
              }),
            ),
          ),
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : MarketToggle(
                      key: ValueKey(('market-unblock', reference)),
                      label: Text(recordsText(context, '解除')),
                      selected: true,
                      onSelected: (_) => _confirm(context, reference),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String reference) async {
    final name = '${r['name'] ?? ''}';
    final ok = await tradeMotionDialog<bool>(
      context,
      (dialog) => AlertDialog(
        title: Text(recordsText(context, '解除拉黑 {name}？', {'name': name})),
        content: Text(
          '${recordsText(context, '解除后，对方可以再次向你发起交易，你也能看到对方的挂单。')}'
          '${r['reason'] == null ? '' : recordsText(context, '拉黑原因：{reason}（{time}）。', {'reason': '${r['reason']}', 'time': marketRecordTime(r['createTime'], date: true)})}',
        ),
        actions: [
          marketButtonAction(
            key: const Key('market-unblock-cancel'),
            TextButton(
              autofocus: true,
              onPressed: () => dismissStarBridgeDialog<bool>(
                dialog,
                source: StarBridgeActivationOrigin.sourceOf(dialog),
                result: false,
              ),
              child: Text(recordsText(context, '取消')),
            ),
          ),
          marketButtonAction(
            key: const Key('market-unblock-confirm'),
            FilledButton(
              style: tradePrimaryStyle(dialog),
              onPressed: () => dismissStarBridgeDialog<bool>(
                dialog,
                source: StarBridgeActivationOrigin.sourceOf(dialog),
                result: true,
              ),
              child: Text(recordsText(context, '解除拉黑')),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final confirmed = await c.unblock(reference);
    if (!confirmed && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showOnly(
        starBridgeTimedSnackBar(
          content: Text(recordsText(context, '没有解除成功，列表已刷新为 SCM 上的当前状态。')),
        ),
      );
    }
  }
}

/// `yyyy-MM-dd HH:mm` (or the date only) in local time, for SCM millis or text.
String marketRecordTime(Object? value, {bool date = false}) {
  final millis = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
  final at = millis != null
      ? DateTime.fromMillisecondsSinceEpoch(millis)
      : DateTime.tryParse('${value ?? ''}');
  if (at == null) return '${value ?? ''}';
  String two(int n) => n.toString().padLeft(2, '0');
  final local = at.toLocal();
  final day = '${local.year}-${two(local.month)}-${two(local.day)}';
  return date ? day : '$day ${two(local.hour)}:${two(local.minute)}';
}

class _RecordList extends StatelessWidget {
  const _RecordList(
    this.list, {
    required this.retry,
    required this.empty,
    required this.row,
    this.more,
  });
  final MarketRecordList list;
  final VoidCallback retry;
  final VoidCallback? more;
  final String empty;
  final Widget Function(MarketRow row, bool last) row;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (list.rows.isEmpty) {
      if (list.loading) {
        return const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: list.failed
            ? marketTextAction(
                key: const Key('market-records-retry'),
                onPressed: retry,
                child: Text(
                  recordsText(
                    context,
                    list.error == 'marketplace.reauthorize_required'
                        ? '需要重新授权后才能查看。'
                        : '暂时读不到，点此重试。',
                  ),
                ),
              )
            : Text(
                empty,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.colors.textSecondary),
              ),
      );
    }
    return ListView(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.surfaces.panel.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: [
                for (final (i, r) in list.rows.indexed)
                  row(r, i == list.rows.length - 1),
              ],
            ),
          ),
        ),
        if (list.more && more != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: marketTextAction(
                key: const Key('market-records-more'),
                onPressed: list.loading ? null : more,
                child: Text(recordsText(context, '加载更多')),
              ),
            ),
          ),
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.child, required this.last});
  final Widget child;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.panel.fill,
      border: Border(
        bottom: last ? BorderSide.none : BorderSide(color: marketLine(context)),
      ),
    ),
    child: child,
  );
}

class _Initial extends StatelessWidget {
  const _Initial(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MarketplacePalette.artBackdrop,
      border: Border.all(color: marketLine(context)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.tokens.colors.textSecondary,
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 11.5,
      color: context.tokens.colors.textSecondary,
    ),
  );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontFamily: context.tokens.typography.monoFamily,
      color: context.tokens.colors.textSecondary,
    ),
  );
}
