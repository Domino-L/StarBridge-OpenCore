import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
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
  String t(String key) => disbandText(context, key);
  @override
  void initState() {
    super.initState();
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
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    password.clear();
    password.dispose();
    unawaited(_subscription?.cancel());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  const LinearProgressIndicator(),
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
                    TextField(
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
          TextButton(
            onPressed: model.sending
                ? null
                : () => Navigator.pop(context, false),
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
            TextButton(
              onPressed: model.loading || model.sending ? null : model.load,
              child: Text(t('reload')),
            ),
          if (preview != null)
            FilledButton(
              style: semanticActionStyle(
                context,
                ActionTone.danger,
                emphasis: ActionEmphasis.filled,
              ),
              onPressed:
                  model.canConfirm &&
                      (preview.isExample || password.text.trim().isNotEmpty)
                  ? _confirm
                  : null,
              child: Text(t('action')),
            ),
        ],
      ),
    );
  }
}
