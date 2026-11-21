import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'tools_style.dart';
import 'catalog_table.dart';

import 'catalog_controller.dart';
import 'catalog_port.dart';
import 'catalog_names.dart';
import 'catalog_blueprint_categories.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters(this.controller, {super.key, this.showHeading = true});
  final CatalogController controller;
  final bool showHeading;
  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _expanded = <String>{};
  String _scope = '';
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, strings = AppStrings.of(context);
    final scope =
        '${c.kind}:${c.options['categoryName']}:${c.options['subcategory']}';
    if (scope != _scope) {
      _expanded.clear();
      _scope = scope;
    }
    final locale = strings.locale.languageCode;
    String t(String key) => strings.text('catalog.$key');
    Widget chips(
      String title,
      String field,
      List<String> values, {
      String Function(String)? label,
      bool limited = false,
    }) => Padding(
      key: Key('catalog-filter-$field'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(title),
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
          const SizedBox(height: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolsOption(
                key: Key('catalog-filter-$field-all'),
                label: t('all'),
                selected: c.options[field] == null,
                onTap: () => c.filter(field, null),
              ),
              for (final value
                  in limited && !_expanded.contains(field)
                      ? values.take(8)
                      : values)
                ToolsOption(
                  key: Key('catalog-filter-$field-$value'),
                  label: label?.call(value) ?? value,
                  selected: c.options[field] == value,
                  onTap: () =>
                      c.filter(field, c.options[field] == value ? null : value),
                ),
              if (limited && values.length > 8 && !_expanded.contains(field))
                ToolsOption(
                  key: Key('catalog-filter-$field-more'),
                  label: '${t('more')} (${values.length - 8})',
                  selected: false,
                  onTap: () => setState(() => _expanded.add(field)),
                ),
            ],
          ),
        ],
      ),
    );
    Widget counted(String title, String field, String source) {
      final rows = catalogRows(c.filters[source])
          .where(
            (r) =>
                r['value'] is String &&
                (r['value'] as String).trim().isNotEmpty,
          )
          .toList();
      rows.sort((a, b) {
        final count = ((b['missionCount'] as num?) ?? 0).compareTo(
          (a['missionCount'] as num?) ?? 0,
        );
        return count != 0 ? count : '${a['value']}'.compareTo('${b['value']}');
      });
      if (rows.isEmpty) return const SizedBox.shrink();
      return chips(
        title,
        field,
        rows.map((r) => r['value']! as String).toList(),
        limited: true,
        label: (value) {
          final row = rows.firstWhere((r) => r['value'] == value);
          final label = catalogName(row, locale, 'label');
          return row['missionCount'] == null
              ? label
              : '$label (${row['missionCount']})';
        },
      );
    }

    List<String> values(String field) =>
        (c.filters[field] as List?)
            ?.whereType<String>()
            .where((v) => v.trim().isNotEmpty)
            .toList() ??
        [];
    Widget check(String key, String field, {bool inverse = false}) =>
        ToolsOption(
          label: t(key),
          selected: c.options[field] == !inverse,
          onTap: () =>
              c.filter(field, c.options[field] == !inverse ? null : !inverse),
        );
    final types =
        (c.filters['missionTypes'] as List?)?.whereType<String>().toList() ??
        [];
    final typeOptions = catalogRows(c.filters['missionTypeOptions']);
    final category = c.options['categoryName'] as String?;
    final subcategories =
        catalogBlueprintSubcategories[category] ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeading)
          Text(t('filters'), style: Theme.of(context).textTheme.titleSmall),
        if (c.kind == CatalogKind.missions) ...[
          chips(
            'type',
            'missionType',
            {
              ...types,
              ...typeOptions.map((r) => r['value']).whereType<String>(),
            }.toList(),
            label: (value) {
              final option = typeOptions
                  .where((row) => row['value'] == value)
                  .firstOrNull;
              final cn = option?['labelCn']?.toString().trim() ?? '';
              if (locale != 'en' && cn.isNotEmpty) return cn;
              return catalogMissionTypeLabel(
                value,
                strings.locale,
                fallback: option?['label']?.toString(),
              );
            },
          ),
          counted('category', 'category', 'categories'),
          counted('faction', 'faction', 'factions'),
          counted('issuer', 'issuer', 'issuers'),
          chips(
            'system',
            'system',
            (c.filters['systems'] as List?)?.whereType<String>().toList() ?? [],
          ),
          const SizedBox(height: 12),
          check('blueprintOnly', 'hasBlueprintRewards'),
          check('sharedOnly', 'canBeShared'),
          check('legalOnly', 'illegal', inverse: true),
          const SizedBox(height: 12),
          Text(
            t('sort'),
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in {
                'rewardUec': 'sortReward',
                'title': 'sortName',
                'baseXp': 'sortXp',
              }.entries)
                ToolsOption(
                  label: t(entry.value),
                  selected:
                      (c.options['sortField'] ?? 'rewardUec') == entry.key,
                  onTap: entry.key == 'baseXp' ? null : () => c.sort(entry.key),
                ),
            ],
          ),
        ] else ...[
          chips(
            'category',
            'categoryName',
            catalogBlueprintCategories,
            label: (value) => strings.text('catalog.$value') == 'catalog.$value'
                ? value
                : t(value),
          ),
          if (category != null) ...[
            if (subcategories.isNotEmpty)
              chips(
                'subcategory',
                'subcategory',
                subcategories,
                label: (value) => t('sub.$category.$value'),
              ),
            if (values('manufacturers').isNotEmpty)
              chips(
                'kind',
                'manufacturer',
                values('manufacturers'),
                limited: true,
                label: (value) =>
                    catalogBlueprintKindLabel(value, strings.locale),
              ),
            if (values('itemClasses').isNotEmpty)
              chips(
                'itemClass',
                'itemClass',
                values('itemClasses'),
                limited: true,
                label: (value) => catalogItemClass(strings, value),
              ),
          ],
          chips(
            'grade',
            'grade',
            (c.filters['grades'] as List?)?.map((v) => v.toString()).toList() ??
                [],
            label: catalogGrade,
          ),
          if (category != null) ...[
            const SizedBox(height: 12),
            check('rewardOnly', 'isReward'),
          ],
        ],
      ],
    );
  }
}
