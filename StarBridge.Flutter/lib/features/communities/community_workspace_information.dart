import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_controller.dart';
import 'community_gameplay_tags.dart';
import 'community_workspace_copy.dart';
import 'community_workspace_port.dart';
import 'community_workspace_image.dart';
import 'community_activity_time.dart';

/// Read-only information shown by the expanded organization header.
final class CommunityWorkspaceInformation {
  CommunityWorkspaceInformation({
    required this.context,
    required this.model,
    required this.workspace,
    required this.copy,
  });
  final BuildContext context;
  final CommunityWorkspaceController model;
  final CommunityWorkspace workspace;
  final Future<void> Function(String, {bool all}) copy;
  String t(String key) => workspaceText(context, key);
  void copyContacts() {
    final separator = AppStrings.of(context).locale.languageCode == 'zh'
        ? '：'
        : ': ';
    final contacts = [
      ...workspace.externalContacts,
      if (workspace.websiteUrl?.isNotEmpty == true)
        (t('website'), workspace.websiteUrl!),
    ];
    unawaited(
      copy(
        contacts
            .where(
              (entry) =>
                  entry.$1.trim().isNotEmpty && entry.$2.trim().isNotEmpty,
            )
            .map((entry) => '${entry.$1.trim()}$separator${entry.$2.trim()}')
            .join('\r\n'),
        all: true,
      ),
    );
  }

  Widget get information {
    final online = workspace.members.where((member) => member.online).length;
    final gaming = workspace.members
        .where(
          (member) =>
              member.online && member.liveStatus.toLowerCase() == 'ingame',
        )
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 650
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        final cells = <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('onlineInfo'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${t('online')} · $online',
                style: TextStyle(color: context.tokens.colors.accent),
              ),
              Text(
                '${t('gaming')} · $gaming',
                style: TextStyle(color: context.tokens.colors.success),
              ),
              Text('${t('members')} · ${workspace.totalCount}'),
              if (workspace.query.isNotEmpty ||
                  workspace.members.length != workspace.totalCount)
                Text(
                  t('presencePageScope'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fact(
                t('activity'),
                [
                  workspace.activityWindows.isNotEmpty
                      ? communityActivitySummary(
                          context,
                          workspace.activityWindows,
                        )
                      : workspace.activeTime,
                  communityTimeZoneSummary(context, workspace),
                ].where((v) => v.isNotEmpty).join(' · '),
                width: width,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (workspace.externalContacts.isNotEmpty ||
                  workspace.websiteUrl?.isNotEmpty == true) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('contacts'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    TextButton.icon(
                      key: const Key('community-copy-all-contacts'),
                      onPressed: copyContacts,
                      icon: const StandardIcon(StandardIconSemantic.copyAll, size: 18),
                      label: Text(t('copyAll')),
                    ),
                  ],
                ),
                for (final (platform, value) in [
                  ...workspace.externalContacts,
                  if (workspace.websiteUrl?.isNotEmpty == true)
                    (t('website'), workspace.websiteUrl!),
                ])
                  Row(
                    children: [
                      Expanded(child: SelectableText('$platform · $value')),
                      IconButton(
                        onPressed: () => copy(value),
                        tooltip: t('copy'),
                        icon: const StandardIcon(StandardIconSemantic.copy, size: 18),
                      ),
                    ],
                  ),
              ],
              if (workspace.externalContacts.isEmpty &&
                  workspace.websiteUrl?.isNotEmpty != true)
                Text('${t('contacts')} · ${t('hidden')}'),
            ],
          ),
        ];
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final cell in cells) SizedBox(width: width, child: cell),
          ],
        );
      },
    );
  }

  Widget get details {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.image('banner') != null)
          SizedBox(
            height: 110,
            child: CommunityWorkspaceImage(
              bytes: model.image('banner'),
              loading: model.imageLoading('banner'),
              loadFailed: model.imageFailed('banner'),
              icon: StandardIconSemantic.groups,
              maxWidth: 1200,
            ),
          ),
        if (workspace.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(workspace.description),
        ],

        if (workspace.tags.isNotEmpty)
          CommunityGameplayTags(value: workspace.tags),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _fact(t('language'), workspace.language),
            _fact(t('systems'), workspace.activeSystemIds.join(' · ')),
          ],
        ),
      ],
    );
  }

  Widget _fact(String label, String? value, {double width = 180}) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(value?.isNotEmpty == true ? value! : t('hidden')),
      ],
    ),
  );
}
