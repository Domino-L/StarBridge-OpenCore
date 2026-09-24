import '../../design_system/icons/standard_icon.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_copy.dart';
import 'community_workspace_image.dart';
import 'community_workspace_port.dart';
import 'community_profile_copy.dart';
import 'community_activity_time.dart';

/// A stable overview: identity/presence first, collaboration information second.
/// Long-form data stays accessible through details, never through a nested fold.
class CommunityWorkspaceHeader extends StatelessWidget {
  const CommunityWorkspaceHeader({
    required this.workspace,
    required this.logo,
    required this.announcement,
    required this.onDetails,
    required this.onRefresh,
    required this.onCopyContacts,
    required this.onCopyContact,
    this.logoLoading = false,
    this.logoFailed = false,
    this.expanded = false,
    this.onToggleExpansion,
    super.key,
  });

  final CommunityWorkspace workspace;
  final Uint8List? logo;
  final bool logoLoading, logoFailed;
  final bool expanded;
  final VoidCallback? onToggleExpansion;
  final Widget announcement;
  final VoidCallback onDetails, onRefresh, onCopyContacts;
  final ValueChanged<String> onCopyContact;

  @override
  Widget build(BuildContext context) {
    String t(String key) => workspaceText(context, key);
    final colors = context.tokens.colors;
    final text = Theme.of(context).textTheme;
    final online = workspace.members.where((m) => m.online).length;
    final gaming = workspace.members
        .where((m) => m.online && m.liveStatus.toLowerCase() == 'ingame')
        .length;
    final scoped =
        workspace.query.isNotEmpty ||
        workspace.members.length != workspace.totalCount;
    final contacts = [
      ...workspace.externalContacts,
      if (workspace.websiteUrl?.isNotEmpty == true)
        (t('website'), workspace.websiteUrl!),
    ];
    final contactSummary = contacts.isEmpty
        ? t('hidden')
        : '${contacts.first.$1} · ${contacts.first.$2}';
    final activity = [
      if (workspace.activityWindows.isNotEmpty)
        communityActivitySummary(context, workspace.activityWindows)
      else if (workspace.activeTime.isNotEmpty)
        workspace.activeTime,
      if (workspace.timeZoneId?.isNotEmpty == true)
        communityTimeZoneSummary(context, workspace),
    ].join(' · ');

    Widget heading(String value) => Text(
      value,
      style: text.labelMedium?.copyWith(color: colors.textSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final identity = Row(
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: CommunityWorkspaceImage(
            bytes: logo,
            loading: logoLoading,
            loadFailed: logoFailed,
            icon: StandardIconSemantic.groups,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: workspace.name,
                child: Text(
                  workspace.name,
                  style: text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 3),
              heading(workspace.code),
            ],
          ),
        ),
      ],
    );
    final presence = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(child: heading(t('onlineInfo'))),
            if (scoped) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: t('presencePageScope'),
                child: Text(
                  t('currentPage'),
                  style: text.labelSmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final metric in [
              ('online', online, colors.accent),
              ('gaming', gaming, colors.success),
              ('member', workspace.totalCount, colors.textPrimary),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Semantics(
                    label: '${t(metric.$1)} ${metric.$2}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${metric.$2}',
                              key: ValueKey(
                                'community-presence-value-${metric.$1}',
                              ),
                              style: text.headlineSmall?.copyWith(
                                fontSize: 28,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: metric.$3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Tooltip(
                          message: t(metric.$1),
                          child: Text(
                            t(metric.$1),
                            key: ValueKey(
                              'community-presence-label-${metric.$1}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              fontSize: 12,
                              height: 1.15,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    final activeHours = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading(t('activity')),
        const SizedBox(height: 5),
        Tooltip(
          message: activity,
          child: Text(
            activity.isEmpty ? t('hidden') : activity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium,
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (expanded && onToggleExpansion != null)
          IconButton(
            key: const Key('community-header-collapse'),
            onPressed: onToggleExpansion,
            tooltip: profileText(context, 'collapseHeader'),
            icon: const StandardIcon(StandardIconSemantic.unfoldLess, size: 18),
          ),
        TextButton.icon(
          key: const Key('community-open-details'),
          onPressed: onDetails,
          icon: const StandardIcon(StandardIconSemantic.info, size: 18),
          label: Text(t('viewDetails')),
        ),
        IconButton(
          onPressed: onRefresh,
          tooltip: t('refresh'),
          icon: const StandardIcon(StandardIconSemantic.refresh, size: 20),
        ),
      ],
    );
    final announcementCell = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading(t('announcements')),
        const SizedBox(height: 4),
        SizedBox(height: 42, child: announcement),
      ],
    );
    final contactsCell = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading(t('contacts')),
        const SizedBox(height: 4),
        SizedBox(
          height: 42,
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: contactSummary,
                  child: SelectableText(
                    contactSummary,
                    maxLines: 1,
                    style: text.bodyMedium?.copyWith(
                      color: contacts.isEmpty
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (contacts.length > 1)
                TextButton(
                  onPressed: onDetails,
                  child: Text('+${contacts.length - 1}'),
                ),
              if (contacts.isNotEmpty)
                IconButton(
                  onPressed: () => onCopyContact(contacts.first.$2),
                  tooltip: t('copy'),
                  icon: const StandardIcon(StandardIconSemantic.copy, size: 18),
                ),
              if (contacts.isNotEmpty)
                IconButton(
                  key: const Key('community-copy-all-contacts'),
                  onPressed: onCopyContacts,
                  tooltip: t('copyAll'),
                  icon: const StandardIcon(StandardIconSemantic.copyAll, size: 18),
                ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, available) {
        final compact =
            !expanded &&
            (available.maxWidth < 1000 ||
                MediaQuery.sizeOf(context).height <= 800);
        return Container(
          key: const Key('community-header-information'),
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
              : const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.tokens.surfaces.raised.fill,
            border: Border.all(color: context.tokens.surfaces.panel.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: compact
              ? _compactHeader(
                  context,
                  online,
                  gaming,
                  scoped,
                  available.maxWidth < 650,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1000;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(flex: 4, child: identity),
                            if (wide) ...[
                              const SizedBox(width: 24),
                              Expanded(flex: 4, child: presence),
                              const SizedBox(width: 24),
                              Expanded(flex: 3, child: activeHours),
                              const SizedBox(width: 16),
                            ],
                            actions,
                          ],
                        ),
                        if (!wide) ...[
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: presence),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: activeHours),
                            ],
                          ),
                        ],
                        const Divider(height: 24),
                        if (constraints.maxWidth >= 650)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: announcementCell),
                              const SizedBox(width: 24),
                              Expanded(flex: 4, child: contactsCell),
                            ],
                          )
                        else ...[
                          announcementCell,
                          const SizedBox(height: 12),
                          contactsCell,
                        ],
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _compactHeader(
    BuildContext context,
    int online,
    int gaming,
    bool scoped,
    bool narrow,
  ) {
    String t(String key) => workspaceText(context, key);
    final colors = context.tokens.colors;
    final text = Theme.of(context).textTheme;
    return Row(
      key: const ValueKey('community-header-compact'),
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CommunityWorkspaceImage(
            bytes: logo,
            loading: logoLoading,
            loadFailed: logoFailed,
            icon: StandardIconSemantic.groups,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: '${workspace.name}\n${workspace.code}',
            child: Text(
              workspace.name,
              key: const ValueKey('community-compact-name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ),
        ),
        for (final metric in [
          ('online', online, colors.accent, StandardIconSemantic.radioButtonChecked),
          ('gaming', gaming, colors.success, StandardIconSemantic.sportsEsports),
          (
            'member',
            workspace.totalCount,
            colors.textPrimary,
            StandardIconSemantic.people,
          ),
        ])
          Padding(
            padding: EdgeInsetsDirectional.only(start: narrow ? 8 : 16),
            child: Tooltip(
              message:
                  '${t(metric.$1)} ${metric.$2}'
                  '${scoped && metric.$1 != 'member' ? '\n${t('presencePageScope')}' : ''}',
              child: Semantics(
                label:
                    '${t(metric.$1)} ${metric.$2}'
                    '${scoped && metric.$1 != 'member' ? ' · ${t('presencePageScope')}' : ''}',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (narrow)
                      StandardIcon(metric.$4, size: 16, color: metric.$3)
                    else
                      Text(
                        '${t(metric.$1)}${scoped && metric.$1 != 'member' ? ' · ${t('currentPage')}' : ''}',
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
                          '${metric.$2}',
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
        const SizedBox(width: 8),
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
      ],
    );
  }
}
