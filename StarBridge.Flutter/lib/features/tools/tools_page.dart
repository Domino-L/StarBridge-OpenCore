import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../marketplace/marketplace_hover.dart';
import 'tools_style.dart';
import 'catalog_details.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import 'cached_exec_hangar.dart';
import 'catalog_recent.dart';
import 'mission_records_controller.dart';
import 'mission_records_port.dart';
import 'tools_card_data.dart';
import 'tools_snapshot_cache.dart';

final class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.titleKey,
    required this.route,
  });
  final String id, titleKey, route;
}

/// The tools are one collection of equals (user 11-11): a new tool is one more
/// entry here and takes the next tile.
const toolEntries = [
  ToolEntry(
    id: 'exec-hangar',
    titleKey: 'execHangar.title',
    route: '/tools/exec-hangar',
  ),
  ToolEntry(
    id: 'missions',
    titleKey: 'catalog.missions',
    route: '/tools/missions',
  ),
  ToolEntry(
    id: 'blueprints',
    titleKey: 'catalog.blueprints',
    route: '/tools/blueprints',
  ),
  ToolEntry(
    id: 'key-bindings',
    titleKey: 'keyBindings.title',
    route: '/tools/key-bindings',
  ),
];

/// Tiles are equal and never narrower than this; at most four share a row.
const _tileMinWidth = 240.0, _tileGap = 14.0, _tilesPerRow = 4;

final class ToolsPage extends StatefulWidget {
  const ToolsPage({
    super.key,
    this.entries = toolEntries,
    this.hangar,
    this.cache,
    this.recordsPort,
    this.recent,
    this.onOpenRecent,
  });
  final List<ToolEntry> entries;
  final CachedExecHangar? hangar;
  final ToolsSnapshotCache? cache;
  final MissionRecordsPort? recordsPort;
  final CatalogRecent? recent;
  final void Function(BuildContext context, CatalogRecentEntry entry)?
  onOpenRecent;
  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  late final MissionRecordsController records;

  @override
  void initState() {
    super.initState();
    records = MissionRecordsController(widget.recordsPort);
    unawaited(records.load());
  }

  @override
  void dispose() {
    records.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ToolsSurface(
    child: ListenableBuilder(
      listenable: Listenable.merge([
        records,
        if (widget.cache != null) widget.cache!,
        if (widget.recent != null) widget.recent!,
      ]),
      builder: (context, _) {
        final strings = AppStrings.of(context), t = context.tokens;
        return LoadingContentProbe(
          route: '/tools',
          items: widget.entries.length,
          status: widget.entries.isEmpty
              ? LoadingContentStatus.empty
              : LoadingContentStatus.data,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.text('navigation.tools'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: t.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        ((constraints.maxWidth + _tileGap) ~/
                                (_tileMinWidth + _tileGap))
                            .clamp(1, _tilesPerRow);
                    // The hall's hover line only; a tile does not lift.
                    Widget tile(ToolEntry entry) => MarketHoverCard(
                      lift: false,
                      child: MarketSurface(
                        child: Material(
                          type: MaterialType.transparency,
                          child: StarBridgeActionRow(
                            controlKey: Key('tool-${entry.id}'),
                            inheritContentStyle: true,
                            hoverFace: false,
                            baseRadius: 0,
                            onActivate: (context, _) => Actions.invoke(
                              context,
                              OpenDestinationIntent(entry.route),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 132),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  22,
                                  24,
                                  20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.text(entry.titleKey),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    if (entry.id == 'exec-hangar')
                                      ToolsHangarCardData(
                                        hangar: widget.hangar,
                                        records: records,
                                      )
                                    else
                                      ToolsCardData(
                                        id: entry.id,
                                        hangar: widget.hangar,
                                        cache: widget.cache,
                                        records: records,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    // Rows, not a Wrap: the tiles of a row share the tallest
                    // one's height (a retry button or wrapped text makes one
                    // taller), and a short last row keeps the same tile width.
                    return Column(
                      children: [
                        for (var i = 0; i < widget.entries.length; i += columns)
                          Padding(
                            padding: EdgeInsets.only(
                              top: i == 0 ? 0 : _tileGap,
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var c = 0; c < columns; c++) ...[
                                    if (c > 0) const SizedBox(width: _tileGap),
                                    Expanded(
                                      child: i + c < widget.entries.length
                                          ? tile(widget.entries[i + c])
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (widget.recent case final recent?
                    when recent.entries.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  MarketSectionHeading(
                    strings.text('terminal.recent'),
                    meta: Text('${recent.entries.length}'),
                    trailing: ToolsAction(
                      key: const Key('tools-recent-clear'),
                      label: strings.text('terminal.clear'),
                      onPressed: recent.clear,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1050
                          ? 4
                          : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                      final width =
                          (constraints.maxWidth - 12 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final entry in recent.entries)
                            SizedBox(
                              width: width,
                              child: MarketSurface(
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: Key('tools-recent-${entry.key}'),
                                    onTap: () => widget.onOpenRecent?.call(
                                      context,
                                      entry,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 56,
                                            height: 56,
                                            child: _recentArt(entry),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.label(
                                                    strings.locale.languageCode,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                ToolsTag(
                                                  strings.text(
                                                    'terminal.${entry.kind.name == 'missions' ? 'contract' : 'blueprint'}',
                                                  ),
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
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (widget.recent?.saveFailed == true)
                  Text(
                    strings.text('terminal.historyError'),
                    style: TextStyle(color: t.colors.textSecondary),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _recentArt(CatalogRecentEntry entry) {
    final row = entry.kind.name == 'blueprints'
        ? widget.cache?.blueprintRows[entry.id.toString()]
        : null;
    return row == null ? const MarketArt(null) : CatalogImage(row);
  }
}
