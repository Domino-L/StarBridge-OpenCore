import 'dart:async';

import 'official_fleet_member_views.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_members_module.dart';
import 'official_fleet_members_controls.dart';

class OfficialFleetMembersSection extends StatefulWidget {
  const OfficialFleetMembersSection({
    required this.sourceRef,
    required this.module,
    super.key,
  });

  final String sourceRef;
  final OfficialFleetMembersModule module;

  @override
  State<OfficialFleetMembersSection> createState() =>
      _OfficialFleetMembersSectionState();
}

class _OfficialFleetMembersSectionState
    extends State<OfficialFleetMembersSection> {
  final TextEditingController _searchController = TextEditingController();

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
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfficialFleetMemberDirectoryProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        return Column(
          key: const Key('official-fleet-members'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DirectoryHeading(projection: projection),
            SizedBox(height: context.tokens.space.md),
            switch (projection.availability) {
              OfficialFleetMemberDirectoryAvailability.idle ||
              OfficialFleetMemberDirectoryAvailability.loading =>
                const OfficialFleetMembersLoading(),
              OfficialFleetMemberDirectoryAvailability.unavailable =>
                OfficialFleetMembersUnavailable(
                  failureKey:
                      projection.failureKey ??
                      'officialFleet.members.error.unavailable',
                  onRetry: widget.module.refresh,
                ),
              OfficialFleetMemberDirectoryAvailability.available =>
                _DirectoryContent(
                  projection: projection,
                  module: widget.module,
                  searchController: _searchController,
                ),
            },
          ],
        );
      },
    );
  }
}

class _DirectoryHeading extends StatelessWidget {
  const _DirectoryHeading({required this.projection});

  final OfficialFleetMemberDirectoryProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('officialFleet.members.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xxs),
            Text(
              strings.text('officialFleet.members.body'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        );
        if (constraints.maxWidth < 760 || projection.totalCount == null) {
          return heading;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            SizedBox(width: tokens.space.lg),
            _DirectoryMetrics(projection: projection),
          ],
        );
      },
    );
  }
}

class _DirectoryMetrics extends StatelessWidget {
  const _DirectoryMetrics({required this.projection});

  final OfficialFleetMemberDirectoryProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Wrap(
      spacing: context.tokens.space.md,
      children: [
        _Metric(
          label: strings.text('officialFleet.members.metric.matches'),
          value: projection.totalCount?.toString() ?? '—',
          color: context.tokens.colors.textPrimary,
        ),
        _Metric(
          label: strings.text('officialFleet.members.metric.online'),
          value: projection.onlineCount?.toString() ?? '—',
          color: context.tokens.colors.info,
        ),
        _Metric(
          label: strings.text('officialFleet.members.metric.inGame'),
          value: projection.inGameCount?.toString() ?? '—',
          color: context.tokens.colors.success,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        SizedBox(width: context.tokens.space.xs),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.tokens.colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _DirectoryContent extends StatelessWidget {
  const _DirectoryContent({
    required this.projection,
    required this.module,
    required this.searchController,
  });

  final OfficialFleetMemberDirectoryProjection projection;
  final OfficialFleetMembersModule module;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.of(
            context,
          ).text('officialFleet.members.coverage.${projection.coverage.name}'),
          key: const Key('official-fleet-members-coverage'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.sm),
        OfficialFleetMembersToolbar(
          projection: projection,
          module: module,
          searchController: searchController,
        ),
        SizedBox(height: tokens.space.md),
        if (projection.members.isEmpty)
          const OfficialFleetMembersEmpty()
        else
          ValueListenableBuilder<String?>(
            valueListenable: module.selectedMemberRef,
            builder: (context, selectedRef, _) {
              final selected = projection.members
                  .where((member) => member.memberRef == selectedRef)
                  .firstOrNull;
              final list = _MemberDirectoryList(
                members: projection.members,
                module: module,
              );
              if (selected == null) return list;
              final detail = OfficialFleetMemberDetails(
                member: selected,
                onClose: () => module.selectMember(null),
              );
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 1000) return detail;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list),
                      SizedBox(width: tokens.space.md),
                      SizedBox(width: 300, child: detail),
                    ],
                  );
                },
              );
            },
          ),
        SizedBox(height: tokens.space.md),
        OfficialFleetMembersPagination(projection: projection, module: module),
      ],
    );
  }
}

class _MemberDirectoryList extends StatefulWidget {
  const _MemberDirectoryList({required this.members, required this.module});

  final List<OfficialFleetMember> members;
  final OfficialFleetMembersModule module;

  @override
  State<_MemberDirectoryList> createState() => _MemberDirectoryListState();
}

class _MemberDirectoryListState extends State<_MemberDirectoryList> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.module.scrollOffset,
    keepScrollOffset: false,
  )..addListener(_rememberScroll);

  void _rememberScroll() => widget.module.rememberScrollOffset(_scroll.offset);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final viewportHeight = (MediaQuery.sizeOf(context).height - 390).clamp(
      320.0,
      620.0,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return StarBridgeSurface(
          key: const Key('official-fleet-members-list'),
          role: SurfaceRole.panel,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (wide) const OfficialFleetMemberTableHeader(),
              SizedBox(
                height: viewportHeight,
                child: ListView.separated(
                  controller: _scroll,
                  key: const Key('official-fleet-members-virtual-list'),
                  padding: EdgeInsets.all(tokens.space.sm),
                  itemCount: widget.members.length,
                  separatorBuilder: (_, _) => SizedBox(height: tokens.space.xs),
                  itemBuilder: (context, index) => OfficialFleetMemberRow(
                    key: Key(
                      'official-fleet-member-${widget.members[index].memberRef}',
                    ),
                    member: widget.members[index],
                    wide: wide,
                    onOpen: () => widget.module.selectMember(
                      widget.members[index].memberRef,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
