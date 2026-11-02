import '../../shared/guide/guide_empty_state.dart';
import '../../app/routing/open_destination_intent.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/widgets/attention_badge.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../common/user_avatar_menu.dart';
import '../common/social_identity_text.dart';
import 'direct_messages_module.dart';
import 'chat_avatar.dart';
import 'communication_time_formatter.dart';

/// Directory projection only; selection, drafts and commands stay with the page.
class DirectMessageDirectory extends StatelessWidget {
  const DirectMessageDirectory({
    required this.module,
    required this.search,
    required this.onOpen,
    this.onOpenProfile,
    super.key,
  });
  final DirectMessagesModule module;
  final String search;
  final Future<void> Function(Conversation) onOpen;
  final void Function(Conversation)? onOpenProfile;
  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('direct.$key');
    String time(DateTime value) =>
        communicationTime(value, AppStrings.of(context).locale);
    final visible = module.visible
        .where(
          (row) =>
              search.isEmpty ||
              row.name.toLowerCase().contains(search) ||
              row.gameId.toLowerCase().contains(search),
        )
        .toList();
    if (visible.isEmpty &&
        search.isEmpty &&
        module.loaded &&
        GuideEmptyState.active(context)) {
      return GuideEmptyState(
        'messages',
        onPrimary: () => Actions.maybeInvoke(
          context,
          const OpenDestinationIntent('/friends'),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          t(
            search.isNotEmpty
                ? 'noSearchResults'
                : module.loaded
                ? 'empty'
                : module.busy
                ? 'loading'
                : 'refreshHint',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final row = visible[index];
        final selected =
            module.selected?.ref == row.ref ||
            (row.conversationKey != null &&
                module.selected?.conversationKey == row.conversationKey);
        return Material(
          color: Colors.transparent,
          child: StarBridgeActionRow(
            controlKey: ValueKey(('chat-conversation', row.ref)),
            semanticLabel: '${row.name}  ${row.gameId}',
            semanticSelected: selected,
            onActivate: (_, source) => unawaited(
              runStarBridgeActivation<void>(source, () => onOpen(row)),
            ),
            child: ListTile(
              leading: ChatAvatar(
                onViewProfile: onOpenProfile == null
                    ? null
                    : () => onOpenProfile!(row),
                label: row.name,
                source: row.avatar,
                target: UserTarget('conversation', row.ref, query: row.gameId),
                actions: [
                  AvatarMenuAction(
                    AppStrings.of(context).text('avatar.sendMessage'),
                    () => unawaited(onOpen(row)),
                  ),
                ],
              ),
              selected: selected,
              selectedTileColor: context.tokens.colors.accent.withValues(
                alpha: .15,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: SocialIdentityText(
                      callsign: row.name,
                      gameId: row.gameId,
                      callsignStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      gameIdColor: context.tokens.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      time(row.time),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.preview,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AttentionCount(count: row.unread),
                    ],
                  ),
                  if (conversationPresence(row.state, row.presence)
                      case final presence?)
                    directMessagePresenceLabel(context, presence),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget directMessagePresenceLabel(BuildContext context, String presence) =>
    Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: presenceColor(context.tokens.colors, 'presence.$presence'),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            AppStrings.of(context).text('direct.presence.$presence'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: presenceColor(context.tokens.colors, 'presence.$presence'),
            ),
          ),
        ],
      ),
    );
