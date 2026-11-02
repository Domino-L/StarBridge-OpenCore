import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_invitation_send_controller.dart';
import 'community_invitation_send_copy.dart';
import 'community_invitation_send_port.dart';
import '../common/social_read_activity.dart';

class CommunityInvitationOutboxDialog extends StatefulWidget {
  const CommunityInvitationOutboxDialog({required this.port, super.key});
  final CommunityInvitationSendPort port;
  @override
  State<CommunityInvitationOutboxDialog> createState() => _OutboxState();
}

class _OutboxState extends State<CommunityInvitationOutboxDialog> {
  late final CommunityInvitationSendController model;
  late final SocialReadActivityBinding _activity;
  StarBridgeDialogRoute<bool>? _retryRoute;
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
    unawaited(model.load());
  }

  @override
  void dispose() {
    retireStarBridgeDialog(_retryRoute);
    _activity.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> _retry(CommunityInvitationOperation row) async {
    if (model.locked || _retryRoute != null) return;
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      useRootNavigator: false,
      builder: (_) => AnimatedBuilder(
        animation: model,
        builder: (context, _) => AlertDialog(
          title: Text(t('retryTitle')),
          content: Text(
            t(model.invalidated ? 'identityUnavailable' : 'retryBody'),
          ),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('community-outbox-retry-cancel'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(t('cancel')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('community-outbox-retry-confirm'),
              onActivate: model.invalidated
                  ? null
                  : (source) => dismissStarBridgeDialog(
                      context,
                      source: source,
                      result: true,
                    ),
              child: Text(t('retry')),
            ),
          ],
        ),
      ),
      onRouteCreated: (route) => _retryRoute = route,
    );
    _retryRoute = null;
    if (!mounted || confirmed != true || model.locked) return;
    await model.recover(
      row.operationId,
      action: InvitationRecoveryAction.retryDelivery,
      retryConfirmed: true,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => AlertDialog(
      title: Text(t('records')),
      content: SizedBox(
        width: 660,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('intro')),
            const SizedBox(height: 12),
            if (model.busy)
              KeyedSubtree(
                key: ValueKey(_activity.revision),
                child: SocialReadActivity(
                  key: const ValueKey('outbox-activity'),
                  source: _activity.source,
                  opening: _activity.opening,
                  label: t(_activity.opening ? 'loadingRecords' : 'working'),
                  height: 4,
                ),
              ),
            if (model.invalidated)
              Text(
                t('identityUnavailable'),
                style: TextStyle(color: context.tokens.colors.warning),
              )
            else ...[
              if (model.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    t(model.error!),
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ),
              if (model.progress case final result?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    t(
                      result.error == 'localRecoveryUnavailable'
                          ? result.error!
                          : result.status,
                    ),
                    style: TextStyle(
                      color: result.status == 'sent'
                          ? context.tokens.colors.success
                          : context.tokens.colors.warning,
                    ),
                  ),
                ),
              Expanded(
                child: model.loaded && model.items.isEmpty
                    ? Center(child: Text(t('empty')))
                    : ListView.separated(
                        itemCount: model.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _record(model.items[index]),
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('community-outbox-refresh'),
          onActivate: model.locked ? null : (_) => model.load(),
          child: Text(t('refresh')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('community-outbox-close'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(t('close')),
        ),
      ],
    ),
  );

  Widget _record(CommunityInvitationOperation row) {
    final current = model.progress?.operationId == row.operationId
        ? model.progress
        : null;
    final sent = row.phase == 'sent' || current?.status == 'sent';
    final date = row.requestedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StandardIcon(
                row.channel == 'private'
                    ? StandardIconSemantic.chatBubble
                    : StandardIconSemantic.meetingRoom,
                size: 18,
              ),
              Text(
                row.sourceName.isEmpty ? t('organization') : row.sourceName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const StandardIcon(StandardIconSemantic.arrowForward, size: 16),
              Text(
                row.destinationName.isEmpty
                    ? t('recipient')
                    : row.destinationName,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${t(row.channel)} · ${material.formatFullDate(date)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            t(sent ? 'sent' : row.phase),
            style: TextStyle(
              color: sent
                  ? context.tokens.colors.success
                  : context.tokens.colors.warning,
            ),
          ),
          if (!sent)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: ValueKey(
                    'community-outbox-check-${row.operationId}',
                  ),
                  onActivate: model.locked
                      ? null
                      : (_) => model.recover(row.operationId),
                  child: Text(t('check')),
                ),
                if (row.phase == 'sending')
                  StarBridgeActionButton(
                    controlKey: ValueKey(
                      'community-outbox-retry-${row.operationId}',
                    ),
                    onActivate: model.locked ? null : (_) => _retry(row),
                    child: Text(t('retry')),
                  )
                else
                  StarBridgeActionButton(
                    controlKey: ValueKey(
                      'community-outbox-continue-${row.operationId}',
                    ),
                    onActivate: model.locked
                        ? null
                        : (_) => model.recover(
                            row.operationId,
                            action: InvitationRecoveryAction.continueSending,
                          ),
                    child: Text(t('continue')),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
