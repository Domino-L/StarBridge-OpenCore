import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'tools_style.dart';

import 'catalog_port.dart';
import 'mission_records_controller.dart';
import 'mission_records_widgets.dart';

/// Resolves names only from data already on screen or one user-demanded detail.
class MissionRecordsPage extends StatefulWidget {
  const MissionRecordsPage({
    super.key,
    required this.controller,
    required this.catalog,
    required this.known,
  });
  final MissionRecordsController controller;
  final CatalogPort catalog;
  final List<CatalogRow> known;
  @override
  State<MissionRecordsPage> createState() => _MissionRecordsPageState();
}

class _MissionRecordsPageState extends State<MissionRecordsPage> {
  MissionRecordsSort _sort = MissionRecordsSort.count;
  final _resolved = <String, CatalogRow?>{};
  bool _opening = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    // A port retirement clears every account-derived name and pending intent.
    if (!widget.controller.loaded) {
      _epoch++;
      _resolved.clear();
      _opening = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  CatalogRow? _known(MissionRecordGroup group) {
    final guid = group.definitionId?.toLowerCase();
    if (guid == null) return null;
    for (final row in widget.known) {
      if (row['missionGuid']?.toString().toLowerCase() == guid) return row;
    }
    return _resolved[group.key];
  }

  Future<void> _open(MissionRecordGroup group) async {
    final guid = group.definitionId;
    if (_opening || guid == null || !widget.controller.visible) return;
    final epoch = _epoch;
    setState(() => _opening = true);
    try {
      CatalogRow? detail;
      if (_resolved.containsKey(group.key)) {
        detail = _resolved[group.key];
      } else {
        try {
          final response = await widget.catalog.read('missions.detail', {
            'guid': guid,
          });
          if (response['missionGuid']?.toString().toLowerCase() ==
              guid.toLowerCase()) {
            detail = response;
          }
        } catch (_) {
          // Unknown contracts retain their original log code without an error.
        }
        if (!mounted || epoch != _epoch || !widget.controller.visible) return;
        _resolved[group.key] = detail;
      }
      if (!mounted || epoch != _epoch || !widget.controller.visible) return;
      if (detail != null) Navigator.of(context).pop(detail);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, strings = AppStrings.of(context);
    String t(String key) => missionRecordText(strings, key);
    final groups = sortedMissionRecords(c.groups, _sort);
    return Scaffold(
      body: ToolsSurface(
        child: SafeArea(
          child: ListView(
            key: const Key('mission-record-list'),
            padding: const EdgeInsets.all(12),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('‹ ${strings.text('catalog.back')}'),
                ),
              ),
              LayoutBuilder(
                builder: (context, box) =>
                    box.maxWidth < 500 &&
                        MediaQuery.textScalerOf(context).scale(1) > 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t('title'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const ToolsRule(),
                        ],
                      )
                    : MarketSectionHeading(t('title')),
              ),
              if (c.visible) ...[
                const SizedBox(height: 12),
                MissionRecordsImport(c),
                const SizedBox(height: 12),
                DropdownButtonFormField<MissionRecordsSort>(
                  key: const Key('mission-record-sort'),
                  initialValue: _sort,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(labelText: t('sort')),
                  items: [
                    for (final sort in MissionRecordsSort.values)
                      DropdownMenuItem(
                        value: sort,
                        child: Text(t('sort.${sort.name}')),
                      ),
                  ],
                  onChanged: (sort) {
                    if (sort != null) setState(() => _sort = sort);
                  },
                ),
                const SizedBox(height: 12),
                if (c.loading || _opening) const LinearProgressIndicator(),
                if (c.loaded && groups.isEmpty)
                  Text(t('empty'), key: const Key('mission-record-empty')),
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: MarketSurface(
                      padding: EdgeInsets.zero,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('mission-record-row-${group.key}'),
                          onTap: _opening ? null : () => _open(group),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(
                              builder: (context) {
                                final known = _known(group);
                                final name = known == null
                                    ? (group.contractCode ??
                                          group.definitionId ??
                                          group.key)
                                    : catalogName(
                                        known,
                                        strings.locale.languageCode,
                                        'title',
                                      );
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: known == null
                                          ? TextStyle(
                                              fontFamily: context
                                                  .tokens
                                                  .typography
                                                  .monoFamily,
                                            )
                                          : Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                    ),
                                    MissionRecordBadge(group),
                                    Text(
                                      '${t('last')}: ${missionRecordDate(context, group.lastCompletedAt)}',
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
