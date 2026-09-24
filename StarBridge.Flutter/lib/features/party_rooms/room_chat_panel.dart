import 'dart:async';
import '../common/user_interaction.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../app/localization/app_strings.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'room_action_dialogs.dart';
import 'room_chat_module.dart';
import 'room_preset_dialog.dart';
import 'room_feedback.dart';
import '../direct_messages/chat_message_bubble.dart';
import '../direct_messages/chat_send_shortcuts.dart';
import '../direct_messages/communication_time_formatter.dart';
import '../communities/community_invitation_card.dart';

class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.module,
    this.openCommunityInvite,
  });
  final RoomChatModule module;
  final Future<void> Function(BuildContext, String)? openCommunityInvite;
  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final _text = TextEditingController(), _scroll = ScrollController();
  String? _lastMessageId;
  Timer? _timeRefresh;
  bool _openingInvite = false;
  Future<void> _openInvitation(String code) async {
    final open = widget.openCommunityInvite;
    if (_openingInvite || open == null || !widget.module.available) return;
    setState(() => _openingInvite = true);
    try {
      await open(context, code);
    } finally {
      if (mounted) setState(() => _openingInvite = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _timeRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _text.text = widget.module.draft;
    widget.module.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.module.followLatest && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    final module = widget.module;
    if (_text.text != module.draft) _text.text = module.draft;
    if (module.messages.lastOrNull?.id != _lastMessageId &&
        module.followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    _lastMessageId = module.messages.lastOrNull?.id;
    setState(() {});
  }

  @override
  void dispose() {
    _timeRefresh?.cancel();
    widget.module.removeListener(_changed);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _older() async {
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    widget.module.setFollowing(false);
    await widget.module.refresh(older: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(
          (oldOffset + _scroll.position.maxScrollExtent - oldMax).clamp(
            0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    String t(String key) => roomActionText(context, key);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('chat'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: module.loading || module.sending
                    ? null
                    : module.refresh,
                child: Text(t('refreshMessages')),
              ),
            ],
          ),
          if (module.loading) const LinearProgressIndicator(),
          if (module.hasOlder)
            TextButton(
              onPressed: module.loading ? null : _older,
              child: Text(t('older')),
            ),
          Expanded(
            child: module.messages.isEmpty
                ? Center(child: Text(t('chatEmpty')))
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if ((notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle) ||
                          (notification is ScrollUpdateNotification &&
                              notification.dragDetails != null)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _scroll.hasClients) {
                            module.setFollowing(
                              _scroll.position.extentAfter < 36,
                            );
                          }
                        });
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      key: const Key('room-chat-messages'),
                      itemCount: module.messages.length,
                      itemBuilder: (context, index) {
                        final message = module.messages[index];
                        final time = communicationTime(
                          message.time,
                          AppStrings.of(context).locale,
                        );
                        if (message.kind != 'player') {
                          return Padding(
                            key: ValueKey(message.id),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '${message.text} · $time',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        }
                        return ChatMessageBubble(
                          key: ValueKey(message.id),
                          incoming: !message.isSelf,
                          sender: message.sender,
                          avatar: message.avatar,
                          userTarget: message.userRef == null ? null : UserTarget('room', message.userRef!, query: message.gameId),
                          time: time,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.text.isNotEmpty)
                                SelectableText(message.text),
                              if (message.communityInvitation
                                  case final invitation?)
                                CommunityInvitationCard(
                                  value: invitation,
                                  busy: _openingInvite,
                                  onOpen: widget.openCommunityInvite == null
                                      ? null
                                      : () => unawaited(
                                          _openInvitation(
                                            invitation.inviteCode,
                                          ),
                                        ),
                                )
                              else if (message.attachment
                                  case final attachment?)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        attachment['title'] as String? ?? '',
                                      ),
                                      Text(
                                        attachment['summary'] as String? ?? '',
                                      ),
                                      if (attachment['kind'] ==
                                              'overlay_preset' &&
                                          module.presetsAvailable)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => roomPresetDialog(
                                              context,
                                              module,
                                              message: message,
                                            ),
                                            icon: const StarBridgeIcon(
                                              StarBridgeIconSemantic.add,
                                            ),
                                            label: Text(t('importPreset')),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (!module.followLatest || module.unread > 0)
            TextButton(
              onPressed: module.loading || module.sending
                  ? null
                  : () => module.refresh(latest: true),
              child: Text('${t('latest')} · ${module.unread}'),
            ),
          if (module.error != null) RoomFeedback(module.error!),
          if (module.uncertain)
            TextButton(
              onPressed: module.acknowledgeUncertain,
              child: Text(t('reviewSend')),
            ),
          const SizedBox(height: 8),
          if (module.attachmentDraft case final attachment?)
            ListTile(
              dense: true,
              leading: const StarBridgeIcon(StarBridgeIconSemantic.overlay),
              title: Text(attachment['title'] as String? ?? ''),
              subtitle: Text(t('presetDraft')),
              trailing: IconButton(
                tooltip: t('removeAttachment'),
                onPressed: module.sending || module.uncertain
                    ? null
                    : module.clearAttachment,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
              ),
            ),
          ChatSendShortcuts(
            controller: _text,
            onSend: () {
              if (module.available &&
                  !module.loading &&
                  !module.sending &&
                  !module.uncertain &&
                  module.hasDraft) {
                module.send();
              }
            },
            child: TextField(
              key: const Key('room-chat-draft'),
              controller: _text,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              enabled: module.available && !module.sending,
              onChanged: (value) => setState(() => module.draft = value),
              decoration: InputDecoration(
                labelText: t('chatDraft'),
                helperText: AppStrings.of(context).text('direct.send.shortcut'),
              ),
            ),
          ),
          Row(
            children: [
              if (module.presetsAvailable)
                TextButton.icon(
                  onPressed: module.sending || module.uncertain
                      ? null
                      : () => roomPresetDialog(context, module),
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.overlay),
                  label: Text(t('sharePreset')),
                ),
              const Spacer(),
              FilledButton(
                onPressed:
                    !module.available ||
                        module.loading ||
                        module.sending ||
                        module.uncertain ||
                        !module.hasDraft
                    ? null
                    : module.send,
                child: Text(t(module.sending ? 'working' : 'send')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
