import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../common/organization_member_controls.dart';
import '../common/organization_member_row.dart';
import '../communities/community_workspace_copy.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_members_module.dart';

OrganizationMemberColumns officialFleetMemberColumns(
  OfficialFleetMemberRuntimeCapabilities capabilities,
) => OrganizationMemberColumns(
  presence: capabilities.presence,
  server: capabilities.server,
  ship: capabilities.ship,
  location: capabilities.location,
);

List<OrganizationMemberFilter> officialFleetMemberFilters(
  OfficialFleetMemberDirectoryProjection projection,
) => projection.runtimeCapabilities.presence
    ? [
        for (final filter in projection.supportedFilters)
          OrganizationMemberFilter.values.byName(filter.name),
      ]
    : const [];

OrganizationMemberPagination officialFleetMemberPagination(
  OfficialFleetMemberDirectoryProjection projection,
  OfficialFleetMembersModule module,
) {
  final query = projection.query;
  if (query == null) return const OrganizationMemberPagination();
  final total = projection.totalPages;
  final multiplePages = total != null && total > 1;
  return OrganizationMemberPagination(
    page: multiplePages ? query.pageNumber : null,
    totalPages: multiplePages ? total : null,
    showNavigationWhenDisabled: true,
    onPrevious: total != null && total > 0 && query.pageNumber > 1
        ? () => unawaited(module.goToPage(query.pageNumber - 1))
        : null,
    onNext: total != null && query.pageNumber < total
        ? () => unawaited(module.goToPage(query.pageNumber + 1))
        : null,
    onJump: multiplePages ? (page) => unawaited(module.goToPage(page)) : null,
    pageSize: query.pageSize,
    pageSizes: const [25, 50, 100],
    onPageSize: (size) => unawaited(module.setPageSize(size)),
  );
}

/// Existing interaction callers use the shared member controls, preserving the
/// account-scoped module's search, filter and paging authority.
class OfficialFleetMembersToolbar extends StatelessWidget {
  const OfficialFleetMembersToolbar({
    required this.projection,
    required this.module,
    required this.searchController,
    super.key,
  });

  final OfficialFleetMemberDirectoryProjection projection;
  final OfficialFleetMembersModule module;
  final TextEditingController searchController;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: searchController,
    builder: (context, value, _) => OrganizationMemberToolbar(
      namespace: 'official-fleet-members',
      searchController: searchController,
      onSearch: (value) => unawaited(module.search(value)),
      maxSearchLength: OfficialFleetMemberDirectoryQuery.maxSearchLength,
      searchHint: AppStrings.of(context).text(
        projection.coverage == OfficialFleetRosterCoverage.scmRegisteredMembers
            ? 'officialFleet.members.search.scm'
            : 'officialFleet.members.search',
      ),
      searchButtonLabel: workspaceText(context, 'searchButton'),
      searchError:
          OfficialFleetMemberDirectoryQuery.isValidSearch(value.text.trim())
          ? null
          : AppStrings.of(context).text('officialFleet.members.search.invalid'),
      filters: officialFleetMemberFilters(projection),
      filter: OrganizationMemberFilter.values.byName(
        (projection.query?.filter ?? OfficialFleetMemberFilter.all).name,
      ),
      onFilter: (filter) => unawaited(
        module.setFilter(OfficialFleetMemberFilter.values.byName(filter.name)),
      ),
      pagination: officialFleetMemberPagination(projection, module),
    ),
  );
}

class OfficialFleetMembersPagination extends StatelessWidget {
  const OfficialFleetMembersPagination({
    required this.projection,
    required this.module,
    super.key,
  });
  final OfficialFleetMemberDirectoryProjection projection;
  final OfficialFleetMembersModule module;

  @override
  Widget build(BuildContext context) => OrganizationMemberPaginationBar(
    namespace: 'official-fleet-members',
    pagination: officialFleetMemberPagination(projection, module),
  );
}
