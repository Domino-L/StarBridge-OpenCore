import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'tools_style.dart';
import 'catalog_controller.dart';
import 'catalog_port.dart';
import 'catalog_names.dart';
import 'mission_records_controller.dart';
import 'mission_records_widgets.dart';

/// SCM's numeric grade contract is 1=A, 2=B, 3=C, 4=D.
String catalogGrade(Object? value) => switch (value?.toString()) {
  '1' || 'A' => 'A',
  '2' || 'B' => 'B',
  '3' || 'C' => 'C',
  '4' || 'D' => 'D',
  _ => '—',
};

Color catalogGradeColor(BuildContext context, Object? value) =>
    switch (catalogGrade(value)) {
      'A' => context.tokens.colors.warning,
      'B' => context.tokens.colors.accent,
      _ => context.tokens.colors.textSecondary,
    };
String catalogDuration(AppStrings strings, Object? seconds) {
  final n = seconds is num ? seconds.toInt() : int.tryParse('$seconds');
  if (n == null || n < 0) return '—';
  final m = strings.text('catalog.minutes'),
      s = strings.text('catalog.seconds');
  return n >= 60 ? '${n ~/ 60} $m ${n % 60} $s' : '$n $s';
}

class CatalogTableHeader extends StatelessWidget {
  const CatalogTableHeader(this.kind, {super.key});
  final CatalogKind kind;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Row(
      children: [
        for (final (field, flex) in const [
          ('contracts', 5),
          ('type', 2),
          ('reward', 3),
          ('blueprintCount', 2),
          ('terminalRecords', 4),
        ])
          Expanded(
            flex: flex,
            child: Text(
              AppStrings.of(context).text('catalog.$field'),
              style: TextStyle(
                fontSize: 12,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );
}

class CatalogTableRow extends StatelessWidget {
  const CatalogTableRow({
    super.key,
    required this.controller,
    required this.row,
    required this.records,
    this.compact = false,
  });
  final CatalogController controller;
  final CatalogRow row;
  final MissionRecordsController records;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens, strings = AppStrings.of(context);
    final id = row['missionGuid'];
    final selected = id?.toString() == controller.selectedKey;
    final group = records.forDefinition(id);
    final type = catalogMissionType(row, strings.locale);
    final issuer = catalogName(row, strings.locale.languageCode, 'issuerName');
    final faction = catalogName(
      row,
      strings.locale.languageCode,
      'factionName',
    );
    final owner = faction == '—' ? issuer : faction;
    final system = (row['systems'] as List?)?.join(' · ') ?? '—';
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          catalogName(row, strings.locale.languageCode, 'title'),
          maxLines: compact ? null : 2,
          overflow: compact ? null : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          compact ? '$type · $owner · $system' : '$owner · $system',
          maxLines: compact ? null : 1,
          overflow: compact ? null : TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
        ),
      ],
    );
    final blueprints = row['blueprintRewardCount'] as num?;
    final blueprintBadge = ToolsTag(
      '${strings.text('catalog.blueprintCount')} ${blueprints ?? '—'}',
      color: (blueprints ?? 0) > 0 ? t.colors.accent : t.colors.textSecondary,
    );
    return Container(
      decoration: BoxDecoration(
        color: selected ? t.colors.accent.withValues(alpha: .08) : null,
        border: Border(
          top: BorderSide(color: marketLine(context)),
          left: BorderSide(
            width: 3,
            color: selected
                ? t.colors.accent
                : row['illegal'] == true
                ? t.colors.danger
                : group != null
                ? t.colors.success.withValues(alpha: .35)
                : marketLine(context),
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('catalog-row-$id'),
          onTap: id == null ? null : () => controller.select(id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 57),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MarketPrice(row['rewardUec'], unit: 'aUEC'),
                            Text(
                              '${strings.text('catalog.xp')} ${row['baseXp'] ?? '—'}',
                            ),
                            blueprintBadge,
                            if (row['illegal'] == true)
                              ToolsTag(
                                strings.text('catalog.illegal'),
                                color: t.colors.danger,
                              ),
                            if (group != null) MissionRecordBadge(group),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 5, child: title),
                        Expanded(
                          flex: 2,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              ToolsTag(type),
                              if (row['illegal'] == true)
                                ToolsTag(
                                  strings.text('catalog.illegal'),
                                  color: t.colors.danger,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: MarketPrice(row['rewardUec'], unit: 'aUEC'),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: blueprintBadge,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            group == null
                                ? '—'
                                : missionRecordLabel(strings, group),
                            key: group == null
                                ? null
                                : const Key('mission-record-badge'),
                            style: toolNumber(
                              context,
                              size: 12,
                              color: group == null
                                  ? t.colors.textSecondary
                                  : t.colors.textPrimary,
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
