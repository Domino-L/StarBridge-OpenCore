import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'communities_module.dart';
import 'community_directory_card.dart';
import 'community_gameplay_tags.dart';
import 'community_logo.dart';

/// Presentation shared by the directory and its selected-card fallback.
final class CommunityDirectoryPresentation {
  CommunityDirectoryPresentation({
    required this.context,
    required this.model,
    required this.t,
    required this.onDetails,
    required this.onAction,
  });
  final BuildContext context;
  final CommunitiesModule model;
  final String Function(String) t;
  final void Function(CommunityCard) onDetails;
  final void Function(CommunityCard, String) onAction;
  Widget build(
    CommunityCard row, {
    bool detail = false,
    bool horizontal = false,
  }) {
    if (!detail) {
      return CommunityDirectoryCard(
        row: row,
        horizontal: horizontal,
        text: t,
        onDetails: () => onDetails(row),
        onAction: model.canExecute(row)
            ? (action) => onAction(row, action)
            : null,
      );
    }
    final tone = switch (row.relationship) {
      'owner' || 'pending' => context.tokens.colors.warning,
      'member' => context.tokens.colors.success,
      _ => context.tokens.colors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.ground.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CommunityLogo(data: row.logo, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      t('relation.${row.relationship}'),
                      style: TextStyle(color: tone),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              if (row.language.isNotEmpty)
                Text(
                  '${t('language')} · ${communityLanguageLabel(context, row.language)}',
                ),
              if (row.activeTime.isNotEmpty)
                Text('${t('activeTime')} · ${row.activeTime}'),
              if (row.memberCount != null)
                Text('${t('members')} · ${row.memberCount}'),
              Text(t('mode.${row.joinMode}')),
            ],
          ),
          if (row.recruiting ||
              row.tags.isNotEmpty ||
              row.memberScale.isNotEmpty && row.memberCount == null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (row.recruiting)
                  Text(
                    t('recruiting'),
                    style: TextStyle(color: context.tokens.colors.success),
                  ),
                if (row.tags.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: CommunityGameplayTags(value: row.tags),
                  ),
                if (row.memberScale.isNotEmpty && row.memberCount == null)
                  Text(t('option.scale.${row.memberScale}')),
              ],
            ),
          ],
          if (!detail && row.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              row.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (detail && row.systems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${t('systems')} · ${row.systems.join(' / ')}'),
            ),
          if (detail && row.description.isNotEmpty) ...[
            const SizedBox(height: 18),
            SelectableText(row.description),
          ],
          if (detail && row.recruiting) ...[
            const SizedBox(height: 18),
            Text(
              '${t('filter.targets')} · ${row.recruitingTarget.isEmpty ? t('card.notSpecified') : communityRecruitingTarget(row.recruitingTarget, t)}',
            ),
            const SizedBox(height: 8),
            Text(
              t('card.recruitingNote'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              row.recruitingNote.isEmpty
                  ? t('card.noRecruitingNote')
                  : row.recruitingNote,
            ),
          ],
          if (detail && row.relationship == 'owner') ...[
            const SizedBox(height: 12),
            Text(t('ownerHint')),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (!detail)
                OutlinedButton(
                  onPressed: model.writing ? null : () => model.open(row),
                  child: Text(t('details')),
                ),
              for (final action in row.actions)
                OutlinedButton(
                  style: action == 'leave'
                      ? OutlinedButton.styleFrom(
                          foregroundColor: context.tokens.colors.warning,
                        )
                      : null,
                  onPressed: model.canExecute(row)
                      ? () => onAction(row, action)
                      : null,
                  child: Text(t('action.$action')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
