import '../common/organization_workspace_frame.dart';
import '../../design_system/icons/standard_icon.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_passive_count.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'community_workspace_copy.dart';
import 'community_compact_header.dart';
import 'community_workspace_image.dart';
import 'community_workspace_port.dart';
import 'community_profile_copy.dart';
import 'community_activity_time.dart';
import '../../design_system/typography/cjk_line_break.dart';

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
    final online = workspace.members.where((m) => m.publicOnline).length;
    final gaming = workspace.members.where((m) => m.publicInGame).length;
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
    // QualityPass ③: one line when it fits; otherwise break only between
    // segments, so the time zone never drops to a line of its own.
    final activity = metaLine([
      if (workspace.activityWindows.isNotEmpty)
        ...communityActivitySummary(
          context,
          workspace.activityWindows,
        ).split(RegExp(r'[;；]\s*'))
      else if (workspace.activeTime.isNotEmpty)
        workspace.activeTime,
      if (workspace.timeZoneId?.isNotEmpty == true)
        communityTimeZoneSummary(context, workspace),
    ]);

    String metricLabel(String key) =>
        key == 'online' ? t(scoped ? 'onlinePage' : 'onlineTotal') : t(key);
    Widget heading(String value) => Text(
      value,
      style: text.labelMedium?.copyWith(color: colors.textSecondary),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
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
              StarBridgeTooltip(
                message: workspace.name,
                child: Text(
                  workspace.name,
                  style: text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
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
              StarBridgeTooltip(
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
              ('online', online, colors.stateAccent),
              ('gaming', gaming, colors.success),
              ('member', workspace.totalCount, colors.textPrimary),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Semantics(
                    label: '${metricLabel(metric.$1)} ${metric.$2}',
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
                            child: StarBridgePassiveCount(
                              value: metric.$2,
                              valueKey: ValueKey(
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
                        StarBridgeTooltip(
                          message: metricLabel(metric.$1),
                          child: Text(
                            metricLabel(metric.$1),
                            key: ValueKey(
                              'community-presence-label-${metric.$1}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
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
        StarBridgeTooltip(
          message: activity,
          child: Text(
            activity.isEmpty ? t('hidden') : activity,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: text.bodyMedium,
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (expanded && onToggleExpansion != null)
          StarBridgeIconAction(
            controlKey: const Key('community-header-collapse'),
            onActivate: (_) => onToggleExpansion!(),
            label: profileText(context, 'collapseHeader'),
            icon: const StandardIcon(StandardIconSemantic.unfoldLess, size: 18),
          ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('community-open-details'),
          onActivate: (_) => onDetails(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StandardIcon(StandardIconSemantic.info, size: 18),
              const SizedBox(width: 8),
              Text(t('viewDetails')),
            ],
          ),
        ),
        StarBridgeIconAction(
          controlKey: const Key('community-workspace-refresh'),
          onActivate: (_) => onRefresh(),
          label: t('refresh'),
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
                child: StarBridgeTooltip(
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
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('community-header-more-contacts'),
                  onActivate: (_) => onDetails(),
                  child: Text('+${contacts.length - 1}'),
                ),
              if (contacts.isNotEmpty)
                StarBridgeIconAction(
                  controlKey: const Key('community-header-copy-contact'),
                  onActivate: (_) => onCopyContact(contacts.first.$2),
                  label: t('copy'),
                  icon: const StandardIcon(StandardIconSemantic.copy, size: 18),
                ),
              if (contacts.isNotEmpty)
                StarBridgeIconAction(
                  controlKey: const Key('community-copy-all-contacts'),
                  onActivate: (_) => onCopyContacts(),
                  label: t('copyAll'),
                  icon: const StandardIcon(
                    StandardIconSemantic.copyAll,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return OrganizationWorkspaceHeaderLayout(
      key: const Key('community-header-information'),
      expanded: expanded,
      compactBuilder: (narrow) =>
          _compactHeader(context, online, gaming, scoped, narrow),
      identity: identity,
      presence: presence,
      activity: activeHours,
      actions: actions,
      announcement: announcementCell,
      contacts: contactsCell,
    );
  }

  Widget _compactHeader(
    BuildContext context,
    int online,
    int gaming,
    bool scoped,
    bool narrow,
  ) => CommunityCompactHeader(
    name: workspace.name,
    code: workspace.code,
    online: online,
    gaming: gaming,
    total: workspace.totalCount,
    scoped: scoped,
    narrow: narrow,
    logo: CommunityWorkspaceImage(
      bytes: logo,
      loading: logoLoading,
      loadFailed: logoFailed,
      icon: StandardIconSemantic.groups,
    ),
    onDetails: onDetails,
    onToggleExpansion: onToggleExpansion,
  );
}
