import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_silhouette.dart';
import 'marketplace_widgets.dart';

/// The market's two-level SCM category tree, shared by 市场 and the publish
/// wizard so both browse categories the same way.
class MarketCategoryTree extends StatelessWidget {
  const MarketCategoryTree({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.allLabel,
    this.allCount,
    this.expandedRoots = const {},
    this.childCount,
    this.accent,
    super.key,
  });
  final List<MarketRow> categories;
  final int selected;
  final ValueChanged<int> onSelect;
  final String allLabel;
  final Object? allCount;
  final Set<int> expandedRoots;
  final Object? Function(int id)? childCount;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final locale = marketLocale(context);
    int idOf(MarketRow r) => (r['id'] as num).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarketCategoryTreeRow(
          name: allLabel,
          id: 0,
          selected: selected == 0,
          onTap: () => onSelect(0),
          count: allCount,
          accent: accent,
        ),
        for (final root in categories.where(
          (r) => r['parentId'] == null || r['parentId'] == 0,
        )) ...[
          MarketCategoryTreeRow(
            name: marketName(root, locale, field: 'name'),
            id: idOf(root),
            selected: selected == idOf(root),
            expanded: expandedRoots.contains(idOf(root)),
            onTap: () => onSelect(idOf(root)),
            accent: accent,
          ),
          if (expandedRoots.contains(idOf(root)))
            for (final child in categories.where((r) => r['parentId'] == root['id']))
              MarketCategoryTreeRow(
                name: marketName(child, locale, field: 'name'),
                id: idOf(child),
                child: true,
                selected: selected == idOf(child),
                onTap: () => onSelect(idOf(child)),
                count: childCount?.call(idOf(child)),
                accent: accent,
              ),
        ],
      ],
    );
  }
}

class MarketCategoryTreeRow extends StatelessWidget {
  const MarketCategoryTreeRow({
    required this.name,
    required this.id,
    required this.selected,
    required this.onTap,
    this.child = false,
    this.expanded = false,
    this.count,
    this.accent,
    super.key,
  });
  final String name;
  final int id;
  final bool selected, child, expanded;
  final VoidCallback onTap;
  final Object? count;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tint = accent ?? t.colors.accent;
    return SizedBox(
      height: child ? 30 : 34,
      child: Material(
        color: selected ? tint.withValues(alpha: .15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: StarBridgeActionRow(
          controlKey: ValueKey(('market-category', id)),
          inheritContentStyle: true,
          semanticSelected: selected,
          baseRadius: 6,
          onActivate: (_, _) => onTap(),
          child: Container(
            padding: EdgeInsets.only(left: child ? 36 : 8, right: 8),
            decoration: BoxDecoration(
              border: selected
                  ? Border(left: BorderSide(color: tint, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                if (!child) ...[
                  SizedBox(
                    width: 22,
                    height: 16,
                    child: MarketSilhouette(id, color: t.colors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: child ? 12.5 : 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? t.colors.textPrimary : t.colors.textSecondary,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    marketMoney(count),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: t.typography.monoFamily,
                      color: t.colors.textSecondary,
                    ),
                  ),
                if (!child && id != 0)
                  MarketplaceIcon(
                    expanded ? MarketplaceGlyph.expand : MarketplaceGlyph.next,
                    size: 14,
                    color: t.colors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
