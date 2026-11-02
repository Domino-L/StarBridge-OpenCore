import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../shell/widgets/attention_badge.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../features/direct_messages/communication_time_formatter.dart';
import 'menu_comms_view.dart';
import 'menu_inline_avatar.dart';
import 'menu_avatar_actions.dart';
import 'menu_feature_view.dart';
import 'menu_loading.dart';

class MenuCommsDirectory extends StatelessWidget {
  const MenuCommsDirectory({
    super.key,
    required this.view,
    required this.query,
    required this.group,
    required this.onQuery,
    required this.onGroup,
    required this.onAction,
    this.searchRevision = 0,
    this.onProfile,
    this.organization,
    this.organizationSelected = false,
    this.onOrganizationAction,
  });
  final MenuCommsView view;
  final String query, group;

  /// Retirement token from the existing panel reset, never a text-value key.
  final int searchRevision;
  final ValueChanged<String> onQuery, onGroup;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final MenuFeatureView? organization;
  final bool organizationSelected;
  final void Function(String, String)? onOrganizationAction;
  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final channels = (organization?.channels ?? const <MenuFeatureRow>[])
        .where(
          (row) => group == 'all' && row.title.toLowerCase().contains(needle),
        )
        .toList();
    final rows = view.rows
        .where(
          (r) =>
              (group == 'all' ||
                  (group == 'unread' ? r.unread > 0 : r.request)) &&
              (needle.isEmpty ||
                  '${r.name} ${view.previews[r.key] ?? ''}'
                      .toLowerCase()
                      .contains(needle)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                menuText(context, 'menu.overlay.comms.conversations'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (view.name == null)
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                semanticLabel: menuText(context, 'friends.refresh'),
                onActivate: view.busy ? null : (_) => onAction('retry', ''),
                child: Text(menuText(context, 'friends.refresh')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (view.name == null && view.refreshing)
          MenuLoading(feedback: view.readFeedback),
        KeyedSubtree(
          key: ValueKey((
            'menu-comms-search-${view.profileKey ?? ''}',
            searchRevision,
          )),
          child: StarBridgeFieldFrame(
            builder: (context, focus) => TextFormField(
              key: const ValueKey('menu-comms-search'),
              focusNode: focus,
              initialValue: query,
              decoration: InputDecoration(
                hintText: menuText(context, 'menu.overlay.comms.filter'),
                isDense: true,
              ),
              onChanged: onQuery,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in {
              'all': menuText(context, 'menu.overlay.comms.all'),
              'unread': menuText(context, 'menu.overlay.comms.unread'),
              'requests': menuText(context, 'menu.overlay.comms.request'),
            }.entries)
              MergeSemantics(
                child: Semantics(
                  selected: group == entry.key,
                  inMutuallyExclusiveGroup: true,
                  child: StarBridgeActionButton(
                    controlKey: ValueKey('menu-comms-group-${entry.key}'),
                    semanticLabel: entry.value,
                    nativeStyle: OutlinedButton.styleFrom(
                      backgroundColor: group == entry.key
                          ? context.tokens.colors.info.withValues(alpha: .16)
                          : null,
                    ),
                    onActivate: (_) => onGroup(entry.key),
                    child: Text(entry.value),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty && channels.isEmpty
              ? Center(
                  child: Text(
                    menuText(context, 'menu.overlay.comms.noMatch'),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('menu-conversation-list'),
                  itemCount: rows.length + channels.length,
                  itemBuilder: (context, index) {
                    if (index < channels.length) {
                      final row = channels[index];
                      return StarBridgeActionRow(
                        semanticLabel: menuText(
                          context,
                          'menu.overlay.comms.openOrganization',
                          {'name': row.title},
                        ),
                        semanticSelected: organizationSelected && row.selected,
                        onActivate:
                            organization?.busy == true || row.buttons.isEmpty
                            ? null
                            : (_, _) => onOrganizationAction?.call(
                                row.buttons.first.key,
                                '',
                              ),
                        child: ListTile(
                          key: ValueKey(
                            'menu-organization-conversation-${row.title}',
                          ),
                          selected: organizationSelected && row.selected,
                          selectedTileColor:
                              context.tokens.surfaces.raised.fill,
                          leading: MenuInlineAvatar(
                            name: row.title,
                            source: row.avatar,
                          ),
                          title: Text(
                            row.title,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            menuText(
                              context,
                              'menu.overlay.comms.organizationChannel',
                            ),
                          ),
                        ),
                      );
                    }
                    final row = rows[index - channels.length];
                    return Material(
                      color: !organizationSelected && row.key == view.profileKey
                          ? context.tokens.surfaces.raised.fill
                          : Colors.transparent,
                      child: StarBridgeActionRow(
                        controlKey: ValueKey('menu-conversation-${row.key}'),
                        semanticLabel: menuText(
                          context,
                          'menu.overlay.comms.open',
                          {'name': row.name},
                        ),
                        semanticSelected:
                            !organizationSelected && row.key == view.profileKey,
                        baseRadius: 0,
                        onActivate: (_, _) => onAction('select', row.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MenuAvatarActions(
                                identity: row.key,
                                name: row.name,
                                onProfile: onProfile == null
                                    ? null
                                    : () => onProfile!(row.key),
                                child: MenuInlineAvatar(
                                  name: row.name,
                                  source: view.avatars[row.key],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            row.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (row.unread > 0)
                                          AttentionCount(count: row.unread),
                                      ],
                                    ),
                                    if ((view.previews[row.key] ?? '')
                                        .isNotEmpty)
                                      Text(
                                        view.previews[row.key]!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      '${row.request ? menuText(context, 'menu.overlay.comms.requestPrefix') : ''}${communicationTime(row.time, Localizations.localeOf(context))}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: context
                                                .tokens
                                                .colors
                                                .textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (organization?.state == 'unavailable')
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            semanticLabel: menuText(
              context,
              'menu.overlay.comms.organizationRetry',
            ),
            onActivate: (_) => onOrganizationAction?.call('refresh', ''),
            child: Text(
              menuText(context, 'menu.overlay.comms.organizationRetry'),
            ),
          ),
        for (final action
            in organization?.buttons ?? const <MenuFeatureButton>[])
          if (const {
            'nextPage',
            'firstPage',
            'moreOrganizationChats',
            'organizationChatsHome',
          }.contains(action.role))
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              semanticLabel: action.label,
              onActivate: organization?.busy == true
                  ? null
                  : (_) => onOrganizationAction?.call(action.key, ''),
              child: Text(action.label),
            ),
      ],
    );
  }
}
