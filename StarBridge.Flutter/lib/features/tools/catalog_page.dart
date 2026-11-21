import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import 'tools_style.dart';
import 'catalog_controller.dart';
import 'catalog_search.dart';
import 'catalog_blueprint_grid.dart';
import '../common/organization_workspace_frame.dart';
import '../common/organization_holo.dart';
import 'catalog_details.dart';
import 'catalog_filters.dart';
import 'catalog_port.dart';
import 'catalog_recent.dart';
import 'catalog_table.dart';
import 'mission_records_port.dart';
import 'mission_records_controller.dart';
import 'mission_records_page.dart';
import 'mission_records_widgets.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.kind,
    required this.port,
    this.selection,
    this.recordsPort,
    this.onBack,
    this.recent,
  });
  final CatalogKind kind;
  final CatalogPort port;
  final MissionRecordsPort? recordsPort;
  final Object? selection;
  final VoidCallback? onBack;
  final CatalogRecent? recent;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final CatalogController c;
  late final MissionRecordsController records;
  bool _narrow = false;
  @override
  void initState() {
    super.initState();
    c = CatalogController(
      widget.kind,
      widget.port,
      onViewed: (row) => widget.recent?.view(widget.kind, row),
    );
    records = MissionRecordsController(
      widget.kind == CatalogKind.missions ? widget.recordsPort : null,
      onImported: () {
        unawaited(widget.recent?.imported(DateTime.now()));
      },
    );
    if (widget.kind == CatalogKind.missions) unawaited(records.load());
    unawaited(c.start(widget.selection));
    unawaited(_prepareRecent());
  }

  Future<void> _prepareRecent() async {
    try {
      await widget.recent?.prepare?.call();
    } catch (_) {
      // History is optional; account resolution must not block the catalogue.
    }
  }

  @override
  void dispose() {
    records.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> _cross(CatalogKind kind, [Object? selection]) async {
    c.setVisible(false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/tools/${kind.name}'),
        builder: (context) => Scaffold(
          body: SafeArea(
            child: CatalogPage(
              kind: kind,
              port: widget.port,
              selection: selection,
              recordsPort: widget.recordsPort,
              recent: widget.recent,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
    if (mounted) c.setVisible(true);
  }

  Future<void> _openRecords() async {
    c.setVisible(false);
    final detail = await Navigator.of(context).push<CatalogRow>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/tools/missions/records'),
        builder: (_) => MissionRecordsPage(
          controller: records,
          catalog: widget.port,
          known: [...c.rows, if (c.detail.isNotEmpty) c.detail],
        ),
      ),
    );
    if (!mounted) return;
    c.setVisible(true);
    if (detail != null && records.visible) c.showResolvedDetail(detail);
  }

  void _back() {
    if (_narrow &&
        (c.hasDetail || c.detailLoading) &&
        widget.selection == null) {
      c.closeDetail();
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Actions.invoke(context, const OpenDestinationIntent('/tools'));
    }
  }

  @override
  Widget build(BuildContext context) => ToolsSurface(
    child: ListenableBuilder(
      listenable: Listenable.merge([c, records]),
      builder: (context, _) {
        final strings = AppStrings.of(context), p = context.tokens;
        String t(String key) => strings.text('catalog.$key');
        final mission = widget.kind == CatalogKind.missions;
        final cross = mission ? CatalogKind.blueprints : CatalogKind.missions;
        return LayoutBuilder(
          builder: (context, constraints) {
            _narrow = constraints.maxWidth < 1050;
            final detailMode = _narrow && (c.hasDetail || c.detailLoading);
            final top = <Widget>[
              if (detailMode)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          key: const Key('catalog-back'),
                          onPressed: _back,
                          child: Text('‹ ${t('back')}'),
                        ),
                        ToolsAction(
                          key: const Key('catalog-refresh'),
                          outlined: true,
                          onPressed: c.loading ? null : c.refresh,
                          label: t('refresh'),
                        ),
                      ],
                    ),
                    Text(
                      t(widget.kind.name),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 20,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          key: const Key('catalog-back'),
                          onPressed: _back,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: p.colors.accent,
                          ),
                          child: Text(
                            '${strings.text('navigation.tools')} / ${t(widget.kind.name)}',
                          ),
                        ),
                        Text(
                          t(widget.kind.name),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings.text(
                            'terminal.${mission ? 'missionsDescription' : 'blueprintsDescription'}',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: p.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    ToolsStat(
                      t('results'),
                      c.hasPageResult ? '${c.total}' : '—',
                      size: 20,
                    ),
                    if (mission && records.visible && records.loaded)
                      ToolsStat(
                        strings.text('terminal.completed'),
                        '${records.groups.fold<int>(0, (n, g) => n + g.count)}',
                        size: 20,
                        color: p.colors.stateAccent,
                      ),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        if (mission && records.visible)
                          ToolsAction(
                            key: const Key('mission-record-entry'),
                            outlined: true,
                            onPressed: _openRecords,
                            label: strings.text('missionRecords.entry'),
                          ),
                        if (mission)
                          MissionRecordsImport(records, inline: true),
                        ToolsAction(
                          key: const Key('catalog-other'),
                          outlined: true,
                          onPressed: () => _cross(cross),
                          label: t(mission ? 'toBlueprints' : 'toMissions'),
                        ),
                        ToolsAction(
                          key: const Key('catalog-refresh'),
                          outlined: true,
                          onPressed: c.loading ? null : c.refresh,
                          label: t('refresh'),
                        ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (mission && !detailMode)
                MissionRecordsImport(records, feedbackOnly: true),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      t(c.error!.limited ? 'limited' : 'error'),
                      key: const Key('catalog-error'),
                      style: TextStyle(color: p.colors.textSecondary),
                    ),
                  ),
                ),
              if (c.loading || c.detailLoading) const LinearProgressIndicator(),
            ];
            return PopScope(
              canPop: !(_narrow && c.hasDetail && widget.selection == null),
              onPopInvokedWithResult: (popped, result) {
                if (!popped) c.closeDetail();
              },
              child: Padding(
                padding: EdgeInsets.all(constraints.maxWidth < 500 ? 12 : 20),
                child: _narrow
                    ? ListView(
                        key: Key(
                          detailMode
                              ? 'catalog-detail-scroll'
                              : 'catalog-narrow',
                        ),
                        children: [
                          ...top,
                          if (detailMode)
                            CatalogDetails(
                              c,
                              onCrossLink: _cross,
                              records: records,
                            )
                          else
                            ..._narrowList(context),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...top,
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: constraints.maxWidth >= 1250
                                      ? 236
                                      : 190,
                                  child: MarketSurface(
                                    child: SingleChildScrollView(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: CatalogFilters(c),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: mission
                                      ? OrganizationWorkspaceSurface(
                                          child: _results(context),
                                        )
                                      : MarketSurface(
                                          padding: const EdgeInsets.all(16),
                                          child: _results(context),
                                        ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: constraints.maxWidth >= 1250
                                      ? 372
                                      : 300,
                                  child: MarketSurface(
                                    padding: EdgeInsets.zero,
                                    child: SingleChildScrollView(
                                      key: const Key('catalog-detail-scroll'),
                                      child: CatalogDetails(
                                        c,
                                        onCrossLink: _cross,
                                        records: records,
                                        framed: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    ),
  );
  String _resultLabel(BuildContext context) {
    final s = AppStrings.of(context);
    return '${s.text('catalog.results')} ${c.total} ${s.text('catalog.${widget.kind == CatalogKind.missions ? 'contracts' : 'blueprintCount'}')}';
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        c.loading
            ? '…'
            : c.error != null && !c.hasPageResult
            ? ''
            : AppStrings.of(context).text(
                'catalog.${widget.kind == CatalogKind.missions ? 'emptyMissions' : 'emptyBlueprints'}',
              ),
        key: const Key('catalog-empty'),
      ),
    ),
  );
  List<Widget> _narrowList(BuildContext context) => [
    CatalogSearch(c),
    ExpansionTile(
      key: const Key('catalog-filter-expander'),
      title: Text(AppStrings.of(context).text('catalog.filters')),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: CatalogFilters(c, showHeading: false),
        ),
      ],
    ),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(_resultLabel(context)),
    ),
    if (c.rows.isEmpty)
      _empty(context)
    else ...[
      for (final row in c.rows)
        if (widget.kind == CatalogKind.blueprints)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CatalogBlueprintCard(controller: c, row: row),
          )
        else
          CatalogTableRow(
            controller: c,
            row: row,
            records: records,
            compact: true,
          ),
      _pager(context),
    ],
  ];
  Widget _results(BuildContext context) => widget.kind == CatalogKind.blueprints
      ? _blueprints(context)
      : LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.clamp(
              590.0 * MediaQuery.textScalerOf(context).scale(1),
              double.infinity,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _resultLabel(context),
                        style: toolNumber(context, size: 15),
                      ),
                    ),
                    CatalogSearch(c),
                    const SizedBox(height: 14),
                    CatalogTableHeader(widget.kind),
                    Expanded(
                      child: c.rows.isEmpty
                          ? _empty(context)
                          : ListView.builder(
                              key: const PageStorageKey('catalog-results'),
                              itemCount: c.rows.length,
                              itemBuilder: (context, index) => CatalogTableRow(
                                controller: c,
                                row: c.rows[index],
                                records: records,
                              ),
                            ),
                    ),
                    _pager(context),
                  ],
                ),
              ),
            );
          },
        );
  Widget _blueprints(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _resultLabel(context),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 10),
      CatalogSearch(c),
      const SizedBox(height: 14),
      Expanded(
        child: c.rows.isEmpty
            ? _empty(context)
            : GridView.builder(
                key: const PageStorageKey('catalog-results'),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent:
                      260 * MediaQuery.textScalerOf(context).scale(1),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: c.rows.length,
                itemBuilder: (context, index) =>
                    CatalogBlueprintCard(controller: c, row: c.rows[index]),
              ),
      ),
      _pager(context),
    ],
  );
  Widget _pager(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('catalog.$key');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          key: const Key('catalog-previous'),
          style: organizationHoloButton(context),
          onPressed: c.page <= 1 || c.loading ? null : () => c.go(c.page - 1),
          child: Text(t('previous')),
        ),
        Text(
          '${c.page} / ${c.pages}',
          key: const Key('catalog-page-number'),
          style: toolNumber(context, size: 17),
        ),
        TextButton(
          key: const Key('catalog-next'),
          style: organizationHoloButton(context),
          onPressed: c.page >= c.pages || c.loading
              ? null
              : () => c.go(c.page + 1),
          child: Text(t('next')),
        ),
      ],
    );
  }
}
