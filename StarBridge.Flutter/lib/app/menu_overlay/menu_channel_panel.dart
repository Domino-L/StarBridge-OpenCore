import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_chat_composer.dart';
import '../../features/communities/community_local_message_tile.dart';
import 'menu_chat_widgets.dart';
import 'menu_inline_avatar.dart';
import 'menu_avatar_actions.dart';
import 'menu_loading.dart';
import '../../features/direct_messages/chat_send_shortcuts.dart';
import 'menu_feature_view.dart';
import 'menu_room_preset_control.dart';
import 'menu_organization_directory.dart';
import 'menu_visible_receipts.dart';
import '../../features/party_rooms/room_system_message.dart';
import '../../features/party_rooms/room_chat_composer.dart';

/// One channel's editor/scroll state; no service, account or room references.
class MenuChannelPanel extends StatefulWidget {
  const MenuChannelPanel({
    super.key,
    required this.view,
    required this.onAction,
    required this.active,
    this.directoryAsPlaceholder = false,
    this.embeddedOrganization = false,
    this.embeddedRoom = false,
    this.onProfile,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  final bool active;
  final bool directoryAsPlaceholder;
  final bool embeddedOrganization;
  final bool embeddedRoom;
  final ValueChanged<String>? onProfile;
  @override
  State<MenuChannelPanel> createState() => _MenuChannelPanelState();
}

class _MenuChannelPanelState extends State<MenuChannelPanel> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  int? _submittedAt;
  String? _submittedKey, _submittedText;
  String? _restoringKey, _restoringText;
  String _scope = '';
  MenuFeatureView? _lastReady;
  bool _newMessages = false;
  @override
  void didUpdateWidget(MenuChannelPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.view;
    if (_scope.isNotEmpty && next.scope.isNotEmpty && _scope != next.scope) {
      _draft.clear();
      _submittedAt = null;
      _submittedKey = _submittedText = null;
      _restoringKey = _restoringText = null;
      _lastReady = null;
      _newMessages = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    } else if (_submittedKey != null && next.chat?.outbox != null) {
      if (next.chat!.outbox!.acceptedAction == _submittedKey) {
        if (_draft.text == _submittedText) _draft.clear();
        _submittedKey = _submittedText = null;
      } else if (next.rejectedAction == _submittedKey) {
        _submittedKey = _submittedText = null;
      }
    } else if (_submittedAt != null &&
        next.state == 'ready' &&
        !next.busy &&
        next.chat != null) {
      if (next.chat!.revision > _submittedAt!) {
        _draft.clear();
        _submittedAt = null;
      } else if (next.chat!.status == 'rejected' ||
          next.chat!.status == 'unknown') {
        _submittedAt = null;
      }
    }
    if (_restoringKey != null) {
      if (next.chat?.outbox?.acceptedAction == _restoringKey) {
        _restoringKey = _restoringText = null;
      } else if (next.rejectedAction == _restoringKey) {
        if (_draft.text == _restoringText) _draft.clear();
        _restoringKey = _restoringText = null;
      }
    }
    final previous = oldWidget.view;
    if (previous.scope == next.scope &&
        previous.chat != null &&
        next.chat != null &&
        next.rows.length > previous.rows.length &&
        previous.chat!.messages.lastOrNull != next.chat!.messages.lastOrNull &&
        _scroll.hasClients &&
        _scroll.offset > 48) {
      final offset = _scroll.offset, extent = _scroll.position.maxScrollExtent;
      _newMessages = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(
          (offset + _scroll.position.maxScrollExtent - extent).clamp(
            0,
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.view;
    if (raw.scope.isNotEmpty) _scope = raw.scope;
    if (raw.state == 'ready' && raw.chat != null) _lastReady = raw;
    final view = raw.state == 'loading' && _lastReady?.scope == raw.scope
        ? _lastReady!
        : raw;
    final chat = view.chat;
    final busy = raw.busy || raw.state != 'ready';
    if (view.organization?.tab == 'directory') {
      if (widget.directoryAsPlaceholder) {
        return const Center(child: Text('从左侧选择会话'));
      }
      return MenuOrganizationDirectory(view: view, onAction: widget.onAction);
    }
    if (chat == null) {
      return MenuFeaturePanel(view: view, onAction: widget.onAction);
    }
    final send = view.buttons.where((a) => a.label == '发送消息').firstOrNull;
    final outbox = chat.outbox;
    final locals = outbox?.messages ?? const [];
    final canSend =
        widget.active &&
        view.state == 'ready' &&
        !busy &&
        send != null &&
        chat.status != 'unknown' &&
        _submittedAt == null &&
        _submittedKey == null &&
        _restoringKey == null &&
        _draft.text.trim().length <= (send.limit) &&
        (_draft.text.trim().isNotEmpty || chat.preset?.draftName != null);
    void submit() {
      // Multiple input events can use the previous frame's enabled callback.
      // Never replace the first handoff's text/key before its acknowledgement.
      if (!canSend ||
          _submittedAt != null ||
          _submittedKey != null ||
          _restoringKey != null) {
        return;
      }
      setState(() {
        if (outbox == null) {
          _submittedAt = chat.revision;
        } else {
          _submittedKey = send.key;
          _submittedText = _draft.text;
        }
      });
      widget.onAction(send.key, _draft.text);
      if (outbox != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    }

    final composer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedRoom) const Divider(),
        if (widget.embeddedRoom)
          RoomChatComposer(
            leadingAction: chat.preset == null
                ? null
                : MenuRoomPresetControl(
                    view: chat.preset!,
                    scope: view.scope,
                    enabled:
                        widget.active &&
                        !busy &&
                        _submittedAt == null &&
                        chat.status != 'unknown',
                    dispatch: widget.onAction,
                  ),
            attachment: chat.preset?.draftName == null
                ? null
                : MenuRoomPresetAttachment(
                    view: chat.preset!,
                    enabled:
                        widget.active &&
                        !busy &&
                        _submittedAt == null &&
                        chat.status != 'unknown',
                    dispatch: widget.onAction,
                  ),
            controller: _draft,
            readOnly:
                _restoringKey != null ||
                outbox == null &&
                    (busy || _submittedAt != null || chat.status == 'unknown'),
            inputKey: const ValueKey('menu-channel-draft'),
            sendKey: const ValueKey('menu-channel-send'),
            onChanged: (_) => setState(() {}),
            onSend: canSend ? submit : null,
          )
        else if (widget.embeddedOrganization)
          CommunityChatComposer(
            maxLength: send?.limit ?? (widget.embeddedRoom ? 300 : 1000),
            controller: _draft,
            enabled: true,
            readOnly:
                _restoringKey != null ||
                outbox == null &&
                    (busy || _submittedAt != null || chat.status == 'unknown'),
            inputKey: const ValueKey('menu-channel-draft'),
            sendKey: const ValueKey('menu-channel-send'),
            onChanged: (_) => setState(() {}),
            onSend: canSend ? submit : null,
          )
        else ...[
          ChatSendShortcuts(
            controller: _draft,
            onSend: canSend ? submit : null,
            child: TextField(
              key: const ValueKey('menu-channel-draft'),
              controller: _draft,
              readOnly:
                  _restoringKey != null ||
                  outbox == null &&
                      (busy ||
                          _submittedAt != null ||
                          chat.status == 'unknown'),
              minLines: 2,
              maxLines: 3,
              inputFormatters: [
                LengthLimitingTextInputFormatter(send?.limit ?? 1000),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '输入消息'),
            ),
          ),
          MenuChatSendBar(
            maxLength: send?.limit ?? 1000,
            length: _draft.text.length,
            sendKey: const ValueKey('menu-channel-send'),
            onSend: canSend ? submit : null,
          ),
        ],
        if (send == null &&
            locals.isEmpty &&
            chat.availability == 'denied' &&
            chat.status != 'unknown' &&
            !view.refreshing)
          const Text('当前频道不可发送消息，请刷新确认权限。'),
        if (_submittedAt != null) const Text('正在确认发送结果，请勿重复提交。'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget content = Padding(
          padding: widget.embeddedRoom
              ? EdgeInsets.zero
              : const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.embeddedOrganization && !widget.embeddedRoom)
                MenuChatHeader(
                  title: view.title,
                  subtitle: widget.directoryAsPlaceholder ? '组织频道' : '',
                  portrait: MenuInlineAvatar(
                    name: view.title,
                    source: view.organization?.logo,
                  ),
                  trailing: TextButton(
                    onPressed: busy
                        ? null
                        : () => widget.onAction('refresh', ''),
                    child: const Text('刷新'),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final action in view.buttons.where(
                    (a) =>
                        a != send &&
                        (!(widget.embeddedOrganization ||
                                widget.embeddedRoom) ||
                            const {
                              '较早消息',
                              '最新消息',
                              '已核对当前结果',
                              '清除本机记录',
                              '重试已读同步',
                            }.contains(a.label)) &&
                        (!widget.directoryAsPlaceholder ||
                            !const {'更多组织会话', '组织会话首页'}.contains(a.label)),
                  ))
                    MenuFeatureAction(
                      key: ValueKey('${view.scope}/${action.label}'),
                      action: action,
                      enabled: !busy,
                      onAction: widget.onAction,
                    ),
                ],
              ),
              if (view.notice.isNotEmpty)
                Text(
                  view.notice,
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
              if (raw.state == 'loading' || raw.refreshing) const MenuLoading(),
              Expanded(
                child: MenuVisibleReceipts(
                  active: widget.active && !busy,
                  tokens: chat.receipts,
                  onRead: (key) => widget.onAction(key, ''),
                  builder: (anchors) => view.rows.isEmpty && locals.isEmpty
                      ? const Center(child: Text('暂无消息'))
                      : Align(
                          alignment: Alignment.topCenter,
                          child: MenuChatScroll(
                            controller: _scroll,
                            child: ListView.builder(
                              key: const ValueKey('menu-channel-history'),
                              controller: _scroll,
                              reverse: true,
                              shrinkWrap: widget.embeddedRoom,
                              itemCount: view.rows.length + locals.length,
                              itemBuilder: (context, reversed) {
                                if (reversed < locals.length) {
                                  final local =
                                      locals[locals.length - 1 - reversed];
                                  return CommunityLocalMessageTile.presentation(
                                    key: ValueKey('${view.scope}/${local.id}'),
                                    text: local.text,
                                    state: local.state,
                                    error: local.error,
                                    createdAt: local.time,
                                    avatar: chat.ownAvatar,
                                    composerOccupied: _draft.text.isNotEmpty,
                                    onRetry:
                                        !busy &&
                                            _restoringKey == null &&
                                            local.retry != null
                                        ? () =>
                                              widget.onAction(local.retry!, '')
                                        : null,
                                    onCheck: !busy
                                        ? () => widget.onAction('refresh', '')
                                        : null,
                                    onRestore:
                                        !busy &&
                                            _restoringKey == null &&
                                            local.restore != null &&
                                            _draft.text.isEmpty
                                        ? () {
                                            if (_restoringKey != null ||
                                                _draft.text.isNotEmpty) {
                                              return;
                                            }
                                            setState(() {
                                              _restoringKey = local.restore;
                                              _restoringText = local.text;
                                              _draft.text = local.text;
                                            });
                                            widget.onAction(local.restore!, '');
                                          }
                                        : null,
                                  );
                                }
                                final index =
                                        view.rows.length -
                                        1 -
                                        (reversed - locals.length),
                                    row = view.rows[index],
                                    meta = chat.messages[index];
                                final time = meta.time.toLocal();
                                if (chat.systemMessages.contains(index)) {
                                  return KeyedSubtree(
                                    key: anchors[index],
                                    child: RoomSystemMessage(
                                      text: row.detail,
                                      time: meta.time,
                                    ),
                                  );
                                }
                                return KeyedSubtree(
                                  key: anchors[index],
                                  child: MenuChatMessage(
                                    incoming: !meta.self,
                                    sender: meta.self ? '我' : row.title,
                                    portrait: MenuAvatarActions(
                                      name: meta.self ? '我' : row.title,
                                      onProfile:
                                          widget.onProfile == null ||
                                              chat.profiles[index] == null
                                          ? null
                                          : () => widget.onProfile!(
                                              chat.profiles[index]!,
                                            ),
                                      child: MenuInlineAvatar(
                                        name: meta.self ? '我' : row.title,
                                        source: row.avatar,
                                      ),
                                    ),
                                    time:
                                        '${time.month}/${time.day} ${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (meta.role.isNotEmpty)
                                          Text(
                                            meta.role,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: meta.roleColor == null
                                                  ? context.tokens.colors.accent
                                                  : Color(meta.roleColor!),
                                            ),
                                          ),
                                        if (meta.role.isNotEmpty)
                                          const SizedBox(height: 4),
                                        SelectableText(row.detail),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ),
              if (_newMessages)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('menu-channel-new-messages'),
                    onPressed: () {
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                      setState(() => _newMessages = false);
                    },
                    child: const Text('有新消息 · 回到底部'),
                  ),
                ),
              composer,
            ],
          ),
        );
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final embedded = widget.embeddedRoom || widget.embeddedOrganization;
        if (constraints.maxHeight < (embedded ? 250 : 470) || scale > 1.5) {
          content = SingleChildScrollView(
            child: SizedBox(height: 760 * scale, child: content),
          );
        }
        return content;
      },
    );
  }
}
