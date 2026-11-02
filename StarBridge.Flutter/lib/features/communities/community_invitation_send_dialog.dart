import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../direct_messages/direct_messages_module.dart';
import 'communities_module.dart';
import 'community_invitation_send_controller.dart';
import 'community_invitation_send_copy.dart';
import 'community_invitation_send_port.dart';
import '../common/social_read_activity.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

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
      chat.busy) {
    return;
  }
  final revision = organizations.accountRevision;
  StarBridgeDialogRoute<void>? route;
  bool current() =>
      context.mounted &&
      organizations.accountRevision == revision &&
      chat.selected?.ref == recipient.ref &&
      chat.canSend;
  void checkContext() {
    if (!current()) retireStarBridgeDialog(route);
  }

  organizations.addListener(checkContext);
  chat.addListener(checkContext);
  try {
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: false,
      barrierDismissible: false,
      onRouteCreated: (opened) => route = opened,
      builder: (_) => StarBridgeDialogOwnerGuard(
        isCurrent: current,
        child: CommunityInvitationSendDialog(
          organizations: organizations,
          port: port as CommunityInvitationSendPort,
          recipient: recipient,
        ),
      ),
    );
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
  late final SocialReadActivityBinding _activity;
  late SocialReadActivityBinding _joinedActivity;
  void _bindJoined({required bool initialRead}) {
    final owner = widget.organizations;
    _joinedActivity = SocialReadActivityBinding(
      owner,
      () => owner.joinedBusy,
      initialRead: initialRead && !owner.joinedBusy,
    );
    // An operation already running on the borrowed owner was not opened here.
    if (owner.joinedBusy) {
      _joinedActivity.source = InteractionSource.programmatic;
    }
  }

  CommunityCard? selected;
  String t(String key) => invitationSendText(context, key);
  @override
  void initState() {
    super.initState();
    model = CommunityInvitationSendController(widget.port);
    _activity = SocialReadActivityBinding(
      model,
      () => model.busy,
      initialRead: true,
    );
    _bindJoined(initialRead: true);
    unawaited(model.load());
    unawaited(widget.organizations.refreshJoined());
  }

  @override
  void didUpdateWidget(covariant CommunityInvitationSendDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizations != widget.organizations) {
      _joinedActivity.dispose();
      _bindJoined(initialRead: false);
    }
  }

  @override
  void dispose() {
    _activity.dispose();
    _joinedActivity.dispose();
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
      final activity = model.busy ? _activity : _joinedActivity;
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
                KeyedSubtree(
                  key: ValueKey((model.busy, activity.revision)),
                  child: SocialReadActivity(
                    key: const ValueKey('invitation-send-activity'),
                    source: activity.source,
                    opening: activity.opening,
                    label: t(
                      model.busy
                          ? activity.opening
                                ? 'loadingRecords'
                                : 'working'
                          : 'loadingOrganizations',
                    ),
                    height: 4,
                  ),
                ),
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
                StarBridgeActionButton(
                  controlKey: const Key('invitation-send-refresh-records'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.locked ? null : (_) => model.load(),
                  child: Text(t('refresh')),
                ),
              ],
              Expanded(
                child: model.invalidated
                    ? const SizedBox.shrink()
                    : !organizations.joinedLoaded && !organizations.joinedBusy
                    ? Center(
                        child: StarBridgeActionButton(
                          controlKey: const Key(
                            'invitation-send-reload-organizations',
                          ),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: (_) => organizations.refreshJoined(),
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
                                child: StarBridgeActionRow(
                                  controlKey: ValueKey(
                                    'invite-source-${row.key}',
                                  ),
                                  semanticLabel: row.name,
                                  semanticSelected: source?.key == row.key,
                                  onActivate: locked
                                      ? null
                                      : (_, _) =>
                                            setState(() => selected = row),
                                  child: ListTile(
                                    leading: StandardIcon(
                                      source?.key == row.key
                                          ? StandardIconSemantic
                                                .radioButtonChecked
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
                                  ),
                                ),
                              ),
                            ),
                          if (organizations.joinedNext != null)
                            StarBridgeActionButton(
                              controlKey: const Key(
                                'invitation-send-more-organizations',
                              ),
                              kind: StarBridgeActionKind.quiet,
                              onActivate: locked || organizations.joinedBusy
                                  ? null
                                  : (_) =>
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
          StarBridgeActionButton(
            controlKey: const Key('invitation-send-close'),
            kind: StarBridgeActionKind.quiet,
            onActivate: model.busy
                ? null
                : (source) => dismissStarBridgeDialog(context, source: source),
            child: Text(t('close')),
          ),
          StarBridgeActionButton(
            controlKey: const ValueKey('send-organization-invitation'),
            kind: StarBridgeActionKind.primary,
            onActivate:
                !model.canStart || organizations.joinedBusy || source == null
                ? null
                : (_) => model.start(
                    organizationRef: source.targetRef,
                    channel: 'private',
                    destinationRef: widget.recipient.ref,
                    maxUses: 1,
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StandardIcon(StandardIconSemantic.send),
                const SizedBox(width: 8),
                Text(t('send')),
              ],
            ),
          ),
        ],
      );
    },
  );
}
