import '../../design_system/icons/standard_icon.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../common/social_read_activity.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_member_removal_port.dart';
import 'community_member_removal_controller.dart';
import 'community_member_removal_copy.dart';

class CommunityMemberRemovalDialog extends StatefulWidget {
  const CommunityMemberRemovalDialog({
    super.key,
    required this.port,
    required this.targetRef,
    required this.memberRef,
    required this.organizationName,
    this.contextInvalidations,
  });
  final CommunityMemberRemovalPort port;
  final String targetRef, memberRef, organizationName;
  final Stream<void>? contextInvalidations;
  @override
  State<CommunityMemberRemovalDialog> createState() =>
      _CommunityMemberRemovalDialogState();
}

class _CommunityMemberRemovalDialogState
    extends State<CommunityMemberRemovalDialog> {
  late final model = CommunityMemberRemovalController(
    widget.port,
    widget.targetRef,
    widget.memberRef,
  );
  StreamSubscription<void>? _contextSubscription;
  late final SocialReadActivityBinding _reading, _sending;
  String t(String key) => memberRemovalText(context, key);
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
          StandardIconSemantic.personRemove,
          color: context.tokens.colors.danger,
        ),
        title: Text(t('remove')),
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
                      key: const ValueKey('removal-activity'),
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
                  Text(member.canRemove ? t('consequence') : t('protected')),
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
            controlKey: const Key('member-remove-cancel'),
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
              controlKey: const Key('member-remove-reload'),
              kind: StarBridgeActionKind.quiet,
              onActivate: model.loading || model.submitting
                  ? null
                  : (_) => model.load(),
              child: Text(t('reload')),
            ),
          StarBridgeActionButton(
            controlKey: const Key('member-remove-confirm'),
            kind: StarBridgeActionKind.primary,
            tone: ActionTone.danger,
            onActivate: !model.canRemove
                ? null
                : (source) async {
                    await model.remove(
                      confirmUncertainRetry: model.requiresRetryConfirmation,
                    );
                    if (mounted && model.removed) {
                      dismissStarBridgeDialog(
                        this.context,
                        source: source,
                        result: true,
                      );
                    }
                  },
            child: Text(
              t(model.requiresRetryConfirmation ? 'retry' : 'remove'),
            ),
          ),
        ],
      ),
    );
  }
}
