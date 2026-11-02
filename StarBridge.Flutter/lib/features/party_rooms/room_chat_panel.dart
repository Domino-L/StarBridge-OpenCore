import 'dart:async';

import '../common/user_interaction.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionScope, ProgressPhase, SuiteProgressBar;

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'room_action_dialogs.dart';
import 'room_chat_module.dart';
import 'room_system_message.dart';
import 'room_preset_dialog.dart';
import 'room_feedback.dart';
import '../direct_messages/chat_message_bubble.dart';
import 'room_chat_composer.dart';
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
  late bool _wasLoading;
  InteractionSource? _readSource, _requestedReadSource;

  // Only classify this wait's presentation. The original read/older functions
  // still own guards, cursors, follow state, errors and asynchronous completion.
  void _readFrom(InteractionSource source, Future<void> Function() read) {
    _requestedReadSource = source;
    try {
      unawaited(read());
    } finally {
      _requestedReadSource = null;
    }
  }

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
    _wasLoading = widget.module.loading;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.module.loading && _readSource == null) {
      _readSource = resolveStarBridgeInitialReadSource(
        context,
        InteractionSource.programmatic,
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    final module = widget.module;
    if (module.loading != _wasLoading) {
      _readSource = module.loading
          ? _requestedReadSource ?? InteractionSource.programmatic
          : null;
      _wasLoading = module.loading;
    }
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

  Widget _readWait(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final label = roomActionText(context, 'working');
        return Semantics(
          key: const Key('room-chat-reading'),
          liveRegion: true,
          label: '${roomActionText(context, 'chat')} · $label',
          child: ExcludeSemantics(
            child:
                _readSource == InteractionSource.keyboard || data.reduceMotion
                ? Text(label)
                : const SuiteProgressBar(
                    value: null,
                    phase: ProgressPhase.running,
                  ),
          ),
        );
      },
    ),
  );

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
              StarBridgeActionButton(
                controlKey: const Key('room-chat-refresh'),
                kind: StarBridgeActionKind.quiet,
                onActivate: module.loading || module.sending
                    ? null
                    : (source) => _readFrom(source, module.refresh),
                child: Text(t('refreshMessages')),
              ),
            ],
          ),
          if (module.loading) _readWait(context),
          if (module.hasOlder)
            StarBridgeActionButton(
              controlKey: const Key('room-chat-older'),
              kind: StarBridgeActionKind.quiet,
              onActivate: module.loading
                  ? null
                  : (source) => _readFrom(source, _older),
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
                          return RoomSystemMessage(
                            key: ValueKey(message.id),
                            text: message.text,
                            time: message.time,
                          );
                        }
                        return ChatMessageBubble(
                          key: ValueKey(message.id),
                          incoming: !message.isSelf,
                          sender: message.sender,
                          avatar: message.avatar,
                          userTarget: message.userRef == null
                              ? null
                              : UserTarget(
                                  'room',
                                  message.userRef!,
                                  query: message.gameId,
                                ),
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
                                          child: StarBridgeActionButton(
                                            kind: StarBridgeActionKind.quiet,
                                            onActivate: (source) =>
                                                roomPresetDialog(
                                                  context,
                                                  module,
                                                  message: message,
                                                  source: source,
                                                ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const StarBridgeIcon(
                                                  StarBridgeIconSemantic.add,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(t('importPreset')),
                                              ],
                                            ),
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
            StarBridgeActionButton(
              controlKey: const Key('room-chat-latest'),
              kind: StarBridgeActionKind.quiet,
              onActivate: module.loading || module.sending
                  ? null
                  : (source) =>
                        _readFrom(source, () => module.refresh(latest: true)),
              child: Text('${t('latest')} · ${module.unread}'),
            ),
          if (module.error != null) RoomFeedback(module.error!),
          if (module.uncertain)
            StarBridgeActionButton(
              controlKey: const Key('room-chat-review-send'),
              kind: StarBridgeActionKind.quiet,
              onActivate: (_) => module.acknowledgeUncertain(),
              child: Text(t('reviewSend')),
            ),
          RoomChatComposer(
            controller: _text,
            inputKey: const Key('room-chat-draft'),
            enabled: module.available && !module.sending,
            sending: module.sending,
            onChanged: (value) => setState(() => module.draft = value),
            onSend:
                module.available &&
                    !module.loading &&
                    !module.sending &&
                    !module.uncertain &&
                    module.hasDraft
                ? module.send
                : null,
            attachment: module.attachmentDraft == null
                ? null
                : ListTile(
                    dense: true,
                    leading: const StarBridgeIcon(
                      StarBridgeIconSemantic.overlay,
                    ),
                    title: Text(
                      module.attachmentDraft!['title'] as String? ?? '',
                    ),
                    subtitle: Text(t('presetDraft')),
                    trailing: StarBridgeIconAction(
                      label: t('removeAttachment'),
                      onActivate: module.sending || module.uncertain
                          ? null
                          : (_) => module.clearAttachment(),
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.windowClose,
                      ),
                    ),
                  ),
            leadingAction: module.presetsAvailable
                ? StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    onActivate: module.sending || module.uncertain
                        ? null
                        : (source) =>
                              roomPresetDialog(context, module, source: source),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StarBridgeIcon(StarBridgeIconSemantic.overlay),
                        const SizedBox(width: 8),
                        Text(t('sharePreset')),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
