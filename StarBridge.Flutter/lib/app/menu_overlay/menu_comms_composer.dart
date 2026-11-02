import 'menu_overlay_locale.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'menu_bridge_style.dart';
import 'menu_comms_view.dart';
import 'menu_chat_widgets.dart';
import '../../features/direct_messages/chat_send_shortcuts.dart';

class MenuCommsComposer extends StatefulWidget {
  const MenuCommsComposer({
    super.key,
    required this.view,
    required this.onCompose,
    this.disconnected = false,
  });
  final MenuCommsView view;
  final bool disconnected;
  final void Function(String action, String key, String text, int revision)
  onCompose;
  @override
  State<MenuCommsComposer> createState() => _MenuCommsComposerState();
}

class _MenuCommsComposerState extends State<MenuCommsComposer> {
  late final _text = TextEditingController(text: widget.view.draft);
  late int _revision = widget.view.draftRevision;
  bool _submitted = false;
  bool _unconfirmed = false;
  Timer? _ackTimer;
  InteractionSource _sendSource = InteractionSource.programmatic;
  int? _sendRevision;
  bool get _canSend =>
      widget.view.canSend &&
      !widget.view.locked &&
      !_submitted &&
      !_unconfirmed &&
      !widget.disconnected &&
      _text.text.trim().isNotEmpty;
  @override
  void didUpdateWidget(MenuCommsComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disconnected) _submitted = false;
    if (widget.view.draftRevision >= _revision) {
      _ackTimer?.cancel();
      _unconfirmed = false;
      _revision = widget.view.draftRevision;
      if (_text.text != widget.view.draft) {
        _text.value = TextEditingValue(
          text: widget.view.draft,
          selection: TextSelection.collapsed(offset: widget.view.draft.length),
        );
      }
      _submitted = false;
    }
  }

  void _act(String action) {
    // Old enabled callbacks can still arrive before the next frame. Do not
    // hand off twice or label a void dispatch as a confirmed transport result.
    if (!mounted || (action == 'send' && !_canSend)) return;
    if (action == 'send') {
      setState(() => _submitted = true);
      _sendSource = currentStarBridgeActivationSource;
      _sendRevision = _revision + 1;
    }
    if (action != 'check') {
      _ackTimer?.cancel();
      _ackTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() {
          _unconfirmed = true;
          _submitted = false;
        });
      });
    }
    widget.onCompose(
      action,
      widget.view.profileKey!,
      _text.text,
      action == 'check' ? _revision : ++_revision,
    );
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Widget _sendingCaption() => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        // This is only the source of this exact, projected send revision. A
        // restored/pushed sending state has no local pointer provenance.
        final source = _sendRevision == widget.view.draftRevision
            ? _sendSource
            : InteractionSource.programmatic;
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source != InteractionSource.pointer,
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.copyWith(
                bodySmall: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 13, height: 1.5),
              ),
            ),
            child: SuiteBusyFrame(
              busy: true,
              child: SuiteBusyLabel(
                menuText(context, 'menu.overlay.comms.sending'),
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: BridgeInk.divider),
      ChatSendShortcuts(
        controller: _text,
        onSend: _canSend ? () => _act('send') : null,
        child: StarBridgeFieldFrame(
          builder: (_, focus) => TextField(
            focusNode: focus,
            key: const ValueKey('menu-message-draft'),
            controller: _text,
            readOnly: widget.view.locked || _submitted,
            minLines: 2,
            maxLines: 3,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.text.length <= 1000 ? newValue : oldValue,
              ),
            ],
            decoration: InputDecoration(
              hintText: menuText(context, 'menu.overlay.comms.input'),
            ),
            onChanged: (_) {
              setState(() {});
              _act('edit');
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (widget.disconnected || _unconfirmed || widget.view.delivery != 'idle')
        Semantics(
          liveRegion: true,
          child: widget.disconnected
              ? BridgeCaption(
                  menuText(context, 'menu.overlay.comms.disconnected'),
                )
              : _unconfirmed
              ? BridgeCaption(
                  menuText(context, 'menu.overlay.comms.notResponding'),
                )
              : widget.view.delivery == 'sending'
              ? _sendingCaption()
              : BridgeCaption(switch (widget.view.delivery) {
                  'sent' => menuText(context, 'menu.overlay.comms.sent'),
                  'request_sent' => menuText(
                    context,
                    'menu.overlay.comms.requestSent',
                  ),
                  'unknown' => menuText(
                    context,
                    'menu.overlay.comms.sendUnknown',
                  ),
                  'rejected' => menuText(
                    context,
                    'menu.overlay.comms.sendRejected',
                  ),
                  'limit' => menuText(context, 'menu.overlay.comms.draftLimit'),
                  _ => '',
                }),
        ),
      if (!widget.view.canSend &&
          !widget.view.busy &&
          !widget.view.locked &&
          widget.view.delivery == 'idle')
        BridgeCaption(menuText(context, 'menu.overlay.comms.checkPermissions')),
      const SizedBox(height: 8),
      MenuChatSendBar(
        length: _text.text.length,
        sendKey: const ValueKey('menu-message-send'),
        onSend: _canSend ? () => _act('send') : null,
        leading:
            widget.disconnected ||
                _unconfirmed ||
                widget.view.delivery == 'unknown' ||
                (!widget.view.canSend &&
                    !widget.view.locked &&
                    !widget.view.busy)
            ? StarBridgeActionButton(
                kind: StarBridgeActionKind.secondary,
                controlKey: const ValueKey('menu-message-check'),
                onActivate: (_) => _act('check'),
                child: Text(
                  menuText(context, 'menu.overlay.comms.checkLatest'),
                ),
              )
            : null,
      ),
    ],
  );
}
