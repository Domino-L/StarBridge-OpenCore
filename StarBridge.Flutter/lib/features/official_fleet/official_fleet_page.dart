import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_models.dart';
import 'official_fleet_members_module.dart';
import 'official_fleet_members_section.dart';
import 'official_fleet_module.dart';
import 'official_fleet_overview_module.dart';
import 'official_fleet_overview_section.dart';
import 'official_fleet_profile_section.dart';
import 'official_fleet_ships_module.dart';
import 'official_fleet_ships_section.dart';
import 'official_fleet_support_views.dart';

class OfficialFleetPage extends StatefulWidget {
  const OfficialFleetPage({required this.module, super.key});

  final OfficialFleetModule module;

  @override
  State<OfficialFleetPage> createState() => _OfficialFleetPageState();
}

class _OfficialFleetPageState extends State<OfficialFleetPage> {
  final ScrollController _scrollController = ScrollController();
  OfficialFleetWorkspaceSection _section =
      OfficialFleetWorkspaceSection.overview;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<OfficialFleetProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.xl,
              tokens.space.lg,
              tokens.space.xl,
              tokens.space.xxl,
            ),
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: tokens.density.contentMaxWidth,
                ),
                child: switch (projection.availability) {
                  OfficialFleetAvailability.loading =>
                    const OfficialFleetLoadingView(),
                  OfficialFleetAvailability.signedOut =>
                    const OfficialFleetSignedOutView(),
                  OfficialFleetAvailability.notMember =>
                    OfficialFleetNotMemberView(onRetry: widget.module.refresh),
                  OfficialFleetAvailability.unavailable =>
                    OfficialFleetUnavailableView(
                      failureKey:
                          projection.failureKey ??
                          'officialFleet.error.unavailable',
                      onRetry: widget.module.refresh,
                    ),
                  OfficialFleetAvailability.available => _FleetWorkspace(
                    projection: projection,
                    overviewModule: widget.module.overview,
                    membersModule: widget.module.members,
                    shipsModule: widget.module.ships,
                    section: _section,
                    onSectionChanged: (value) => setState(() {
                      _section = value;
                    }),
                    onRefresh: widget.module.refresh,
                  ),
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FleetWorkspace extends StatelessWidget {
  const _FleetWorkspace({
    required this.projection,
    required this.overviewModule,
    required this.membersModule,
    required this.shipsModule,
    required this.section,
    required this.onSectionChanged,
    required this.onRefresh,
  });

  final OfficialFleetProjection projection;
  final OfficialFleetOverviewModule overviewModule;
  final OfficialFleetMembersModule membersModule;
  final OfficialFleetShipsModule shipsModule;
  final OfficialFleetWorkspaceSection section;
  final ValueChanged<OfficialFleetWorkspaceSection> onSectionChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final fleet = projection.fleet!;
    final tokens = context.tokens;
    return Column(
      key: const Key('official-fleet-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FleetContextHeader(fleet: fleet, onRefresh: onRefresh),
        SizedBox(height: tokens.space.md),
        _WorkspaceNavigation(selected: section, onSelected: onSectionChanged),
        SizedBox(height: tokens.space.lg),
        switch (section) {
          OfficialFleetWorkspaceSection.overview =>
            OfficialFleetOverviewSection(
              sourceRef: fleet.sourceRef,
              module: overviewModule,
              onOpenSection: onSectionChanged,
            ),
          OfficialFleetWorkspaceSection.profile => OfficialFleetProfileSection(
            fleet: fleet,
            observedAtUtc: projection.observedAtUtc,
          ),
          OfficialFleetWorkspaceSection.members => OfficialFleetMembersSection(
            sourceRef: fleet.sourceRef,
            module: membersModule,
          ),
          OfficialFleetWorkspaceSection.ships => OfficialFleetShipsSection(
            sourceRef: fleet.sourceRef,
            module: shipsModule,
          ),
          _ => _DeferredSection(section: section),
        },
      ],
    );
  }
}

class _FleetContextHeader extends StatelessWidget {
  const _FleetContextHeader({required this.fleet, required this.onRefresh});

  final OfficialFleetSummary fleet;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final rankName =
        fleet.officialRankName ?? strings.text('officialFleet.rank.unknown');
    final rankValue = fleet.officialRankValue;
    return StarBridgeSurface(
      key: const Key('official-fleet-context-header'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.all(tokens.space.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _FleetLogo(fleet: fleet),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fleet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      fleet.sid,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.colors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: tokens.space.sm),
                    _FreshnessLabel(
                      label: strings.text('officialFleet.fresh.live'),
                    ),
                  ],
                ),
              ),
            ],
          );
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OfficialPosition(rankName: rankName, rankValue: rankValue),
              SizedBox(width: tokens.space.md),
              Tooltip(
                message: strings.text('officialFleet.action.refresh'),
                child: IconButton(
                  key: const Key('official-fleet-refresh'),
                  onPressed: onRefresh,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                SizedBox(height: tokens.space.md),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: controls,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              SizedBox(width: tokens.space.lg),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _FleetLogo extends StatelessWidget {
  const _FleetLogo({required this.fleet});

  final OfficialFleetSummary fleet;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = ColoredBox(
      color: tokens.domainColors.command.soft,
      child: Center(
        child: Text(
          fleet.sid.characters.take(2).toString().toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: tokens.domainColors.command.foreground),
        ),
      ),
    );
    return Container(
      key: const Key('official-fleet-logo'),
      width: 68,
      height: 68,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: fleet.logoUrl == null
          ? fallback
          : Image.network(
              fleet.logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _OfficialPosition extends StatelessWidget {
  const _OfficialPosition({required this.rankName, required this.rankValue});

  final String rankName;
  final int? rankValue;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final command = tokens.domainColors.command;
    return Container(
      key: const Key('official-fleet-my-official-position'),
      padding: EdgeInsetsDirectional.only(start: tokens.space.md),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: command.foreground,
            width: tokens.stroke.strong,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('officialFleet.myOfficialPosition'),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.xxs),
          Text(
            '$rankName · ${rankValue == null ? '—' : '$rankValue★'}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: command.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreshnessLabel extends StatelessWidget {
  const _FreshnessLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tokens.icons.statusDot,
          height: tokens.icons.statusDot,
          decoration: BoxDecoration(
            color: tokens.colors.success,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: tokens.space.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
      ],
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({
    required this.selected,
    required this.onSelected,
  });

  final OfficialFleetWorkspaceSection selected;
  final ValueChanged<OfficialFleetWorkspaceSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaces.panel.border,
            width: tokens.stroke.regular,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in OfficialFleetWorkspaceSection.values)
              _WorkspaceTab(
                section: section,
                selected: section == selected,
                onPressed: () => onSelected(section),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.section,
    required this.selected,
    required this.onPressed,
  });

  final OfficialFleetWorkspaceSection section;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppStrings.of(context).text(_sectionLabel(section));
    return TextButton(
      key: Key('official-fleet-tab-${section.name}'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? tokens.colors.textPrimary
            : tokens.colors.textSecondary,
        backgroundColor: selected
            ? tokens.surfaces.selected.fill
            : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space.md,
          vertical: tokens.space.sm,
        ),
        shape: const RoundedRectangleBorder(),
        side: BorderSide.none,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          SizedBox(height: tokens.space.xs),
          AnimatedContainer(
            duration: tokens.motion.pointerMicro,
            width: selected ? 24 : 0,
            height: 2,
            color: tokens.colors.accent,
          ),
        ],
      ),
    );
  }
}

class _DeferredSection extends StatelessWidget {
  const _DeferredSection({required this.section});

  final OfficialFleetWorkspaceSection section;

  @override
  Widget build(BuildContext context) {
    final (titleKey, bodyKey, icon, color) = switch (section) {
      OfficialFleetWorkspaceSection.operations => (
        'officialFleet.section.operations.title',
        'officialFleet.section.operations.body',
        StarBridgeIconSemantic.operation,
        context.tokens.domainColors.command.foreground,
      ),
      OfficialFleetWorkspaceSection.channel => (
        'officialFleet.section.channel.title',
        'officialFleet.section.channel.body',
        StarBridgeIconSemantic.room,
        context.tokens.domainColors.logistics.foreground,
      ),
      OfficialFleetWorkspaceSection.broadcasts => (
        'officialFleet.section.broadcasts.title',
        'officialFleet.section.broadcasts.body',
        StarBridgeIconSemantic.notifications,
        context.tokens.colors.warning,
      ),
      _ => throw StateError('Unsupported deferred fleet section.'),
    };
    return OfficialFleetStatePanel(
      key: Key('official-fleet-section-${section.name}'),
      icon: icon,
      color: color,
      titleKey: titleKey,
      bodyKey: bodyKey,
    );
  }
}

String _sectionLabel(
  OfficialFleetWorkspaceSection section,
) => switch (section) {
  OfficialFleetWorkspaceSection.overview => 'officialFleet.tab.overview',
  OfficialFleetWorkspaceSection.operations => 'officialFleet.tab.operations',
  OfficialFleetWorkspaceSection.members => 'officialFleet.tab.members',
  OfficialFleetWorkspaceSection.channel => 'officialFleet.tab.channel',
  OfficialFleetWorkspaceSection.ships => 'officialFleet.tab.ships',
  OfficialFleetWorkspaceSection.broadcasts => 'officialFleet.tab.broadcasts',
  OfficialFleetWorkspaceSection.profile => 'officialFleet.tab.profile',
};
