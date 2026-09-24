import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_members_module.dart';
import 'official_fleet_support_views.dart';

class OfficialFleetMembersLoading extends StatelessWidget {
  const OfficialFleetMembersLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return StarBridgeSurface(
      key: const Key('official-fleet-members-loading'),
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: context.tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: context.tokens.space.md),
          Text(AppStrings.of(context).text('officialFleet.members.loading')),
        ],
      ),
    );
  }
}

class OfficialFleetMembersUnavailable extends StatelessWidget {
  const OfficialFleetMembersUnavailable({
    required this.failureKey,
    required this.onRetry,
    super.key,
  });

  final String failureKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return OfficialFleetStatePanel(
      key: const Key('official-fleet-members-unavailable'),
      icon: StarBridgeIconSemantic.warning,
      color: context.tokens.colors.warning,
      titleKey: 'officialFleet.members.unavailable.title',
      bodyKey: failureKey,
      actionKey: 'officialFleet.action.retry',
      onAction: onRetry,
    );
  }
}

class OfficialFleetMembersEmpty extends StatelessWidget {
  const OfficialFleetMembersEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return OfficialFleetStatePanel(
      key: const Key('official-fleet-members-empty'),
      icon: StarBridgeIconSemantic.friends,
      color: context.tokens.colors.info,
      titleKey: 'officialFleet.members.empty.title',
      bodyKey: 'officialFleet.members.empty.body',
    );
  }
}

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
  Widget build(BuildContext context) {
    final query = projection.query!;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final search = SizedBox(
      width: 320,
      child: TextField(
        key: const Key('official-fleet-members-search'),
        controller: searchController,
        onSubmitted: module.search,
        decoration: InputDecoration(
          hintText: strings.text('officialFleet.members.search'),
          prefixIcon: const Padding(
            padding: EdgeInsets.all(10),
            child: StarBridgeIcon(StarBridgeIconSemantic.friends),
          ),
          suffixIcon: IconButton(
            tooltip: strings.text('officialFleet.members.search.submit'),
            onPressed: () => module.search(searchController.text),
            icon: const StarBridgeIcon(StarBridgeIconSemantic.forward),
          ),
        ),
      ),
    );
    final filters = Wrap(
      spacing: tokens.space.xs,
      children: [
        for (final filter in OfficialFleetMemberFilter.values)
          ChoiceChip(
            key: Key('official-fleet-members-filter-${filter.name}'),
            label: Text(strings.text(_filterLabelKey(filter))),
            selected: query.filter == filter,
            onSelected: projection.supportedFilters.contains(filter)
                ? (_) => module.setFilter(filter)
                : null,
          ),
      ],
    );
    final pageSize = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.text('officialFleet.members.pageSize'),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(width: tokens.space.sm),
        DropdownButton<int>(
          key: const Key('official-fleet-members-page-size'),
          value: query.pageSize,
          items: const [
            DropdownMenuItem(value: 25, child: Text('25')),
            DropdownMenuItem(value: 50, child: Text('50')),
            DropdownMenuItem(value: 100, child: Text('100')),
          ],
          onChanged: (value) {
            if (value != null) {
              module.setPageSize(value);
            }
          },
        ),
      ],
    );
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 880) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                SizedBox(height: tokens.space.md),
                Row(
                  children: [
                    Expanded(child: filters),
                    pageSize,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              search,
              SizedBox(width: tokens.space.md),
              Expanded(child: filters),
              pageSize,
            ],
          );
        },
      ),
    );
  }
}

class OfficialFleetMembersPagination extends StatefulWidget {
  const OfficialFleetMembersPagination({
    required this.projection,
    required this.module,
    super.key,
  });

  final OfficialFleetMemberDirectoryProjection projection;
  final OfficialFleetMembersModule module;

  @override
  State<OfficialFleetMembersPagination> createState() =>
      _OfficialFleetMembersPaginationState();
}

class _OfficialFleetMembersPaginationState
    extends State<OfficialFleetMembersPagination> {
  final TextEditingController _pageController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.projection.query!;
    final totalPages = widget.projection.totalPages;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      children: [
        OutlinedButton(
          key: const Key('official-fleet-members-previous-page'),
          onPressed:
              totalPages != null && totalPages > 0 && query.pageNumber > 1
              ? () => widget.module.goToPage(query.pageNumber - 1)
              : null,
          child: Text(strings.text('officialFleet.members.previousPage')),
        ),
        Text(
          strings
              .text('officialFleet.members.pageStatus')
              .replaceAll('{page}', query.pageNumber.toString())
              .replaceAll('{total}', totalPages?.toString() ?? '—'),
        ),
        OutlinedButton(
          key: const Key('official-fleet-members-next-page'),
          onPressed: totalPages != null && query.pageNumber < totalPages
              ? () => widget.module.goToPage(query.pageNumber + 1)
              : null,
          child: Text(strings.text('officialFleet.members.nextPage')),
        ),
        SizedBox(
          width: 72,
          child: TextField(
            key: const Key('official-fleet-members-jump-input'),
            controller: _pageController,
            enabled: totalPages != null && totalPages > 0,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: strings.text('officialFleet.members.pageNumber'),
            ),
            onSubmitted: (_) => _jump(),
          ),
        ),
        OutlinedButton(
          key: const Key('official-fleet-members-jump'),
          onPressed: totalPages != null && totalPages > 0 ? _jump : null,
          child: Text(strings.text('officialFleet.members.jump')),
        ),
      ],
    );
  }

  void _jump() {
    final value = int.tryParse(_pageController.text);
    if (value != null) {
      widget.module.goToPage(value);
    }
  }
}

String _filterLabelKey(OfficialFleetMemberFilter filter) => switch (filter) {
  OfficialFleetMemberFilter.all => 'officialFleet.members.filter.all',
  OfficialFleetMemberFilter.online => 'officialFleet.members.filter.online',
  OfficialFleetMemberFilter.inGame => 'officialFleet.members.filter.inGame',
};
