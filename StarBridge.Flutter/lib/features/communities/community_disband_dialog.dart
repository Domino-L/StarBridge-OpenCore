import 'dart:async';

import 'package:flutter/material.dart';

import '../common/social_read_activity.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'community_disband_controller.dart';
import 'community_disband_copy.dart';
import 'community_disband_port.dart';

class CommunityDisbandDialog extends StatefulWidget {
  const CommunityDisbandDialog({
    super.key,
    required this.port,
    required this.targetRef,
    this.contextInvalidations,
  });
  final CommunityDisbandPort port;
  final String targetRef;
  final Stream<void>? contextInvalidations;
  @override
  State<CommunityDisbandDialog> createState() => _CommunityDisbandDialogState();
}

class _CommunityDisbandDialogState extends State<CommunityDisbandDialog> {
  late final model = CommunityDisbandController(widget.port, widget.targetRef);
  final password = TextEditingController();
  StreamSubscription<void>? _subscription;
  late final SocialReadActivityBinding _reading, _sending;
  String t(String key) => disbandText(context, key);
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
      () => model.sending,
      initialRead: false,
    );
    model.addListener(_changed);
    _subscription = widget.contextInvalidations?.listen(
      (_) => model.invalidate(),
    );
    unawaited(model.load());
  }

  void _changed() {
    if (model.invalidated) password.clear();
    if (mounted) setState(() {});
  }

  Future<void> _confirm() async {
    final credential = password.text;
    password.clear();
    await model.confirm(credential);
    if (mounted && !model.invalidated && model.outcome?.status == 'accepted') {
      dismissStarBridgeDialog(
        context,
        source: currentStarBridgeActivationSource,
        result: true,
      );
    }
  }

  @override
  void dispose() {
    _reading.dispose();
    _sending.dispose();
    password.clear();
    password.dispose();
    unawaited(_subscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = model.loading ? _reading : _sending;
    final preview = model.preview;
    return PopScope(
      canPop: !model.sending,
      child: AlertDialog(
        title: Text(t('title')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.loading || model.sending)
                  KeyedSubtree(
                    key: ValueKey((model.loading, activity.revision)),
                    child: SocialReadActivity(
                      key: const ValueKey('disband-activity'),
                      source: activity.source,
                      opening: activity.opening,
                      label: t(
                        model.loading ? 'activityLoading' : 'activitySending',
                      ),
                      height: 4,
                    ),
                  ),
                if (preview != null) ...[
                  Text(
                    preview.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('members')
                        .replaceAll('{count}', '${preview.memberCount}'),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.tokens.colors.danger),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(t('consequence')),
                  ),
                  const SizedBox(height: 16),
                  if (preview.isExample)
                    Text(t('example'))
                  else ...[
                    StarBridgeFieldFrame(
                      builder: (_, focus) => TextField(
                        key: const Key('community-disband-password'),
                        focusNode: focus,
                        controller: password,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        enabled: !model.sending,
                        maxLength: 4096,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: t('password'),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('credential'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (!preview.canDisband) ...[
                    const SizedBox(height: 12),
                    Text(t('notAllowed')),
                  ],
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
            controlKey: const Key('community-disband-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: model.sending
                ? null
                : (source) => dismissStarBridgeDialog(
                    context,
                    source: source,
                    result: false,
                  ),
            child: Text(
              t(
                model.outcome == null && !model.invalidated
                    ? 'cancel'
                    : 'close',
              ),
            ),
          ),
          if (preview == null &&
              !model.invalidated &&
              model.outcome?.status != 'unknown')
            StarBridgeActionButton(
              controlKey: const Key('community-disband-reload'),
              kind: StarBridgeActionKind.quiet,
              onActivate: model.loading || model.sending
                  ? null
                  : (_) => model.load(),
              child: Text(t('reload')),
            ),
          if (preview != null)
            StarBridgeActionButton(
              controlKey: const Key('community-disband-confirm'),
              kind: StarBridgeActionKind.primary,
              tone: ActionTone.danger,
              onActivate:
                  model.canConfirm &&
                      (preview.isExample || password.text.trim().isNotEmpty)
                  ? (_) => _confirm()
                  : null,
              child: Text(t('action')),
            ),
        ],
      ),
    );
  }
}
