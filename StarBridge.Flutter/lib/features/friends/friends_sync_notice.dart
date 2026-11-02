import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'friends_module.dart';
import 'friends_waiting_indicator.dart';

final class FriendsSyncNotice extends StatelessWidget {
  const FriendsSyncNotice(
    this.module, {
    this.source = InteractionSource.programmatic,
    super.key,
  });
  final FriendsModule module;
  final InteractionSource source;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final at = module.lastSuccessfulReadUtc?.toLocal();
    final labels = MaterialLocalizations.of(context);
    String dated(String key) => strings
        .text(key)
        .replaceAll(
          '{time}',
          at == null
              ? ''
              : '${labels.formatShortDate(at)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
        );
    if (module.displayOnly && module.snapshot != null && at != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dated('friends.cachedAt'),
              key: const Key('friends-cached-display'),
            ),
            if (module.reading)
              FriendsWaitingIndicator(
                label: strings.text('friends.syncing'),
                source: source,
                controlKey: const Key('friends-syncing'),
              )
            else if (module.refreshFailed)
              Text(
                dated('friends.syncFailedAt'),
                key: const Key('friends-sync-failed'),
                style: TextStyle(color: context.tokens.colors.warning),
              ),
          ],
        ),
      );
    }
    if (module.snapshot != null && module.reading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FriendsWaitingIndicator(
          label: strings.text('friends.syncing'),
          source: source,
          controlKey: const Key('friends-syncing'),
        ),
      );
    }
    if (!module.refreshFailed || at == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        dated('friends.syncFailedAt'),
        key: const Key('friends-sync-failed'),
        style: TextStyle(color: context.tokens.colors.warning),
      ),
    );
  }
}
