import 'dart:async';

import 'official_fleet_member_views.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../common/organization_member_board.dart';
import '../communities/community_workspace_copy.dart' show workspaceText;
import '../party_rooms/room_display.dart' show roomDate;
import 'official_fleet_members_controls.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_members_module.dart';

class OfficialFleetMembersSection extends StatefulWidget {
  const OfficialFleetMembersSection({
    required this.sourceRef,
    required this.module,
    this.retained = false,
    this.officialMemberCount,
    super.key,
  });
  final String sourceRef;
  final OfficialFleetMembersModule module;
  final bool retained;

  /// The RSI organization's member count, shown beside the registered count.
  final int? officialMemberCount;

  @override
  State<OfficialFleetMembersSection> createState() =>
      _OfficialFleetMembersSectionState();
}

class _OfficialFleetMembersSectionState
    extends State<OfficialFleetMembersSection> {
  final _searchController = TextEditingController();
  final _entries = <String, (Object, OrganizationMemberEntry)>{};
  final _rows = <String, (Object, Widget)>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries.clear();
    _rows.clear();
  }

  OrganizationMemberEntry _entry(
    OfficialFleetMember member,
    String? sourceRef,
    bool allowProfile,
  ) {
    final key = (member, sourceRef, allowProfile);
    final cached = _entries[member.memberRef];
    if (cached?.$1 == key) return cached!.$2;
    final entry = officialFleetMemberEntry(
      context,
      member,
      sourceRef: sourceRef,
      allowProfile: allowProfile,
    );
    _entries[member.memberRef] = (key, entry);
    return entry;
  }

  Widget _row(
    OrganizationMemberEntry entry,
    OrganizationMemberColumns columns,
    String roleLabel,
    bool actions,
  ) {
    final key = (
      entry,
      columns.presence,
      columns.server,
      columns.ship,
      columns.location,
      roleLabel,
      actions,
    );
    final cached = _rows[entry.reference];
    if (cached?.$1 == key) return cached!.$2;
    final row = OrganizationMemberRow(
      key: ValueKey('member-row-${entry.reference}'),
      entry: entry,
      columns: columns,
      roleLabel: roleLabel,
      showActions: actions,
    );
    _rows[entry.reference] = (key, row);
    return row;
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.module.open(widget.sourceRef));
    _searchController.text = widget.module.projection.value.query?.search ?? '';
  }

  @override
  void didUpdateWidget(covariant OfficialFleetMembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceRef != widget.sourceRef ||
        oldWidget.module != widget.module) {
      _searchController.clear();
      unawaited(widget.module.open(widget.sourceRef));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<OfficialFleetMemberDirectoryProjection>(
    valueListenable: widget.module.projection,
    builder: (context, projection, _) {
      final available =
          projection.availability ==
          OfficialFleetMemberDirectoryAvailability.available;
      final loading =
          projection.availability ==
              OfficialFleetMemberDirectoryAvailability.idle ||
          projection.availability ==
              OfficialFleetMemberDirectoryAvailability.loading;
      final allowProfile =
          available &&
          !widget.retained &&
          !projection.isRefreshing &&
          !projection.refreshFailed;
      final query = projection.query;
      final refs = projection.members.map((m) => m.memberRef).toSet();
      _entries.removeWhere((ref, _) => !refs.contains(ref));
      _rows.removeWhere((ref, _) => !refs.contains(ref));
      final strings = AppStrings.of(context);
      final total = projection.totalCount;
      // The directory contract exposes the count for this query, not an
      // independent unfiltered count. With no filter the two are equal;
      // otherwise show only the count actually supplied by the source.
      final unfiltered =
          query != null &&
          query.search.isEmpty &&
          query.filter == OfficialFleetMemberFilter.all;
      // Only SCM-registered members are listed (PR #13 closed, 2026-10-23):
      // name the count for what it is and put the RSI total beside it.
      final registered =
          projection.coverage ==
          OfficialFleetRosterCoverage.scmRegisteredMembers;
      final summary = strings.text(
        registered
            ? 'officialFleet.members.summary.registered'
            : 'officialFleet.members.summary.title',
      );
      final official = widget.officialMemberCount;
      return LoadingContentProbe(
        route: '/fleet',
        status: loading
            ? LoadingContentStatus.waiting
            : !available
            ? LoadingContentStatus.unavailable
            : projection.refreshFailed || widget.retained
            ? LoadingContentStatus.partial
            : projection.members.isEmpty
            ? LoadingContentStatus.empty
            : LoadingContentStatus.data,
        items: projection.members.length,
        child: Column(
          key: const Key('official-fleet-members'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) => OrganizationMemberBoard(
                key: ValueKey(
                  'fleet-members:${widget.sourceRef}:${query?.search}:'
                  '${query?.filter.name}:${query?.pageSize}:${query?.pageNumber}',
                ),
                namespace: 'official-fleet-members',
                rows: [
                  for (final member in projection.members)
                    _entry(member, query?.sourceRef, allowProfile),
                ],
                rowBuilder: _row,
                roleLabel: memberBoardText(context, 'rank'),
                columns: officialFleetMemberColumns(
                  projection.runtimeCapabilities,
                ),
                searchController: _searchController,
                onSearch: (text) => unawaited(widget.module.search(text)),
                searchHint: strings.text(
                  projection.coverage ==
                          OfficialFleetRosterCoverage.scmRegisteredMembers
                      ? 'officialFleet.members.search.scm'
                      : 'officialFleet.members.search',
                ),
                searchButtonLabel: workspaceText(context, 'searchButton'),
                searchError:
                    OfficialFleetMemberDirectoryQuery.isValidSearch(
                      value.text.trim(),
                    )
                    ? null
                    : strings.text('officialFleet.members.search.invalid'),
                filters: officialFleetMemberFilters(projection),
                filter: OrganizationMemberFilter.values.byName(
                  (query?.filter ?? OfficialFleetMemberFilter.all).name,
                ),
                onFilter: (filter) => unawaited(
                  widget.module.setFilter(
                    OfficialFleetMemberFilter.values.byName(filter.name),
                  ),
                ),
                pagination: officialFleetMemberPagination(
                  projection,
                  widget.module,
                ),
                totalCount: projection.totalCount,
                summaryText: registered
                    ? [
                        total == null ? summary : '$summary · $total',
                        if (official != null)
                          strings
                              .text('officialFleet.members.summary.official')
                              .replaceAll('{n}', '$official'),
                      ].join(' / ')
                    : total == null
                    ? summary
                    : '$summary · $total${unfiltered ? ' / $total' : ''}',
                updatedText: projection.lastReadAtUtc == null
                    ? null
                    : '${workspaceText(context, 'updated')} · '
                          '${roomDate(context, projection.lastReadAtUtc!)}',
                onlineCount: projection.runtimeCapabilities.onlineCount
                    ? projection.onlineCount
                    : null,
                inGameCount: projection.runtimeCapabilities.inGameCount
                    ? projection.inGameCount
                    : null,
                fetchedAt: projection.lastReadAtUtc,
                footerNote: available
                    ? strings.text(
                        'officialFleet.members.coverage.${projection.coverage.name}',
                      )
                    : null,
                loading: loading,
                refreshing: projection.isRefreshing,
                error: projection.failureKey == null
                    ? null
                    : strings.text(projection.failureKey!),
                onRetry: () => unawaited(widget.module.refresh()),
                initialScrollOffset: widget.module.scrollOffset,
                onScroll: widget.module.rememberScrollOffset,
              ),
            ),
          ],
        ),
      );
    },
  );
}
