import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../common/social_read_activity.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_ownership_transfer_port.dart';
import 'community_ownership_transfer_controller.dart';
import 'community_ownership_transfer_copy.dart';

class CommunityOwnershipTransferDialog extends StatefulWidget {
  const CommunityOwnershipTransferDialog({
    super.key,
    required this.port,
    required this.targetRef,
    required this.memberRef,
    required this.organizationName,
    this.contextInvalidations,
  });
  final CommunityOwnershipTransferPort port;
  final String targetRef, memberRef, organizationName;
  final Stream<void>? contextInvalidations;
  @override
  State<CommunityOwnershipTransferDialog> createState() =>
      _CommunityOwnershipTransferDialogState();
}

class _CommunityOwnershipTransferDialogState
    extends State<CommunityOwnershipTransferDialog> {
  late final model = CommunityOwnershipTransferController(
    widget.port,
    widget.targetRef,
    widget.memberRef,
  );
  StreamSubscription<void>? _contextSubscription;
  late final SocialReadActivityBinding _reading, _sending;
  String t(String key) => ownershipTransferText(context, key);
  @override
  void initState() {
    super.initState();
    _reading = SocialReadActivityBinding(
      model,
      () => model.loading,
      initialRead: true,
    );
    _sending = SocialReadActivityBinding(
      model,
      () => model.submitting,
      initialRead: false,
    );
    model.addListener(_changed);
    _contextSubscription = widget.contextInvalidations?.listen(
      (_) => model.invalidate(),
    );
    unawaited(model.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _reading.dispose();
    _sending.dispose();
    unawaited(_contextSubscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = model.loading ? _reading : _sending;
    final member = model.snapshot;
    return PopScope(
      canPop: !model.submitting,
      child: AlertDialog(
        icon: StandardIcon(
          StandardIconSemantic.swapHoriz,
          color: context.tokens.colors.danger,
        ),
        title: Text(t('transfer')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.loading || model.submitting)
                  KeyedSubtree(
                    key: ValueKey((model.loading, activity.revision)),
                    child: SocialReadActivity(
                      key: const ValueKey('transfer-activity'),
                      source: activity.source,
                      opening: activity.opening,
                      label: t(
                        model.loading ? 'activityLoading' : 'activitySending',
                      ),
                      height: 4,
                    ),
                  ),
                if (member != null) ...[
                  Text(
                    member.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    widget.organizationName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (member.roleTitle.isNotEmpty)
                    Text(
                      member.roleTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    member.canTransfer
                        ? '${t('consequence')}\n${t('formerRole').replaceAll('{role}', member.formerOwnerRoleTitle)}'
                        : t('protected'),
                  ),
                ],
                if (model.requiresRetryConfirmation) ...[
                  const SizedBox(height: 12),
                  Text(
                    t('retryHelp'),
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ],
                if (model.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    t(model.error!),
                    style: TextStyle(color: context.tokens.colors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('member-transfer-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: model.submitting
                ? null
                : (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: false,
                  ),
            child: Text(t(model.invalidated ? 'close' : 'cancel')),
          ),
          if (!model.invalidated &&
              (model.error != null || model.requiresRetryConfirmation))
            StarBridgeActionButton(
              controlKey: const Key('member-transfer-reload'),
              kind: StarBridgeActionKind.quiet,
              onActivate: model.loading || model.submitting
                  ? null
                  : (_) => model.load(),
              child: Text(t('reload')),
            ),
          StarBridgeActionButton(
            controlKey: const Key('member-transfer-confirm'),
            kind: StarBridgeActionKind.primary,
            tone: ActionTone.danger,
            onActivate: !model.canTransfer
                ? null
                : (source) async {
                    await model.transfer(
                      confirmUncertainRetry: model.requiresRetryConfirmation,
                    );
                    if (mounted && model.transferred) {
                      dismissStarBridgeDialog(
                        this.context,
                        source: source,
                        result: true,
                      );
                    }
                  },
            child: Text(
              t(model.requiresRetryConfirmation ? 'retry' : 'confirm'),
            ),
          ),
        ],
      ),
    );
  }
}
