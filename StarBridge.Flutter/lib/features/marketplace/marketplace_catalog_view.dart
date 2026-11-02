import 'marketplace_hall_helpers.dart';
import 'marketplace_prefetch.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart' show SuiteChipData;
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_removable_chip_group.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import 'marketplace_controller.dart';
import 'marketplace_hall_drawers.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

Widget marketCatalogView(BuildContext context, MarketplaceController c, Widget Function(String, Widget Function(MarketRead), VoidCallback) block) {
    final read = c.blocks['catalog'];
    SuiteChipData filter(String id, String label) {
      final short = marketShort(label);
      return SuiteChipData(
        id: id,
        label: short,
        fullLabel: short == label ? null : label,
        removable: true,
        removeLabel: '${MaterialLocalizations.of(context).deleteButtonTooltip} $label',
      );
    }

    // Names, never ids (user 10-29: "兼容配件 #43475 这一串数字也看不懂").
    String categoryLabel(int id) {
      final name = marketCategoryName(context, c, id);
      return name == null
          ? marketText(context, 'filterCategoryUnnamed')
          : marketTextN(context, 'filterCategory', name);
    }

    String relationLabel() {
      final name = marketKnownItemName(context, c, c.relatedId);
      if (name == null) return marketText(context, c.relation);
      return marketTextN(
        context,
        c.relation == 'blueprints' ? 'filterBlueprints' : 'filterAttachments',
        name,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            marketTextAction(
              key: const Key('market-catalog-back'),
              onPressed: c.back,
              child: Text(marketBackText(context, c)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                marketText(context, 'results') +
                    (read?.total == null
                        ? ''
                        : ' · ${marketMoney(read!.total)}'),
              ),
            ),
            StarBridgeNativeIconAction(
              key: const Key('market-catalog-refresh'),
              label: marketText(context, 'refresh'),
              onActivate: (_) => c.refreshCatalog(),
              icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (c.hasCatalog) StarBridgeRemovableChipGroup(
              key: const Key('market-catalog-filters'),
              chips: [
                if (c.keyword.isNotEmpty) filter('keyword', c.keyword),
                if (c.categoryId != null)
                  filter('category', categoryLabel(c.categoryId!)),
                if (c.relation.isNotEmpty)
                  filter('relation', relationLabel()),
              ],
              onRemove: (id, _) {
                if (id == 'keyword') {
                  c.browse(category: c.categoryId);
                } else if (id == 'category') {
                  c.browse(query: c.keyword);
                } else if (id == 'relation') {
                  c.hall();
                }
              },
            ),
            marketTextAction(
              key: const Key('market-catalog-clear'),
              onPressed: c.hall,
              child: Text(marketText(context, 'clearFilters')),
            ),
            for (final mode in ['cards', 'rows'])
              StarBridgeChoiceChip(
                key: ValueKey('market-catalog-layout-$mode'),
                label: marketText(context, mode),
                selected: c.layout == mode,
                onSelected: (_) => c.setLayout(mode),
              ),
          ],
        ),
        if (c.relation == 'blueprints')
          Text(marketText(context, 'blueprintCoverage')),
        if (marketAttachmentConditions(context, c, read).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(marketAttachmentConditions(context, c, read)),
          ),
        Expanded(
          child: block(
            'catalog',
            (value) => value.data['missing'] is String
                ? MarketNotice(
                    marketText(context, value.data['missing'] as String),
                  )
                : value.rows.isEmpty
                ? MarketNotice(marketText(context, 'empty'))
                : LayoutBuilder(
                    builder: (context, constraints) => MarketPrefetch(
                      read: value,
                      loading: c.loading.contains('catalog'),
                      failed: c.failures.contains('catalog'),
                      load: c.moreCatalog,
                      child: CustomScrollView(
                        key: PageStorageKey((
                          'catalog',
                          c.categoryId,
                          c.keyword,
                          c.relation,
                          c.relatedId,
                          c.layout,
                        )),
                        slivers: [
                          if (c.layout == 'rows' || c.relation == 'blueprints')
                            SliverList.builder(
                              itemCount: value.rows.length,
                              itemBuilder: (_, i) {
                                final row = value.rows[i];
                                final blueprint = c.relation == 'blueprints';
                                final name = blueprint
                                    ? (row[marketLocale(context) == 'en'
                                                  ? 'blueprintName'
                                                  : marketLocale(context) ==
                                                        'hant'
                                                  ? 'blueprintNameCnHant'
                                                  : 'blueprintNameCn'] ??
                                              row['blueprintName'] ??
                                              '')
                                          .toString()
                                    : marketName(row, marketLocale(context));
                                final tile = ListTile(
                                    leading: SizedBox.square(
                                      dimension: 44,
                                      child: MarketArt.of(row),
                                    ),
                                    title: Text(name),
                                );
                                return Material(
                                  color: Colors.transparent,
                                  child: blueprint || marketItemId(row) == null
                                      ? tile
                                      : StarBridgeActionRow(
                                          inheritContentStyle: true,
                                          semanticLabel: name,
                                          onActivate: (_, _) => c.openItem(marketItemId(row)!),
                                          child: ExcludeSemantics(child: tile),
                                        ),
                                );
                              },
                            )
                          else
                            SliverGrid.builder(
                              itemCount: value.rows.length,
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 260,
                                    mainAxisExtent: 260,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                  ),
                              itemBuilder: (_, i) => MarketCatalogCard(
                                value.rows[i],
                                open: () =>
                                    c.openItem(marketItemId(value.rows[i])!),
                                drawer: (drawer) => marketCatalogDrawer(
                                  drawer,
                                  context,
                                  c,
                                  value.rows[i],
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: MarketPageStatus(
                              read: value,
                              loading: c.loading.contains('catalog'),
                              failed: c.failures.contains('catalog'),
                              load: c.moreCatalog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            c.refreshCatalog,
          ),
        ),
      ],
    );
  }
