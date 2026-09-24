import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import 'direct_messages_module.dart';
import 'chat_send_shortcuts.dart';

class DirectMessageComposer extends StatefulWidget {
  const DirectMessageComposer(this.module, {this.onSend, super.key});
  final DirectMessagesModule module;
  final VoidCallback? onSend;
  @override
  State<DirectMessageComposer> createState() => _DirectMessageComposerState();
}

class _DirectMessageComposerState extends State<DirectMessageComposer> {
  late final _controller = TextEditingController(text: widget.module.draft);

  @override
  void didUpdateWidget(covariant DirectMessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.module.draft) {
      _controller.text = widget.module.draft;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final onSend = widget.onSend;
    String t(String key) => AppStrings.of(context).text('direct.$key');
    if (!module.supportsSending) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (module.sendStatus != null)
            Semantics(
              liveRegion: true,
              child: Text(t('send.${module.sendStatus}')),
            ),
          if (!module.canSend && !module.busy)
            Text(
              t('send.notAllowed'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          ChatSendShortcuts(
            controller: _controller,
            onSend: () {
              if (module.readyToSend) (onSend ?? module.send)();
            },
            child: TextFormField(
              key: ValueKey('${module.selected?.ref}:${module.draftRevision}'),
              controller: _controller,
              enabled: !module.sending && !module.awaitingConfirmation,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              // Count UTF-16 code units, matching the existing .NET contract.
              maxLengthEnforcement: MaxLengthEnforcement.none,
              onChanged: module.editDraft,
              decoration: InputDecoration(
                labelText: t('send.input'),
                counterText: '${module.draft.length}/1000',
                errorText: module.draft.trim().length > 1000
                    ? t('send.tooLong')
                    : null,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('send.shortcut'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton(
                onPressed: module.readyToSend ? onSend ?? module.send : null,
                child: Text(t(module.sending ? 'send.sending' : 'send.action')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
