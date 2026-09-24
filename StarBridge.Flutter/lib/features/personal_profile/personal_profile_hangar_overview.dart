import '../../shared/ships/ship_category_colors.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_domain_colors.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';
import 'personal_profile_ship_names.dart';

Color _shipSliceColor(
  BuildContext context,
  PersonalProfileHangarCategorySlice slice,
) {
  const prefix = 'profile.local.category.';
  if (slice.labelKey.startsWith(prefix)) {
    return shipCategoryColor(context, slice.labelKey.substring(prefix.length));
  }
  return context.tokens.domainColors
      .resolve(slice.category.domainColorRole)
      .foreground;
}

TextStyle? _caption(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontSize: Theme.of(context).textTheme.labelSmall?.fontSize);

class PersonalProfileHangarOverview extends StatelessWidget {
  const PersonalProfileHangarOverview({
    required this.summary,
    required this.span,
    this.headerTrailing,
    super.key,
  });

  final PersonalProfileHangarSummary summary;
  final int span;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (!summary.isAvailable) {
      return PersonalProfileModuleSurface(
        icon: StarBridgeIconSemantic.hangar,
        titleKey: 'profile.hangar.title',
        accentRole: DomainColorRole.ship,
        headerTrailing: headerTrailing,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            AppStrings.of(context).text('profile.hangar.notConnected'),
            key: const Key('profile-hangar-unavailable'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ),
      );
    }
    final sourceKey = summary.sourceLabelKey.isEmpty
        ? 'profile.hangar.source.rsiSync'
        : summary.sourceLabelKey;
    if (span <= 2) {
      return PersonalProfileModuleSurface(
        icon: StarBridgeIconSemantic.hangar,
        titleKey: 'profile.hangar.title',
        accentRole: DomainColorRole.ship,
        headerTrailing: headerTrailing,
        child: _CompactOverview(
          summary: summary,
          span: span,
          sourceKey: sourceKey,
        ),
      );
    }
    final panels = <({int flex, Widget child})>[
      (
        flex: span == 1 ? 135 : 100,
        child: _ShipCountPanel(summary: summary, compact: span == 1),
      ),
      if (span >= 2 && summary.categories.isNotEmpty)
        (flex: 160, child: _CompositionPanel(categories: summary.categories)),
      if (summary.estimatedValueLabel.isNotEmpty)
        (
          flex: span == 1
              ? 65
              : span == 2
              ? 80
              : 90,
          child: _ValuePanel(
            value: summary.estimatedValueLabel,
            unpriced: summary.unpricedCount,
          ),
        ),
      if (span >= 3 && summary.recentlyAddedShip != null)
        (
          flex: 125,
          child: _RecentShipPanel(
            ship: summary.recentlyAddedShip,
            imageAsset: summary.recentlyAddedShipImageAsset,
            addedAtLabel: summary.recentlyAddedAtLabel,
          ),
        ),
    ];
    return PersonalProfileModuleSurface(
      icon: StarBridgeIconSemantic.hangar,
      titleKey: 'profile.hangar.title',
      accentRole: DomainColorRole.ship,
      headerTrailing: headerTrailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final vertical =
                    constraints.maxWidth <
                        panels.length *
                            MediaQuery.textScalerOf(context).scale(180) &&
                    constraints.maxHeight >=
                        panels.length *
                                MediaQuery.textScalerOf(context).scale(48) +
                            (panels.length - 1) * tokens.space.sm;
                return Flex(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < panels.length; index++) ...[
                      Expanded(
                        flex: vertical ? 1 : panels[index].flex,
                        child: panels[index].child,
                      ),
                      if (index != panels.length - 1)
                        SizedBox(
                          width: vertical ? 0 : tokens.space.sm,
                          height: vertical ? tokens.space.sm : 0,
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (span >= 2 && summary.syncedAtLabel.isNotEmpty) ...[
            SizedBox(height: tokens.space.xs),
            Text(
              key: const Key('profile-hangar-sync-footer'),
              '${AppStrings.of(context).text(sourceKey)} · '
              '${sourceKey.startsWith('profile.local.') ? '' : AppStrings.of(context).text('profile.hangar.syncedAt')} '
              '${summary.syncedAtLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _caption(context)
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Narrow grid modules reflow their facts instead of dividing a single text
/// line into progressively smaller columns. Exceptional text scaling scrolls
/// within the existing grid cell rather than clipping or shrinking typography.
class _CompactOverview extends StatefulWidget {
  const _CompactOverview({
    required this.summary,
    required this.span,
    required this.sourceKey,
  });
  final PersonalProfileHangarSummary summary;
  final int span;
  final String sourceKey;

  @override
  State<_CompactOverview> createState() => _CompactOverviewState();
}

class _CompactOverviewState extends State<_CompactOverview> {
  final _scroll = ScrollController();
  PersonalProfileHangarSummary get summary => widget.summary;
  int get span => widget.span;
  String get sourceKey => widget.sourceKey;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final populated = summary.categories.where((s) => s.count > 0).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final primary = populated.isEmpty
        ? strings.text(
            summary.shipCount > 0
                ? 'profile.local.unknown'
                : 'profile.hangar.none',
          )
        : '${strings.text(populated.first.labelKey)} ${populated.first.count}';
    Widget fact(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${strings.text(label)}  ',
            style: TextStyle(color: tokens.colors.textSecondary),
          ),
          TextSpan(text: value),
        ],
      ),
      style: _caption(context),
    );
    final panels = <Widget>[
      _HangarPanel(
        key: const Key('profile-hangar-count-panel'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _PanelLabel(labelKey: 'profile.hangar.shipCount', wrap: true),
            Text(
              '${summary.shipCount}${strings.text('profile.hangar.unit')}',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: tokens.domainColors.ship.foreground),
            ),
            if (span >= 2)
              fact(
                'profile.hangar.categoryCoverage',
                populated.isEmpty && summary.shipCount > 0
                    ? strings.text('profile.local.unknown')
                    : '${populated.length}${strings.text('profile.hangar.categoryUnit')}',
              ),
            fact('profile.hangar.primaryType', primary),
          ],
        ),
      ),
      if (span >= 2 && summary.categories.isNotEmpty)
        _CompositionPanel(categories: summary.categories, stacked: true),
      if (summary.estimatedValueLabel.isNotEmpty)
        _HangarPanel(
          key: const Key('profile-hangar-value-panel'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelLabel(
                labelKey: summary.unpricedCount == null
                    ? 'profile.hangar.estimatedValue'
                    : summary.unpricedCount! > 0
                    ? 'profile.local.knownValue'
                    : 'profile.local.estimatedValue',
                wrap: true,
              ),
              Text(
                summary.estimatedValueLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.colors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((summary.unpricedCount ?? 0) > 0)
                Text(
                  '${summary.unpricedCount} ${strings.text('profile.local.unpriced')}',
                  style: _caption(context),
                ),
            ],
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth <
            MediaQuery.textScalerOf(context).scale(130) * panels.length;
        return Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stack)
                  for (var i = 0; i < panels.length; i++) ...[
                    if (i > 0) SizedBox(height: tokens.space.xs),
                    panels[i],
                  ]
                else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < panels.length; i++) ...[
                          if (i > 0) SizedBox(width: tokens.space.sm),
                          Expanded(child: panels[i]),
                        ],
                      ],
                    ),
                  ),
                if (span >= 2 && summary.syncedAtLabel.isNotEmpty) ...[
                  SizedBox(height: tokens.space.xs),
                  Text(
                    '${strings.text(sourceKey)} · ${sourceKey.startsWith('profile.local.') ? '' : strings.text('profile.hangar.syncedAt')} ${summary.syncedAtLabel}',
                    key: const Key('profile-hangar-sync-footer'),
                    style: _caption(context)
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShipCountPanel extends StatelessWidget {
  const _ShipCountPanel({required this.summary, required this.compact});

  final PersonalProfileHangarSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final populated =
        summary.categories.where((item) => item.count > 0).toList()
          ..sort((first, second) => second.count.compareTo(first.count));
    final primary = populated.isEmpty ? null : populated.first;
    return _HangarPanel(
      key: const Key('profile-hangar-count-panel'),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Expanded(
                  child: _PanelLabel(labelKey: 'profile.hangar.shipCount'),
                ),
                SizedBox(width: tokens.space.xs),
                Text(
                  '${summary.shipCount}'
                  '${strings.text('profile.hangar.unit')}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: tokens.domainColors.ship.foreground),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!compact) ...[
                  _InlineFact(
                    labelKey: 'profile.hangar.categoryCoverage',
                    value: populated.isEmpty && summary.shipCount > 0
                        ? strings.text('profile.local.unknown')
                        : '${populated.length}'
                              '${strings.text('profile.hangar.categoryUnit')}',
                  ),
                  SizedBox(height: tokens.space.xs),
                ],
                _InlineFact(
                  labelKey: 'profile.hangar.primaryType',
                  value: primary == null
                      ? strings.text(
                          summary.shipCount > 0
                              ? 'profile.local.unknown'
                              : 'profile.hangar.none',
                        )
                      : '${strings.text(primary.labelKey)} ${primary.count}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompositionPanel extends StatelessWidget {
  const _CompositionPanel({required this.categories, this.stacked = false});

  final List<PersonalProfileHangarCategorySlice> categories;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final populated = categories.where((item) => item.count > 0).toList();
    final total = populated.fold<int>(0, (sum, item) => sum + item.count);
    return _HangarPanel(
      key: const Key('profile-hangar-composition-panel'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (stacked)
                const _PanelLabel(
                  labelKey: 'profile.hangar.composition',
                  wrap: true,
                )
              else
                const Expanded(
                  child: _PanelLabel(labelKey: 'profile.hangar.composition'),
                ),
              SizedBox(width: tokens.space.xs),
              Flexible(
                flex: stacked ? 0 : 1,
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (
                        var index = 0;
                        index <
                            (stacked
                                ? populated.length
                                : populated.take(3).length);
                        index++
                      ) ...[
                        if (index > 0) const TextSpan(text: ' · '),
                        TextSpan(
                          text:
                              '${strings.text(populated[index].labelKey)} '
                              '${populated[index].count}',
                          style: TextStyle(
                            color: _shipSliceColor(context, populated[index]),
                          ),
                        ),
                      ],
                    ],
                  ),
                  maxLines: stacked ? null : 1,
                  overflow: stacked
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: _caption(context)
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.xs),
          SizedBox(
            key: const Key('profile-hangar-composition-bar'),
            height: tokens.space.xs + tokens.stroke.regular * 2,
            child: ColoredBox(
              color: tokens.surfaces.raised.fill,
              child: total == 0
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: tokens.surfaces.status.border,
                          width: tokens.stroke.hairline,
                        ),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < populated.length;
                          index++
                        ) ...[
                          if (index > 0) SizedBox(width: tokens.space.xxs),
                          Expanded(
                            flex: populated[index].count,
                            child: ColoredBox(
                              key: Key(
                                'profile-hangar-composition-segment-$index',
                              ),
                              color: _shipSliceColor(
                                context,
                                populated[index],
                              ).withValues(alpha: 0.76),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuePanel extends StatelessWidget {
  const _ValuePanel({required this.value, this.unpriced});

  final String value;
  final int? unpriced;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return _HangarPanel(
      key: const Key('profile-hangar-value-panel'),
      child: Tooltip(
        message: unpriced == null
            ? ''
            : AppStrings.of(context).text('profile.local.catalogPrice'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _PanelLabel(
                    labelKey: unpriced == null
                        ? 'profile.hangar.estimatedValue'
                        : unpriced! > 0
                        ? 'profile.local.knownValue'
                        : 'profile.local.estimatedValue',
                  ),
                ),
                SizedBox(width: tokens.space.xs),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.colors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if ((unpriced ?? 0) > 0)
              Text(
                '$unpriced ${AppStrings.of(context).text('profile.local.unpriced')}',
                style: _caption(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentShipPanel extends StatelessWidget {
  const _RecentShipPanel({
    required this.ship,
    required this.imageAsset,
    required this.addedAtLabel,
  });

  final PersonalProfileShipIdentity? ship;
  final String imageAsset;
  final String addedAtLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return _HangarPanel(
      key: const Key('profile-hangar-recent-ship-panel'),
      child: Row(
        children: [
          Container(
            width: tokens.density.controlHeight + tokens.space.lg,
            height: tokens.density.controlHeight + tokens.space.lg,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tokens.domainColors.ship.soft,
              borderRadius: tokens.shape.small,
              border: Border.all(
                color: tokens.surfaces.status.border,
                width: tokens.stroke.hairline,
              ),
            ),
            child: imageAsset.isEmpty
                ? const _RecentShipFallback()
                : Image.asset(
                    imageAsset,
                    cacheWidth: 128,
                    key: const Key('profile-hangar-recent-ship-image'),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const _RecentShipFallback(),
                  ),
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addedAtLabel.isEmpty
                      ? strings.text('profile.hangar.recentlyAdded')
                      : '${strings.text('profile.hangar.recentlyAdded')} · '
                            '$addedAtLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caption(context)
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                Text(
                  ship == null
                      ? strings.text('profile.hangar.none')
                      : PersonalProfileShipNames.primary(context, ship!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caption(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentShipFallback extends StatelessWidget {
  const _RecentShipFallback();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: StarBridgeIcon(
        StarBridgeIconSemantic.hangar,
        size: tokens.icons.medium,
        color: tokens.domainColors.ship.foreground,
      ),
    );
  }
}

class _HangarPanel extends StatelessWidget {
  const _HangarPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.xs),
      decoration: BoxDecoration(
        color: tokens.surfaces.status.fill,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: tokens.surfaces.status.border,
          width: tokens.stroke.hairline,
        ),
      ),
      child: child,
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.labelKey, this.wrap = false});

  final String labelKey;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      AppStrings.of(context).text(labelKey),
      maxLines: wrap ? null : 1,
      overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
      style: _caption(context)?.copyWith(color: tokens.colors.textSecondary),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.labelKey, required this.value});

  final String labelKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            AppStrings.of(context).text(labelKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _caption(context)
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ),
        SizedBox(width: tokens.space.xs),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _caption(context),
          ),
        ),
      ],
    );
  }
}
