import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_records_controller.dart';
import 'marketplace_records_page.dart' show marketRecordTime;
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_warehouse_controller.dart';
import 'marketplace_widgets.dart';

/// 大厅 · 仓储 (0.7.2 G2, read only; approved preview warehouse-preview): my
/// spaces on the left; the chosen space's items, the ledger and listing escrow
/// on the right. Transfers, counts and stock-out stay on the SCM site.
class MarketplaceWarehousePage extends StatefulWidget {
  const MarketplaceWarehousePage(this.market, {super.key});
  final MarketplaceController market;
  @override
  State<MarketplaceWarehousePage> createState() => _WarehouseState();
}

class _WarehouseState extends State<MarketplaceWarehousePage> {
  MarketplaceWarehouseController? w;
  int view = 0; // 0 资产 · 1 账本 · 2 托管

  @override
  void initState() {
    super.initState();
    final port = widget.market.port;
    if (port is MarketplaceWarehousePort &&
        (port as MarketplaceWarehousePort).warehouseSupported) {
      w = MarketplaceWarehouseController(port as MarketplaceWarehousePort);
      unawaited(w!.loadSpaces());
      unawaited(w!.select(null));
      unawaited(w!.loadEscrow());
    }
  }

  @override
  void dispose() {
    w?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = w;
    if (controller == null) return MarketNotice(_t(context, 'needsScm'));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final right = _right(context, controller);
          if (box.maxWidth < 760) return right;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 240, child: _spaces(context, controller)),
              const SizedBox(width: 20),
              Expanded(child: right),
            ],
          );
        },
      ),
    );
  }

  Widget _spaces(BuildContext context, MarketplaceWarehouseController c) {
    final t = context.tokens;
    Widget space(
      int? id,
      String name,
      String sub,
      String meta,
    ) => StarBridgeActionRow(
      controlKey: ValueKey(('market-warehouse-space', '${id ?? 'all'}')),
      inheritContentStyle: true,
      baseRadius: 0,
      onActivate: (_, _) => unawaited(c.select(id)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: c.spaceId == id
              ? t.colors.accent.withValues(alpha: .08)
              : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: c.spaceId == id ? t.colors.accent : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
              ),
            if (meta.isNotEmpty)
              Text(
                meta,
                style: TextStyle(fontSize: 11, color: t.colors.textSecondary),
              ),
          ],
        ),
      ),
    );
    final summary = c.summary;
    return MarketSurface(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: MarketHeading(_t(context, 'mySpaces'), titleSize: 13),
          ),
          if (c.spacesLoading && c.spaces.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          space(
            null,
            _t(context, 'allSpaces'),
            '',
            summary == null
                ? ''
                : _t(context, 'kindsAvailable', {
                    'n': '${summary['items'] ?? 0}',
                    'a': '${summary['available'] ?? 0}',
                  }),
          ),
          for (final row in c.spaces)
            space(
              (row['id'] as num?)?.toInt(),
              '${row['name'] ?? ''}${row['isDefault'] == true ? ' · ${_t(context, 'default')}' : ''}',
              '${row['locationPath'] ?? row['location'] ?? ''}',
              _t(context, 'kindsAvailable', {
                'n': '${row['lines'] ?? 0}',
                'a': '${row['available'] ?? 0}',
              }),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: MarketHeading(_t(context, 'fleetSpaces'), titleSize: 13),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              _t(context, 'nextVersion'),
              style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _right(BuildContext context, MarketplaceWarehouseController c) {
    final t = context.tokens;
    final selected = c.spaces
        .where((s) => (s['id'] as num?)?.toInt() == c.spaceId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: MarketSubTabs(key: const Key('market-warehouse-view'), [
            for (final (i, key, count) in [
              (0, 'assets', c.inventory.total),
              (1, 'ledger', null),
              (2, 'escrow', c.escrow.length),
            ])
              MarketSubTab(
                _t(context, key),
                count: count == null || count == 0 ? null : count,
                selected: view == i,
                onTap: () => setState(() => view = i),
                controlKey: ValueKey(('market-warehouse-view', i)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          key: const Key('market-warehouse-readonly'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: t.surfaces.panel.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(context, 'readOnly'),
                  style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
                ),
              ),
              if (widget.market.openScm != null)
                marketTextAction(
                  key: const Key('market-warehouse-open-scm'),
                  onPressed: () => widget.market.openScm!(context),
                  child: Text('${_t(context, 'openScm')} →'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MarketHeading(
          selected == null
              ? _t(context, 'allSpaces')
              : '${selected['name'] ?? ''}',
          trailing: Text(
            [
              if (selected != null) '${selected['location'] ?? ''}',
              if (selected != null)
                _t(context, 'stock', {
                  'o': '${selected['onHand'] ?? 0}',
                  'r': '${selected['reserved'] ?? 0}',
                })
              else if (c.summary != null)
                _t(context, 'stock', {
                  'o': '${c.summary!['onHand'] ?? 0}',
                  'r': '${c.summary!['reserved'] ?? 0}',
                }),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (view) {
            1 => _list(
              context,
              c.ledger,
              () => c.loadLedger(),
              () => c.loadLedger(more: true),
              (r) => _LedgerRow(r),
            ),
            2 => _escrow(context, c),
            _ => _list(
              context,
              c.inventory,
              () => c.loadInventory(),
              () => c.loadInventory(more: true),
              (r) => _ItemRow(r),
              header: _ItemRow.header(context),
            ),
          },
        ),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    MarketRecordList list,
    VoidCallback retry,
    VoidCallback more,
    Widget Function(MarketRow) row, {
    Widget? header,
  }) {
    if (list.rows.isEmpty) {
      return _empty(
        context,
        loading: list.loading,
        failed: list.failed,
        error: list.error,
        retry: retry,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (event) {
        if (event.metrics.extentAfter < 400 && list.more && !list.loading) {
          more();
        }
        return false;
      },
      child: ListView(
        children: [
          ?header,
          MarketSurface(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final r in list.rows) row(r)]),
          ),
        ],
      ),
    );
  }

  Widget _escrow(BuildContext context, MarketplaceWarehouseController c) {
    if (c.escrow.isEmpty) {
      return _empty(
        context,
        loading: c.escrowLoading,
        failed: c.escrowFailed,
        retry: () => c.loadEscrow(),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (event) {
        if (event.metrics.extentAfter < 400 &&
            c.escrowMore &&
            !c.escrowLoading) {
          unawaited(c.loadEscrow(more: true));
        }
        return false;
      },
      child: ListView(
        children: [
          MarketSurface(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final r in c.escrow) _EscrowRow(r)]),
          ),
        ],
      ),
    );
  }

  Widget _empty(
    BuildContext context, {
    required bool loading,
    required bool failed,
    String? error,
    required VoidCallback retry,
  }) {
    if (loading) {
      return const Align(
        alignment: Alignment.topCenter,
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: failed
          ? marketTextAction(
              key: const Key('market-warehouse-retry'),
              onPressed: retry,
              child: Text(
                _t(
                  context,
                  error == 'marketplace.reauthorize_required'
                      ? 'needsScm'
                      : 'failed',
                ),
              ),
            )
          : Text(
              _t(context, 'empty'),
              style: TextStyle(color: context.tokens.colors.textSecondary),
            ),
    );
  }
}

TextStyle _num(BuildContext context, {Color? color}) => TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  fontFamily: context.tokens.typography.monoFamily,
  color: color,
);

String _itemName(BuildContext context, MarketRow r) =>
    '${(marketLocale(context) == 'en' ? r['itemNameEn'] : null) ?? r['itemName'] ?? ''}';

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.r);
  final MarketRow r;

  static Widget header(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      color: context.tokens.colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(80, 0, 14, 6),
      child: Row(
        children: [
          Expanded(child: Text(_t(context, 'item'), style: style)),
          SizedBox(width: 90, child: Text(_t(context, 'onHand'), style: style)),
          SizedBox(
            width: 90,
            child: Text(_t(context, 'reserved'), style: style),
          ),
          SizedBox(
            width: 90,
            child: Text(_t(context, 'available'), style: style),
          ),
          SizedBox(width: 180, child: Text(_t(context, 'where'), style: style)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reserved = (r['reserved'] as num?) ?? 0;
    final quality = RegExp(r'\d+')
        .firstMatch('${r['quality'] ?? ''}')
        ?.group(0);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: marketLine(context))),
      ),
      child: Row(
        children: [
          const SizedBox.square(dimension: 52, child: MarketArt(null)),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _itemName(context, r),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (quality != null)
                  MarketSlantTag(
                    _t(context, 'quality'),
                    color: MarketplacePalette.gold,
                    mono: quality,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text('${r['onHand'] ?? 0}', style: _num(context)),
          ),
          SizedBox(
            width: 90,
            child: Text(
              reserved == 0 ? '—' : '$reserved',
              style: _num(
                context,
                color: reserved == 0
                    ? t.colors.textSecondary
                    : MarketplacePalette.attention,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text('${r['available'] ?? 0}', style: _num(context)),
          ),
          SizedBox(
            width: 180,
            child: Text(
              '${r['space'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow(this.r);
  final MarketRow r;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final delta = (r['deltaOnHand'] as num?) ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: marketLine(context))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              marketRecordTime(r['time']),
              style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _operation(context, r['operationType']),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Text(
              _itemName(context, r),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              delta > 0 ? '+$delta' : '$delta',
              style: _num(
                context,
                color: delta > 0
                    ? t.colors.success
                    : delta < 0
                    ? t.colors.danger
                    : t.colors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              [
                '${r['space'] ?? ''}',
                if (r['from'] != null || r['to'] != null)
                  '${r['from'] ?? '—'} → ${r['to'] ?? '—'}',
                if (r['businessNo'] != null) '#${r['businessNo']}',
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  static String _operation(BuildContext context, Object? type) {
    final text = '${type ?? ''}'.toUpperCase();
    final key = text.contains('TRANSFER')
        ? 'transfer'
        : text.contains('OUT')
        ? 'stockOut'
        : text.contains('IN')
        ? 'stockIn'
        : text.contains('ADJUST') || text.contains('COUNT')
        ? 'adjust'
        : null;
    return key == null ? '${type ?? ''}' : _t(context, key);
  }
}

class _EscrowRow extends StatelessWidget {
  const _EscrowRow(this.r);
  final MarketRow r;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: marketLine(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemName(context, r),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '#${r['businessNo'] ?? ''}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '${r['quantity'] ?? 0}',
              style: _num(context, color: MarketplacePalette.attention),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              [
                r['orderStatus'],
                r['transactionStatus'],
                r['deliveryStatus'],
                r['status'],
              ].whereType<Object>().join(' · '),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, color: t.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

const _copy = <String, List<String>>{
  'mySpaces': ['我的仓位', '我的倉位', 'My spaces'],
  'allSpaces': ['全部仓位', '全部倉位', 'All spaces'],
  'default': ['默认', '預設', 'default'],
  'kindsAvailable': [
    '{n} 种 · 可用 {a}',
    '{n} 種 · 可用 {a}',
    '{n} kinds · {a} available',
  ],
  'fleetSpaces': ['舰队仓储', '艦隊倉儲', 'Fleet storage'],
  'nextVersion': ['下一版开放', '下一版開放', 'Coming in a later version'],
  'assets': ['资产', '資產', 'Assets'],
  'ledger': ['账本', '帳本', 'Ledger'],
  'escrow': ['托管', '託管', 'Escrow'],
  'readOnly': [
    '只读：转移、盘点、出库这一版先到 SCM 网站操作。',
    '唯讀：轉移、盤點、出庫這一版請到 SCM 網站操作。',
    'Read only: transfers, counts and stock-out are on the SCM site for now.',
  ],
  'openScm': ['打开 SCM 仓储', '開啟 SCM 倉儲', 'Open SCM storage'],
  'stock': [
    '在库 {o} · 托管中 {r}',
    '在庫 {o} · 託管中 {r}',
    '{o} on hand · {r} in escrow',
  ],
  'item': ['物品', '物品', 'Item'],
  'onHand': ['在库', '在庫', 'On hand'],
  'reserved': ['托管中', '託管中', 'Escrow'],
  'available': ['可用', '可用', 'Available'],
  'where': ['位置', '位置', 'Space'],
  'quality': ['品质', '品質', 'Quality'],
  'transfer': ['转移', '轉移', 'Transfer'],
  'stockOut': ['出库', '出庫', 'Out'],
  'stockIn': ['入库', '入庫', 'In'],
  'adjust': ['调整', '調整', 'Adjust'],
  'empty': ['这里还没有东西。', '這裡還沒有東西。', 'Nothing here yet.'],
  'failed': [
    '暂时读不到仓储，点此重试。',
    '暫時讀不到倉儲，點此重試。',
    'Could not load storage. Tap to retry.',
  ],
  'needsScm': [
    '仓储需要 SCM 授权更新后才能使用。',
    '倉儲需要 SCM 授權更新後才能使用。',
    'Storage needs an SCM permission update first.',
  ],
};

String _t(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) {
  final locale = marketLocale(context);
  var text =
      _copy[key]![locale == 'en'
          ? 2
          : locale == 'hant'
          ? 1
          : 0];
  for (final e in args.entries) {
    text = text.replaceAll('{${e.key}}', e.value);
  }
  return text;
}
