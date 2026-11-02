import 'community_workspace_header.dart';
import 'community_announcements_port.dart';
import 'community_announcements_dialog.dart';
import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
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
  Widget header({
    required CommunityWorkspacePort port,
    required bool expanded,
    required VoidCallback onToggleExpansion,
    required Future<void> Function() onRefresh,
    required Future<void> Function(Widget) onDetails,
  }) {
    return CommunityWorkspaceHeader(
      expanded: expanded,
      onToggleExpansion: onToggleExpansion,
      workspace: workspace,
      logo: model.image('logo'),
      logoLoading: model.imageLoading('logo'),
      logoFailed: model.imageFailed('logo'),
      onRefresh: onRefresh,
      onCopyContacts: copyContacts,
      onCopyContact: (value) => copy(value),
      onDetails: () => onDetails(detailsPanel(port)),
      announcement:
          port is CommunityAnnouncementsPort &&
              (port as CommunityAnnouncementsPort).announcementsAvailable
          ? CommunityAnnouncementEntry(
              key: ValueKey('announcements:${model.targetRef}'),
              controller: model.announcements,
              port: port as CommunityAnnouncementsPort,
              targetRef: model.targetRef,
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('sectionUnavailable'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }

  /// Everything about the organization: shown by the details dialog of the
  /// classic header and of the holo shell's bar.
  Widget detailsPanel(CommunityWorkspacePort port) {
    final headerInformation = information;
    final details = this.details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(workspace.name, style: Theme.of(context).textTheme.titleLarge),
        Text(workspace.code),
        details,
        const Divider(height: 32),
        if (port is CommunityAnnouncementsPort &&
            (port as CommunityAnnouncementsPort).announcementsAvailable) ...[
          CommunityAnnouncementEntry(
            key: ValueKey('detail-announcements:${model.targetRef}'),
            controller: model.announcements,
            port: port as CommunityAnnouncementsPort,
            targetRef: model.targetRef,
            expanded: true,
          ),
          const Divider(height: 32),
        ] else ...[
          Text(
            t('announcements'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(t('sectionUnavailable')),
          const Divider(height: 32),
        ],
        headerInformation,
      ],
    );
  }

  /// Active hours and time zone, or empty when the community set none.
  String get activityText => [
    workspace.activityWindows.isNotEmpty
        ? communityActivitySummary(context, workspace.activityWindows)
        : workspace.activeTime,
    communityTimeZoneSummary(context, workspace),
  ].where((v) => v.isNotEmpty).join(' · ');

  /// The active hours in the viewer's own clock; empty in the same offset.
  String get viewerActivityText => communityViewerActivitySummary(
    context,
    workspace.activityWindows,
    workspace.timeZoneStandardOffsetMinutes,
  );

  /// Every contact as (platform, value), the website last.
  List<(String, String)> get contactEntries => [
    for (final entry in workspace.externalContacts)
      if (entry.$1.trim().isNotEmpty && entry.$2.trim().isNotEmpty) entry,
    if (workspace.websiteUrl?.isNotEmpty == true)
      (t('website'), workspace.websiteUrl!),
  ];

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
        // The same snapshot can outlive its page for one route-removal frame.
        // Resolve inherited presentation from this live projection, not the
        // original page element captured when the snapshot was created.
        final projection = CommunityWorkspaceInformation(
          context: context,
          model: model,
          workspace: workspace,
          copy: copy,
        );
        String t(String key) => projection.t(key);
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
                style: TextStyle(color: context.tokens.colors.stateAccent),
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
              projection._fact(
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
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.quiet,
                      controlKey: const Key('community-copy-all-contacts'),
                      onActivate: (_) => projection.copyContacts(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StandardIcon(
                            StandardIconSemantic.copyAll,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(t('copyAll')),
                        ],
                      ),
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
                      StarBridgeIconAction(
                        controlKey: ValueKey(
                          'community-copy-contact-$platform-$value',
                        ),
                        onActivate: (_) => copy(value),
                        label: t('copy'),
                        icon: const StandardIcon(
                          StandardIconSemantic.copy,
                          size: 18,
                        ),
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
