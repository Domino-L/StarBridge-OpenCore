import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'catalog_controller.dart';
import 'catalog_details.dart';
import 'catalog_port.dart';
import 'catalog_names.dart';
import 'catalog_table.dart';
import 'tools_style.dart';

class CatalogBlueprintCard extends StatelessWidget {
  const CatalogBlueprintCard({
    required this.controller,
    required this.row,
    super.key,
  });
  final CatalogController controller;
  final CatalogRow row;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context), t = context.tokens;
    final title = catalogBlueprintTitle(row, strings.locale);
    final selected = row['id']?.toString() == controller.selectedKey;
    return MarketSurface(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('catalog-row-${row['id']}'),
          onTap: row['id'] == null ? null : () => controller.select(row['id']!),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 3,
                  color: selected ? t.colors.accent : Colors.transparent,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // In the fixed-height grid cell the picture gives up height
                  // when a long name or wrapped meta needs it; in the narrow
                  // list (unbounded height) it keeps its full size.
                  if (constraints.hasBoundedHeight)
                    Flexible(
                      child: SizedBox(height: 134, child: CatalogImage(row)),
                    )
                  else
                    SizedBox(height: 134, child: CatalogImage(row)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (title.size case final size?) ...[
                              const SizedBox(width: 6),
                              ToolsTag(size),
                            ],
                            const SizedBox(width: 6),
                            ToolsTag(
                              catalogGrade(row['grade']),
                              color: catalogGradeColor(context, row['grade']),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            catalogCategoryName(strings, row['categoryName']),
                            ?catalogBlueprintKind(
                              row['manufacturer'],
                              strings.locale,
                            ),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: t.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              catalogDuration(strings, row['craftTimeSeconds']),
                              style: toolNumber(context, size: 14),
                            ),
                            Text(
                              '${strings.text('catalog.sources')} ${row['rewardMissionCount'] ?? '—'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: t.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
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
