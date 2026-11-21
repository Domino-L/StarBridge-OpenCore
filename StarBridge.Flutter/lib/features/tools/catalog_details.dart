import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'tools_style.dart';
import '../../shared/remote_image.dart';
import 'catalog_controller.dart';
import 'catalog_port.dart';
import 'catalog_names.dart';
import 'mission_records_controller.dart';
import 'mission_records_widgets.dart';
import 'catalog_table.dart';
import 'catalog_blueprint_categories.dart';
import 'catalog_detail_values.dart';

String catalogCategoryName(AppStrings strings, Object? value) {
  final raw = value?.toString() ?? '—';
  final label = strings.text('catalog.$raw');
  return label == 'catalog.$raw' ? raw : label;
}

String catalogChance(Object? value) {
  final chance = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (chance == null || !chance.isFinite || chance < 0 || chance > 1) {
    return '—';
  }
  return '${(chance * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}%';
}

int catalogArtCategory(Object? category) => switch (category) {
  'FPSArmours' => 5,
  'FPSWeapons' => 3,
  'Ammo' => 4,
  'Components' || 'ShipWeapons' => 1,
  _ => 0,
};

class CatalogImage extends StatelessWidget {
  const CatalogImage(this.row, {super.key, this.large = false});
  final CatalogRow row;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final fallback = KeyedSubtree(
      key: const Key('catalog-image-placeholder'),
      child: MarketArt(null, category: catalogArtCategory(row['categoryName'])),
    );
    final source =
        (large
                ? row['thumbnailUrlHd'] ?? row['thumbnailUrl']
                : row['thumbnailUrl'])
            ?.toString() ??
        '';
    return AspectRatio(
      aspectRatio: large ? 1.5 : 1.2,
      child: source.isEmpty
          ? fallback
          : RemoteImage(
              source,
              fit: BoxFit.contain,
              followRedirects: false,
              semanticLabel: AppStrings.of(context).text('catalog.image'),
              errorBuilder: (_, error, stack) => fallback,
              loadingBuilder: (_) => fallback,
            ),
    );
  }
}

class CatalogDetails extends StatelessWidget {
  const CatalogDetails(
    this.controller, {
    super.key,
    required this.onCrossLink,
    this.records,
    this.framed = true,
  });
  final MissionRecordsController? records;
  final bool framed;
  final CatalogController controller;
  final void Function(CatalogKind kind, Object selection) onCrossLink;
  @override
  Widget build(BuildContext context) {
    final c = controller, row = c.detail;
    final palette = context.tokens;
    final strings = AppStrings.of(context),
        locale = AppStrings.of(context).locale.languageCode;
    String t(String key) => strings.text('catalog.$key');
    String name(CatalogRow r, String field) => catalogName(r, locale, field);
    String text(String key) => row[key]?.toString() ?? '—';
    String category(CatalogRow r) {
      final value = r['categoryName']?.toString() ?? '—';
      final translated = t(value);
      return translated == 'catalog.$value' ? value : translated;
    }

    Widget section(String title, List<Widget> children) => children.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ToolsRule(),
              Text(
                t(title),
                style: TextStyle(
                  color: palette.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          );
    Widget kv(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(t(label), style: TextStyle(color: palette.colors.textSecondary)),
          Text(value),
        ],
      ),
    );
    String duration(Object? seconds) {
      final n = seconds is num
          ? seconds.toInt()
          : int.tryParse(seconds?.toString() ?? '');
      if (n == null || n < 0) return '—';
      return n >= 60
          ? '${n ~/ 60} ${t('minutes')} ${n % 60} ${t('seconds')}'
          : '$n ${t('seconds')}';
    }

    Widget link(
      CatalogRow r,
      CatalogKind target,
      Object? selection,
      String title,
      String subtitle,
    ) {
      final chance = catalogChance(
        r[target == CatalogKind.blueprints ? 'chance' : 'rewardChance'],
      );
      final info = subtitle.split(' · ${t('chance')}').first;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('catalog-link-${target.name}-$selection'),
          onTap: selection == null
              ? null
              : () => onCrossLink(target, selection),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.colors.textPrimary,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        info,
                        style: TextStyle(
                          color: palette.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  chance,
                  style: toolNumber(
                    context,
                    size: 16,
                    color: palette.colors.warning,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (row.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t('select')),
      );
    }
    final mission = c.kind == CatalogKind.missions;
    final blueprintTitle = mission
        ? null
        : catalogBlueprintTitle(row, strings.locale);
    final title = blueprintTitle?.name ?? name(row, 'title');
    final enTitle = row[mission ? 'title' : 'blueprintName']?.toString() ?? '';
    final difficulty = catalogDifficulty(row['difficulty'], locale);
    final minimum = catalogStanding(row['minStanding'], strings);
    final maximum = catalogStanding(row['maxStanding'], strings);
    final faction = catalogOptionalName(row, locale, 'factionName');
    final destinations = catalogRows(row['destinations'])
        .map((r) => catalogOptionalName(r, locale, 'name'))
        .where((v) => v.isNotEmpty)
        .toList();
    final encounters = catalogEncounterNames(row['shipEncounters'], locale);
    final rewards = catalogRewardNames(row['itemRewards'], locale);
    final stats = catalogStats(row);
    final subcategory = catalogSubcategory(
      strings,
      row['categoryName'],
      row['subcategory'],
    );
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('catalog-detail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mission) ...[
            CatalogImage(row, large: true),
            const SizedBox(height: 12),
          ],
          Text(
            mission
                ? '${catalogMissionType(row, strings.locale)} · ${name(row, 'issuerName')}'
                : [
                    category(row),
                    if (subcategory.isNotEmpty) subcategory,
                  ].join(' · '),
            style: TextStyle(fontSize: 12, color: palette.colors.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (blueprintTitle?.size case final size?) ...[
                const SizedBox(width: 8),
                ToolsTag(size),
              ],
            ],
          ),
          if (enTitle.isNotEmpty && enTitle != title)
            Text(
              enTitle,
              style: TextStyle(
                color: palette.colors.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),
          const ToolsRule(),
          Wrap(
            spacing: 26,
            runSpacing: 8,
            children: mission
                ? [
                    if (row['rewardUec'] != null)
                      ToolsStat(
                        '${t('reward')} aUEC',
                        text('rewardUec'),
                        size: 34,
                      ),
                    if (row['baseXp'] != null)
                      ToolsStat(t('xp'), text('baseXp'), size: 24),
                    if (row['timeToComplete'] case final num n when n > 0)
                      ToolsStat(t('timeLimit'), switch (row['timeToComplete']) {
                        final num minutes when minutes > 0 =>
                          '${minutes.round()} ${t('minutes')}',
                        _ => '—',
                      }, size: 24),
                  ]
                : [
                    if (row['grade'] != null)
                      ToolsStat(
                        t('grade'),
                        catalogGrade(row['grade']),
                        size: 34,
                        color: catalogGradeColor(context, row['grade']),
                      ),
                    if (row['craftTimeSeconds'] != null)
                      ToolsStat(
                        t('craftTime'),
                        duration(row['craftTimeSeconds']),
                        size: 24,
                      ),
                  ],
          ),
          const ToolsRule(),
          if (mission) ...[
            if ((row['systems'] as List?)?.isNotEmpty == true)
              kv('system', (row['systems'] as List).join(' · ')),
            if (catalogRows(row['locations']).isNotEmpty)
              kv(
                'locations',
                catalogRows(row['locations'])
                    .map((r) => name(r, 'name'))
                    .join(' · '),
              ),
            if (faction.isNotEmpty) kv('faction', faction),
            if ([
              row['canBeShared'],
              row['illegal'],
              row['onceOnly'],
            ].contains(true))
              kv(
                'other',
                [
                      if (row['canBeShared'] == true) t('sharedOnly'),
                      if (row['illegal'] == true) t('illegal'),
                      if (row['onceOnly'] == true) t('onceOnly'),
                    ].join(' · ').isEmpty
                    ? '—'
                    : [
                        if (row['canBeShared'] == true) t('sharedOnly'),
                        if (row['illegal'] == true) t('illegal'),
                        if (row['onceOnly'] == true) t('onceOnly'),
                      ].join(' · '),
              ),
            section('rewardBlueprints', [
              for (final blueprint in catalogRows(row['rewardBlueprints']))
                link(
                  blueprint,
                  CatalogKind.blueprints,
                  blueprint['id'],
                  name(blueprint, 'name'),
                  '${category(blueprint)} · ${t('chance')} ${catalogChance(blueprint['chance'])}',
                ),
            ]),
            if (records?.visible == true && records?.loaded == true)
              MissionRecordDetails(records!.forDefinition(row['missionGuid'])),
            section('requirements', [
              if (difficulty.isNotEmpty) kv('difficulty', difficulty),
              if (minimum.isNotEmpty) kv('minStanding', minimum),
              if (maximum.isNotEmpty) kv('maxStanding', maximum),
              if (row['minRankIndex'] != null || row['maxRankIndex'] != null)
                kv(
                  'rank',
                  [
                    row['minRankIndex'],
                    row['maxRankIndex'],
                  ].whereType<num>().join(' – '),
                ),
              if (row['cargoMinScu'] != null || row['cargoMaxScu'] != null)
                kv(
                  'cargo',
                  '${[row['cargoMinScu'], row['cargoMaxScu']].whereType<num>().join(' – ')} SCU',
                ),
              if (row['buyIn'] != null) kv('buyIn', '${text('buyIn')} aUEC'),
              if (row['cargoPickupCount'] != null)
                kv('cargoPickupCount', text('cargoPickupCount')),
              if (row['cargoDropoffCount'] != null)
                kv('cargoDropoffCount', text('cargoDropoffCount')),
              for (final prerequisite in catalogRows(
                row['prerequisiteContracts'],
              ))
                kv(
                  'prerequisites',
                  name(
                    prerequisite,
                    prerequisite.containsKey('title') ? 'title' : 'name',
                  ),
                ),
            ]),
            section('destinations', [
              for (final value in destinations) Text(value),
            ]),
            section('shipEncounters', [
              for (final value in encounters) Text(value),
            ]),
            section('itemRewards', [for (final value in rewards) Text(value)]),
            if (name(row, 'description') != '—')
              section('description', [Text(name(row, 'description'))]),
          ] else ...[
            if (catalogBlueprintKind(row['manufacturer'], strings.locale)
                case final kind?)
              kv('kind', kind),
            if (row['itemClass']?.toString().trim().isNotEmpty == true)
              kv('itemClass', catalogItemClass(strings, text('itemClass'))),
            if (stats.isNotEmpty)
              section('stats', [
                for (final entry in stats.entries)
                  kv('stat.${entry.key}', entry.value),
              ]),
            section('materials', [
              for (final slot in catalogRows(row['slots'])) ...[
                Text(
                  '${name(slot, 'slotDisplayName')} ×${slot['requiredCount'] ?? '—'}',
                ),
                for (final material in catalogRows(slot['options']))
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${name(material, 'materialName')} ×${material['materialType'] == 'resource' ? '${material['standardCargoUnits'] ?? '—'} SCU' : material['quantity'] ?? '—'}'
                          '${material['minQuality'] == null ? '' : ' · ${t('quality')} ${material['minQuality']}'}',
                        ),
                        if (material['minQuality'] case final num quality)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: LinearProgressIndicator(
                              key: Key(
                                'catalog-quality-${material['materialName']}',
                              ),
                              value: quality.clamp(0, 1000) / 1000,
                              minHeight: 3,
                              color: palette.colors.accent,
                              backgroundColor: marketLine(context),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ]),
            section('sources', [
              if (c.sources.isEmpty)
                Text(
                  c.sourcesLoading
                      ? '…'
                      : c.sourcesKnown
                      ? t('none')
                      : '—',
                ),
              for (final source in c.sources)
                link(
                  source,
                  CatalogKind.missions,
                  source['missionGuid'],
                  name(source, 'title'),
                  '${catalogMissionType(source, strings.locale)} · ${t('chance')} ${catalogChance(source['rewardChance'])}',
                ),
            ]),
          ],
          if (c.port.canOpenWebsite) ...[
            const SizedBox(height: 16),
            ToolsAction(
              key: const Key('catalog-open-website'),
              onPressed: c.openWebsite,
              label: t('openScm'),
            ),
          ],
        ],
      ),
    );
    return framed
        ? MarketSurface(padding: EdgeInsets.zero, child: content)
        : content;
  }
}
