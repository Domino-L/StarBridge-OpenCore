import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_copy.dart';
import 'community_profile_copy.dart';

/// Shared display-only compact organization header. Missing counts stay absent.
class CommunityCompactHeader extends StatelessWidget {
  const CommunityCompactHeader({
    super.key,
    required this.name,
    required this.code,
    required this.logo,
    required this.narrow,
    this.online,
    this.gaming,
    this.total,
    this.scoped = false,
    this.showUnknownMetrics = false,
    this.onDetails,
    this.onToggleExpansion,
  });
  final String name, code;
  final Widget logo;
  final int? online, gaming, total;
  final bool scoped, narrow;
  final bool showUnknownMetrics;
  final VoidCallback? onDetails, onToggleExpansion;
  @override
  Widget build(BuildContext context) {
    String t(String key) => workspaceText(context, key);
    String metricLabel(String key) =>
        key == 'online' ? t(scoped ? 'onlinePage' : 'onlineTotal') : t(key);
    final colors = context.tokens.colors;
    final text = Theme.of(context).textTheme;
    final identity = <Widget>[
      SizedBox(width: 32, height: 32, child: logo),
      const SizedBox(width: 8),
      Expanded(
        child: Tooltip(
          message: '$name\n$code',
          child: Text(
            name,
            key: const ValueKey('community-compact-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium,
          ),
        ),
      ),
    ];
    final metrics = <Widget>[
      for (final metric in [
        (
          'online',
          online,
          colors.accent,
          StandardIconSemantic.radioButtonChecked,
        ),
        ('gaming', gaming, colors.success, StandardIconSemantic.sportsEsports),
        ('member', total, colors.textPrimary, StandardIconSemantic.people),
      ])
        if (metric.$2 != null || showUnknownMetrics)
          Padding(
            padding: EdgeInsetsDirectional.only(start: narrow ? 8 : 16),
            child: Tooltip(
              message:
                  '${metricLabel(metric.$1)} ${metric.$2 ?? '—'}'
                  '${scoped && metric.$1 != 'member' ? '\n${t('presencePageScope')}' : ''}',
              child: Semantics(
                label:
                    '${metricLabel(metric.$1)} ${metric.$2 ?? '—'}'
                    '${scoped && metric.$1 != 'member' ? ' · ${t('presencePageScope')}' : ''}',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (narrow)
                      StandardIcon(metric.$4, size: 16, color: metric.$3)
                    else
                      Text(
                        '${metricLabel(metric.$1)}${scoped && metric.$1 == 'gaming' ? ' · ${t('currentPage')}' : ''}',
                        key: ValueKey('community-presence-label-${metric.$1}'),
                        style: text.labelMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: narrow ? 40 : 64),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${metric.$2 ?? '—'}',
                          key: ValueKey(
                            'community-presence-value-${metric.$1}',
                          ),
                          style: text.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: metric.$3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ];
    final actions = <Widget>[
      const SizedBox(width: 8),
      if (onDetails != null)
        TextButton(
          key: const Key('community-open-details'),
          onPressed: onDetails,
          child: Text(t('viewDetails')),
        ),
      if (onToggleExpansion != null)
        IconButton(
          key: const Key('community-header-expand'),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          onPressed: onToggleExpansion,
          tooltip: profileText(context, 'expandHeader'),
          icon: const StandardIcon(StandardIconSemantic.unfoldMore, size: 18),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            360;
        if (stacked) {
          return Column(
            key: const ValueKey('community-header-compact'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [...identity, ...actions]),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: metrics),
              ],
            ],
          );
        }
        return Row(
          key: const ValueKey('community-header-compact'),
          children: [...identity, ...metrics, ...actions],
        );
      },
    );
  }
}
