// 我的交易, layout A (user 2026-10-23, preview TradingHall/my-trades-layout.html):
// a left rail for the sections, the trading profile as a card under it, one
// filter row per section and an empty state that says what to do next.
import 'package:flutter/material.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_states.dart' show marketButtonAction;

/// One rail entry: its tab id, label and an optional count ("3 / 24").
/// [hot] marks a count that waits on me.
typedef MarketRailItem = ({int id, String label, String? count, bool hot});

class MarketActivityRail extends StatelessWidget {
  const MarketActivityRail({
    required this.items,
    required this.selected,
    required this.onSelect,
    this.footer,
    super.key,
  });
  final List<MarketRailItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 208,
      padding: const EdgeInsets.fromLTRB(0, 4, 14, 12),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: t.surfaces.panel.border)),
      ),
      child: ListView(
        children: [
          for (final item in items)
            _RailEntry(
              item,
              selected: item.id == selected,
              onTap: () => onSelect(item.id),
            ),
          if (footer != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: t.surfaces.panel.border),
            ),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry(this.item, {required this.selected, required this.onTap});
  final MarketRailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final count = item.count;
    // Like the hall's sub-tabs: a native text button through the shared
    // feedback wrapper, exposed as a selected button named by its label; the
    // count is its value.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          value: count,
          child: marketButtonAction(
            key: ValueKey(('market-activity-tab', item.id)),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
                backgroundColor: selected
                    ? t.colors.accent.withValues(alpha: .14)
                    : null,
                foregroundColor: t.colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    color: selected ? t.colors.accent : Colors.transparent,
                  ),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? t.colors.textPrimary
                            : t.colors.textSecondary,
                      ),
                    ),
                  ),
                  if (count != null)
                    ExcludeSemantics(
                      child: Container(
                        padding: item.hot
                            ? const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              )
                            : EdgeInsets.zero,
                        decoration: item.hot
                            ? BoxDecoration(
                                color: MarketplacePalette.attention,
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        child: Text(
                          count,
                          style: TextStyle(
                            fontFamily: t.typography.monoFamily,
                            fontSize: 11,
                            fontWeight: item.hot ? FontWeight.w700 : null,
                            color: item.hot
                                ? MarketplacePalette.onGoldTag
                                : t.colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's single filter row: its title, then its choices, then actions
/// pushed to the end.
class MarketSectionBar extends StatelessWidget {
  const MarketSectionBar(
    this.title, {
    this.filters = const [],
    this.actions = const [],
    super.key,
  });
  final String title;
  final List<Widget> filters, actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.colors.textPrimary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: filters,
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 12), action],
        ],
      ),
    );
  }
}

/// An empty list: what it means and where to go, instead of "已显示全部".
class MarketActivityEmpty extends StatelessWidget {
  const MarketActivityEmpty({
    required this.title,
    required this.body,
    this.actions = const [],
    super.key,
  });
  final String title, body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.surfaces.panel.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
