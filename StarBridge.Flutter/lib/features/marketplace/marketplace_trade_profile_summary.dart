import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

import 'marketplace_controller.dart';
import 'marketplace_details.dart';
import 'marketplace_port.dart';
import 'marketplace_states.dart' show marketTextAction;
import 'marketplace_trade_profile.dart';
import 'marketplace_trade_profile_copy.dart';

class TradeProfileSummary extends StatefulWidget {
  const TradeProfileSummary(this.market, {this.card = false, super.key});
  final MarketplaceController market;

  /// 我的交易's rail (layout A): the same fields as a labelled card.
  final bool card;
  @override
  State<TradeProfileSummary> createState() => _SummaryState();
}

class _SummaryState extends State<TradeProfileSummary> {
  MarketRow? profile;
  String? error;
  bool loading = true;
  late final revision = widget.market.contextRevision;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final port = widget.market.port;
    if (port is! BridgeMarketplacePort) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await port.tradeProfile();
      if (mounted && revision == widget.market.contextRevision) {
        setState(() => profile = value);
      }
    } catch (e) {
      if (mounted && revision == widget.market.contextRevision) {
        setState(
          () => error = e is MarketplaceTradeError
              ? e.code
              : 'marketplace.unavailable',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.market;
    if (c.port is! BridgeMarketplacePort || revision != c.contextRevision) {
      return const SizedBox.shrink();
    }
    String text(String key) => tradeProfileText(context, key);
    final row = profile;
    Future<void> edit() async {
      final result = await editTradeProfile(context, c);
      if (mounted && revision == c.contextRevision && result != null) {
        setState(() => profile = result);
      }
    }

    if (widget.card) return _card(context, row, edit);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(text('title')),
          if (loading)
            const SizedBox(width: 80, child: LinearProgressIndicator()),
          if (row != null) ...[
            Text(marketTradeTime(context, row)),
            Text('${row['userMobile'] ?? ''}'),
            Text('${text('limit')}: ${row['orderLimit'] ?? '—'}'),
          ],
          if (error != null)
            Text(tradeProfileErrorText(context, error!, reading: true)),
          marketTextAction(
            key: const Key('market-trade-profile-summary-edit'),
            onPressed: loading ? null : edit,
            child: Text(text('edit')),
          ),
          if (error != null)
            marketTextAction(
              key: const Key('market-trade-profile-summary-retry'),
              onPressed: loading ? null : load,
              child: Text(text('retry')),
            ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    MarketRow? row,
    Future<void> Function() edit,
  ) {
    final t = context.tokens;
    String text(String key) => tradeProfileText(context, key);
    Widget pair(String label, String value, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: mono ? t.typography.monoFamily : null,
                color: t.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('market-trade-profile-card'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: t.surfaces.panel.fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.surfaces.panel.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text('title'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.colors.textSecondary,
                  ),
                ),
              ),
              marketTextAction(
                key: const Key('market-trade-profile-summary-edit'),
                onPressed: loading ? null : edit,
                // Short on the card; readers still hear the full action.
                child: Semantics(
                  label: text('edit'),
                  excludeSemantics: true,
                  child: Text(text('editShort')),
                ),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (row != null) ...[
            pair(text('hours'), marketTradeTime(context, row)),
            pair(text('contact'), '${row['userMobile'] ?? '—'}'),
            pair(text('limit'), '${row['orderLimit'] ?? '—'}', mono: true),
          ],
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              tradeProfileErrorText(context, error!, reading: true),
              style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: marketTextAction(
                key: const Key('market-trade-profile-summary-retry'),
                onPressed: loading ? null : load,
                child: Text(text('retry')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
