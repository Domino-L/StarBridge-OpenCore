import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../direct_messages/direct_messages_module.dart';
import 'communities_module.dart';
import 'community_invitation_send_controller.dart';
import 'community_invitation_send_copy.dart';
import 'community_invitation_send_port.dart';

/// The chat owns this route. Leaving it or changing account removes the picker;
/// the existing Host outbox retains any delivery already in progress.
Future<void> sendCommunityInvitationInChat(
  BuildContext context,
  CommunitiesModule organizations,
  DirectMessagesModule chat,
) async {
  final port = organizations.port;
  final recipient = chat.selected;
  if (port is! CommunityInvitationSendPort ||
      !(port as CommunityInvitationSendPort).invitationSendingAvailable ||
      recipient == null ||
      !chat.canSend ||
      chat.busy ||
      chat.sending ||
      chat.awaitingConfirmation) {
    return;
  }
  final revision = organizations.accountRevision;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CommunityInvitationSendDialog(
      organizations: organizations,
      port: port as CommunityInvitationSendPort,
      recipient: recipient,
    ),
  );
  void checkContext() {
    if (organizations.accountRevision != revision ||
        chat.selected?.ref != recipient.ref ||
        !chat.canSend) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
  }

  organizations.addListener(checkContext);
  chat.addListener(checkContext);
  try {
    await Navigator.of(context).push(route);
    if (context.mounted &&
        organizations.accountRevision == revision &&
        chat.selected?.ref == recipient.ref) {
      await chat.load(newer: true);
    }
  } finally {
    organizations.removeListener(checkContext);
    chat.removeListener(checkContext);
  }
}

class CommunityInvitationSendDialog extends StatefulWidget {
  const CommunityInvitationSendDialog({
    required this.organizations,
    required this.port,
    required this.recipient,
    super.key,
  });
  final CommunitiesModule organizations;
  final CommunityInvitationSendPort port;
  final Conversation recipient;
  @override
  State<CommunityInvitationSendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<CommunityInvitationSendDialog> {
  late final CommunityInvitationSendController model;
  CommunityCard? selected;
  String t(String key) => invitationSendText(context, key);
  @override
  void initState() {
    super.initState();
    model = CommunityInvitationSendController(widget.port);
    unawaited(model.load());
    unawaited(widget.organizations.refreshJoined());
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([model, widget.organizations]),
    builder: (context, _) {
      final organizations = widget.organizations;
      final rows = organizations.joined
          .where((row) => {'member', 'owner'}.contains(row.relationship))
          .toList();
      final source = rows.where((row) => row.key == selected?.key).firstOrNull;
      final locked = model.locked || model.activeOperationId != null;
      return AlertDialog(
        title: Text(t('sendTitle')),
        content: SizedBox(
          width: 540,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!model.invalidated)
                Text(
                  '${t('sendTo')} ${widget.recipient.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 8),
              Text(t('sendInfo')),
              const SizedBox(height: 12),
              if (model.busy || organizations.joinedBusy)
                const LinearProgressIndicator(),
              if (model.invalidated)
                Text(t('identityUnavailable'))
              else if (model.progress case final progress?)
                Text(
                  t(progress.status),
                  style: TextStyle(
                    color: progress.status == 'sent'
                        ? context.tokens.colors.success
                        : context.tokens.colors.warning,
                  ),
                ),
              if (model.error != null) ...[
                Text(t(model.error!)),
                TextButton(
                  onPressed: model.locked ? null : model.load,
                  child: Text(t('refresh')),
                ),
              ],
              Expanded(
                child: model.invalidated
                    ? const SizedBox.shrink()
                    : !organizations.joinedLoaded && !organizations.joinedBusy
                    ? Center(
                        child: TextButton(
                          onPressed: () => organizations.refreshJoined(),
                          child: Text(t('reloadOrganizations')),
                        ),
                      )
                    : rows.isEmpty && !organizations.joinedBusy
                    ? Center(child: Text(t('noOrganizations')))
                    : ListView(
                        children: [
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: source?.key == row.key
                                    ? context.tokens.colors.accentSoft
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: BorderSide(
                                    color: source?.key == row.key
                                        ? context.tokens.colors.accent
                                        : Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: ListTile(
                                  key: ValueKey('invite-source-${row.key}'),
                                  leading: StandardIcon(
                                    source?.key == row.key
                                        ? StandardIconSemantic.radioButtonChecked
                                        : StandardIconSemantic.radioButtonOff,
                                  ),
                                  title: Text(
                                    row.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  subtitle: row.description.isEmpty
                                      ? null
                                      : Text(
                                          row.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  selected: source?.key == row.key,
                                  onTap: locked
                                      ? null
                                      : () => setState(() => selected = row),
                                ),
                              ),
                            ),
                          if (organizations.joinedNext != null)
                            TextButton(
                              onPressed: locked || organizations.joinedBusy
                                  ? null
                                  : () =>
                                        organizations.refreshJoined(next: true),
                              child: Text(t('moreOrganizations')),
                            ),
                        ],
                      ),
              ),
              if (model.activeOperationId != null &&
                  model.progress?.status != 'sent')
                Text(t('recordsHint')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: model.busy ? null : () => Navigator.pop(context),
            child: Text(t('close')),
          ),
          FilledButton.icon(
            key: const ValueKey('send-organization-invitation'),
            onPressed:
                !model.canStart || organizations.joinedBusy || source == null
                ? null
                : () => model.start(
                    organizationRef: source.targetRef,
                    channel: 'private',
                    destinationRef: widget.recipient.ref,
                    maxUses: 1,
                  ),
            icon: const StandardIcon(StandardIconSemantic.send),
            label: Text(t('send')),
          ),
        ],
      );
    },
  );
}
