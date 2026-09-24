import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    if (action == 'send') setState(() => _submitted = true);
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: BridgeInk.divider),
      ChatSendShortcuts(
        controller: _text,
        onSend: _canSend ? () => _act('send') : null,
        child: TextField(
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
          decoration: const InputDecoration(hintText: '输入消息'),
          onChanged: (_) {
            setState(() {});
            _act('edit');
          },
        ),
      ),
      const SizedBox(height: 8),
      if (widget.disconnected)
        const BridgeCaption('通讯连接中断，草稿暂未确认保存。恢复后请核对会话，勿重复发送。')
      else if (_unconfirmed)
        const BridgeCaption('通讯暂未响应，草稿暂未确认保存。请核对最新消息，勿重复发送。')
      else if (widget.view.delivery != 'idle')
        BridgeCaption(switch (widget.view.delivery) {
          'sending' => '正在发送…',
          'sent' => '已发送',
          'request_sent' => '消息请求已发送，等待对方回应。',
          'unknown' => '发送结果尚未确认。请核对最新消息，暂勿重复发送。',
          'rejected' => '未能发送，草稿已保留。请核对会话权限后重试。',
          'limit' => '已保留 32 个会话草稿，请先清空一个草稿。',
          _ => '',
        }),
      if (!widget.view.canSend &&
          !widget.view.busy &&
          !widget.view.locked &&
          widget.view.delivery == 'idle')
        const BridgeCaption('当前无法发送，请刷新会话确认权限。'),
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
            ? OutlinedButton(
                key: const ValueKey('menu-message-check'),
                onPressed: () => _act('check'),
                child: const Text('核对最新消息'),
              )
            : null,
      ),
    ],
  );
}
