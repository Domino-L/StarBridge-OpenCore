import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';

/// Reminder surface only: no chat bodies or duplicated membership actions.
class RoomActivityPage extends StatelessWidget {
  const RoomActivityPage({required this.module, super.key});
  final PartyRoomsModule module;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: module,
    builder: (context, _) {
      final strings = AppStrings.of(context);
      String t(String key) => strings.text('rooms.activity.$key');
      final ready = module.state == RoomReadState.ready;
      return ListView(
        padding: EdgeInsets.all(context.tokens.space.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: module.busy ? null : module.refresh,
                child: Text(strings.text('rooms.refresh')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t('hint')),
          const SizedBox(height: 20),
          if (module.previewScene != null)
            Text(strings.text('rooms.example.notice')),
          if (!ready)
            Text(
              strings.text(switch (module.state) {
                RoomReadState.signedOut => 'rooms.signedOut',
                RoomReadState.loading => 'rooms.loading',
                _ => 'rooms.error.${module.failure}',
              }),
            )
          else ...[
            if (module.invitationCount == 0 && module.applicationCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(t('empty')),
              ),
            for (final invitation in module.directory!.receivedInvitations)
              Card.outlined(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      leading: StarBridgeIcon(
                        StarBridgeIconSemantic.room,
                        color: context.tokens.colors.info,
                      ),
                      title: Text(
                        invitation.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text('${t('invitedBy')}${invitation.inviter}'),
                    ),
                    _openAction(context, 'invite-${invitation.id}', t('open')),
                  ],
                ),
              ),
            if (module.applicationCount > 0)
              Card.outlined(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      leading: StarBridgeIcon(
                        StarBridgeIconSemantic.pending,
                        color: context.tokens.colors.info,
                      ),
                      title: Text(
                        strings.text('rooms.action.applications'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        '${module.selectedRoom?.title ?? ''} · ${module.applicationCount}',
                      ),
                    ),
                    _openAction(context, 'applications', t('open')),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );

  Widget _openAction(BuildContext context, String id, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: OutlinedButton(
        key: ValueKey('room-activity-open-$id'),
        style: semanticActionStyle(
          context,
          ActionTone.info,
          emphasis: ActionEmphasis.outlined,
        ),
        onPressed: () =>
            Actions.invoke(context, const OpenDestinationIntent('/rooms')),
        child: Text(label),
      ),
    ),
  );
}
