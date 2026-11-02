import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';
import '../common/organization_holo_deck.dart';
import 'official_fleet_holo_layers.dart';

/// Workspace controls next to the section tabs: freshness, details, refresh
/// and the header collapse toggle.
class OfficialFleetHeaderActions extends StatelessWidget {
  const OfficialFleetHeaderActions({
    required this.retained,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onDetails,
    required this.onRefresh,
    super.key,
  });

  final bool retained;
  final bool collapsed;
  final VoidCallback onToggleCollapsed, onDetails;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!narrow)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text(
              strings.text(
                retained
                    ? 'officialFleet.fresh.retained'
                    : 'officialFleet.fresh.live',
              ),
              key: const Key('official-fleet-freshness'),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: context.tokens.colors.textSecondary),
            ),
          ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('official-fleet-open-details'),
          onActivate: (_) => onDetails(),
          child: Text(strings.text('officialFleet.workspace.details')),
        ),
        StarBridgeIconAction(
          controlKey: const Key('official-fleet-refresh'),
          label: strings.text('officialFleet.action.refresh'),
          onActivate: onRefresh == null ? null : (_) => onRefresh!(),
          icon: const StandardIcon(StandardIconSemantic.refresh, size: 20),
        ),
        StarBridgeIconAction(
          controlKey: Key(
            collapsed
                ? 'official-fleet-header-expand'
                : 'official-fleet-header-collapse',
          ),
          label: strings.text(
            collapsed
                ? 'officialFleet.workspace.expand'
                : 'officialFleet.workspace.collapse',
          ),
          onActivate: (_) => onToggleCollapsed(),
          icon: StandardIcon(
            collapsed
                ? StandardIconSemantic.unfoldMore
                : StandardIconSemantic.unfoldLess,
            size: 18,
          ),
        ),
      ],
    );
  }
}

/// The collapsed header: a slim full-bleed strip of the banner carrying the
/// emblem, name, code, tag and the same counters as the full header. Shared
/// by the main fleet and communities through [OrganizationHoloDeck].
class OfficialFleetHoloBar extends StatelessWidget {
  const OfficialFleetHoloBar({
    required this.deck,
    this.tabs,
    this.trailing,
    super.key,
  });

  final OrganizationHoloDeck deck;

  /// The lower screen's section tabs and workspace controls, carried by the
  /// bar on wide windows (preview internals.html, 2026-10-23).
  final Widget? tabs, trailing;

  Widget _emblem() => SizedBox.square(
    dimension: 40,
    // Never clipped (user 2026-10-29: keep the emblem whole).
    child: KeyedSubtree(
      key: const Key('official-fleet-logo'),
      child: OrganizationHoloEmblem(deck.logo, fallback: deck.code),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final ground = tokens.surfaces.ground.fill;
    return ConstrainedBox(
      key: const Key('official-fleet-header-compact'),
      constraints: const BoxConstraints(minHeight: 64),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: OfficialFleetHoloBannerImage(deck.banner),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ground.withValues(alpha: .9),
                    ground.withValues(alpha: .7),
                    ground.withValues(alpha: .55),
                  ],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metricViews = [
                  for (final item in deck.stats)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${item.value ?? '—'} ',
                            style: text.titleMedium?.copyWith(
                              fontFamily: tokens.typography.monoFamily,
                              fontWeight: FontWeight.w600,
                              color: item.accent
                                  ? tokens.colors.stateAccent
                                  : tokens.colors.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: item.label,
                            style: text.labelMedium?.copyWith(
                              color: tokens.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ];
                if (tabs != null) {
                  return _withTabs(context, metricViews, constraints);
                }
                // Narrow bars wrap the metrics after the identity.
                final trailing = constraints.maxWidth >= 760;
                return Row(
                  children: [
                    _emblem(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            deck.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: tokens.colors.textPrimary,
                            ),
                          ),
                          Text(
                            deck.code,
                            style: text.labelLarge?.copyWith(
                              fontFamily: tokens.typography.monoFamily,
                              letterSpacing: 3,
                              color: tokens.colors.textSecondary,
                            ),
                          ),
                          if (deck.tag != null)
                            Text(
                              deck.tag!,
                              key: const Key(
                                'official-fleet-my-official-position',
                              ),
                              style: text.labelMedium?.copyWith(
                                color: tokens.colors.textSecondary,
                              ),
                            ),
                          if (!trailing) ...metricViews,
                        ],
                      ),
                    ),
                    if (trailing)
                      for (final view in metricViews)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 18),
                          child: view,
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Emblem, name over code and tag, the tabs, then counters and controls.
  Widget _withTabs(
    BuildContext context,
    List<Widget> metricViews,
    BoxConstraints constraints,
  ) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        _emblem(),
        const SizedBox(width: 14),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * .22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deck.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.colors.textPrimary,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: deck.code,
                      style: TextStyle(
                        fontFamily: tokens.typography.monoFamily,
                        letterSpacing: 3,
                      ),
                    ),
                    if (deck.tag != null) TextSpan(text: '  ${deck.tag}'),
                  ],
                ),
                key: const Key('official-fleet-my-official-position'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OrganizationHolo(child: OrganizationHoloFace(child: tabs!)),
          ),
        ),
        if (constraints.maxWidth >= 1300)
          for (final view in metricViews)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 18),
              child: view,
            ),
        if (trailing != null)
          OrganizationHolo(child: OrganizationHoloFace(child: trailing!)),
      ],
    );
  }
}
