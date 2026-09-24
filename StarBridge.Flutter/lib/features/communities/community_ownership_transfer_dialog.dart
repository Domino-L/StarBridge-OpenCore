import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
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
  String t(String key) => ownershipTransferText(context, key);
  @override
  void initState() {
    super.initState();
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
    unawaited(_contextSubscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final member = model.snapshot;
    return PopScope(
      canPop: !model.submitting,
      child: AlertDialog(
        icon: StandardIcon(StandardIconSemantic.swapHoriz, color: context.tokens.colors.danger),
        title: Text(t('transfer')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.loading || model.submitting)
                  const LinearProgressIndicator(),
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
          TextButton(
            onPressed: model.submitting
                ? null
                : () => Navigator.pop(context, false),
            child: Text(t(model.invalidated ? 'close' : 'cancel')),
          ),
          if (!model.invalidated &&
              (model.error != null || model.requiresRetryConfirmation))
            TextButton(
              onPressed: model.loading || model.submitting ? null : model.load,
              child: Text(t('reload')),
            ),
          FilledButton(
            style: semanticActionStyle(
              context,
              ActionTone.danger,
              emphasis: ActionEmphasis.filled,
            ),
            onPressed: !model.canTransfer
                ? null
                : () async {
                    await model.transfer(
                      confirmUncertainRetry: model.requiresRetryConfirmation,
                    );
                    if (mounted && model.transferred) {
                      Navigator.pop(this.context, true);
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
