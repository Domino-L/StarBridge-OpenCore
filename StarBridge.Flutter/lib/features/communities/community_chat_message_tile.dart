import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../common/user_avatar_menu.dart';
import '../direct_messages/chat_message_bubble.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'community_chat_port.dart';
import 'community_chat_media_cache.dart';
import 'community_image_decoder.dart';
import 'community_chat_copy.dart';
import 'community_workspace_image.dart';
import 'community_preset_port.dart';
import 'community_preset_dialog.dart';

class CommunityChatMessageTile extends StatefulWidget {
  const CommunityChatMessageTile({
    required this.port,
    required this.targetRef,
    required this.message,
    this.mediaCache,
    super.key,
  });
  final CommunityChatPort port;
  final String targetRef;
  final CommunityChatMessage message;
  final CommunityChatMediaCache? mediaCache;
  @override
  State<CommunityChatMessageTile> createState() =>
      _CommunityChatMessageTileState();
}

class _CommunityChatMessageTileState extends State<CommunityChatMessageTile> {
  CommunityChatDetail? detail;
  Uint8List? avatar;
  bool failed = false, loading = false, invalidated = false;
  int epoch = 0;
  late StreamSubscription<void> changes;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    changes = widget.port.invalidations.listen((_) {
      epoch++;
      invalidated = true;
      if (mounted) {
        setState(() {
          detail = null;
          avatar = null;
          loading = false;
        });
      }
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CommunityChatMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.mediaCache != widget.mediaCache ||
        oldWidget.message.messageRef != widget.message.messageRef ||
        oldWidget.message.senderRef != widget.message.senderRef ||
        oldWidget.message.avatarVersion != widget.message.avatarVersion ||
        oldWidget.message.hasAvatar != widget.message.hasAvatar) {
      epoch++;
      unawaited(changes.cancel());
      detail = null;
      avatar = null;
      failed = loading = invalidated = false;
      _bind();
    }
  }

  Future<void> _load({bool retry = false}) async {
    if (loading ||
        invalidated ||
        !widget.message.hasAvatar &&
            !widget.message.hasAttachment &&
            !widget.message.isSelf) {
      return;
    }
    final current = ++epoch;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      if (widget.mediaCache case final cache?) {
        final result = await cache.load(widget.message, retry: retry);
        if (!mounted || current != epoch || invalidated) return;
        setState(() {
          detail = CommunityChatDetail(null, result.attachment);
          avatar = result.avatar;
        });
        return;
      }
      final result = await assembleCommunityChatDetail(
        widget.port,
        widget.targetRef,
        widget.message.messageRef,
        checkCurrent: () {
          if (!mounted || current != epoch || invalidated) {
            throw const FormatException();
          }
        },
      );
      if (!mounted || current != epoch) return;
      setState(() {
        detail = result;
        avatar = result.avatar == null
            ? null
            : base64Decode(result.avatar!.split(',').last);
      });
    } catch (_) {
      if (mounted && current == epoch) setState(() => failed = true);
    } finally {
      if (mounted && current == epoch) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    avatar = null;
    detail = null;
    unawaited(changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final card = detail?.attachment;
    final sender = message.gameId.isEmpty
        ? message.callsign
        : '${message.callsign} (${message.gameId})';
    String t(String key) => communityChatText(context, key);
    return ChatMessageBubble(
      incoming: !message.isSelf,
      sender: sender,
      time: communicationTime(message.createdAt, AppStrings.of(context).locale),
      avatarWidget: UserAvatarMenu(
        name: sender,
        avatarBytes: avatar,
        isSelf: message.isSelf,
        target: UserTarget.community(widget.targetRef, message.senderRef, query: message.gameId),
        child: SizedBox(
          width: 36,
          height: 36,
          child: CommunityWorkspaceImage(
            bytes: avatar,
            loading: loading && !invalidated,
            loadFailed: failed,
            icon: StandardIconSemantic.person,
            maxWidth: 96,
            decoder: widget.mediaCache?.images.decode ?? decodeCommunityImage,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: message.roleTitle,
            child: Text(
              message.roleTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(
                  int.parse(message.roleColor.substring(1), radix: 16) |
                      0xff000000,
                ),
                fontSize: 12,
              ),
            ),
          ),
          if (message.text.isNotEmpty) SelectableText(message.text),
          if (message.hasAttachment)
            SizedBox(
              height: 176,
              width: 360,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: card != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('preset'),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              card['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              card['summary'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.port is CommunityPresetPort &&
                                (widget.port as CommunityPresetPort)
                                    .communityPresetsAvailable)
                              TextButton(
                                onPressed: invalidated
                                    ? null
                                    : () => showDialog<void>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => CommunityPresetDialog(
                                          port:
                                              widget.port
                                                  as CommunityPresetPort,
                                          attachment: card,
                                        ),
                                      ),
                                child: Text(t('importPreset')),
                              ),
                          ],
                        )
                      : Center(
                          child: loading
                              ? const CircularProgressIndicator()
                              : Text(t('mediaFailed')),
                        ),
                ),
              ),
            ),
          if (failed)
            TextButton.icon(
              onPressed: invalidated ? null : () => _load(retry: true),
              icon: const StandardIcon(StandardIconSemantic.refresh, size: 14),
              label: Text(t('retry')),
            ),
        ],
      ),
    );
  }
}
