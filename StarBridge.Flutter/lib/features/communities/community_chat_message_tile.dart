import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../common/organization_holo.dart';
import '../common/social_read_activity.dart';
import '../common/user_avatar_menu.dart';
import '../common/organization_member_actions.dart';
import '../direct_messages/chat_message_bubble.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'community_chat_port.dart';
import 'community_author_projection_port.dart';
import 'community_chat_media_cache.dart';
import 'community_image_decoder.dart';
import 'community_chat_copy.dart';
import 'community_author_projection.dart';
import 'community_chat_seen_authors.dart';
import 'community_own_avatar.dart';
import 'community_workspace_image.dart';
import 'community_preset_port.dart';
import 'community_preset_dialog.dart';
import '../overlay_settings/overlay_shared_preset_card.dart';
import '../overlay_settings/overlay_preset_transfer.dart';

class CommunityChatMessageTile extends StatefulWidget {
  const CommunityChatMessageTile({
    required this.port,
    required this.targetRef,
    required this.message,
    this.mediaCache,
    this.authorIsCurrent,
    this.seenAuthors,
    super.key,
  });
  final CommunityChatPort port;
  final String targetRef;
  final CommunityChatMessage message;
  final CommunityChatMediaCache? mediaCache;
  final bool Function(CommunityChatMessage)? authorIsCurrent;
  final CommunityChatSeenAuthors? seenAuthors;
  @override
  State<CommunityChatMessageTile> createState() =>
      _CommunityChatMessageTileState();
}

class _CommunityChatMessageTileState extends State<CommunityChatMessageTile> {
  CommunityChatDetail? detail;
  Uint8List? avatar;
  OverlayPresetTransfer? preview;
  bool failed = false, loading = false, invalidated = false;
  int epoch = 0, _authorEpoch = 0;
  InteractionSource _activitySource = InteractionSource.programmatic;
  bool get _official => widget.port is CommunityAuthorProjectionPort;

  /// What to draw: the checked avatar, else the last one seen while the person
  /// is shown by name. Hidden or unavailable shows neither.
  Uint8List? get _shownAvatar {
    if (_ownIdentity != null) {
      final own = ownCommunityAvatarBytes(widget.port);
      if (own != null) return own;
    }
    final seen = widget.seenAuthors, sender = widget.message.senderRef;
    final identity = widget.message.authorIdentity;
    final version = identity?.visible == true ? identity?.avatarVersion : null;
    final current = avatar;
    if (seen == null) return current;
    if (current != null) {
      if (version != null) seen.rememberAvatar(sender, version, current);
      return current;
    }
    if (identity?.state == CommunityAuthorState.lastSeen) {
      return seen.avatarOf(sender);
    }
    return version == null ? null : seen.avatarOf(sender, version: version);
  }

  /// Your own messages use your own account, never an author proof.
  CommunityOwnIdentitySource? get _ownIdentity {
    final Object port = widget.port;
    return widget.message.isSelf && port is CommunityOwnIdentitySource
        ? port
        : null;
  }

  void _seenAvatarChanged() {
    if (mounted) setState(() {});
  }

  void _readSeenAvatar() {
    final seen = widget.seenAuthors;
    if (seen == null ||
        _ownIdentity != null ||
        widget.message.authorIdentity?.state != CommunityAuthorState.lastSeen) {
      return;
    }
    final wanted = seen.avatarWanted(widget.message.senderRef);
    if (wanted != null) {
      widget.mediaCache?.readSeenAvatar(widget.message, wanted);
    }
  }

  bool get _authorAvatarAllowed =>
      !_official ||
      widget.message.authorIdentity?.visible == true &&
          widget.message.hasAvatar &&
          widget.authorIsCurrent?.call(widget.message) == true;
  late StreamSubscription<void> changes;
  @override
  void initState() {
    super.initState();
    widget.seenAuthors?.addListener(_seenAvatarChanged);
    _bind();
    _readSeenAvatar();
  }

  void _bind() {
    _activitySource = InteractionSource.programmatic;
    final ready = widget.mediaCache?.peek(widget.message);
    var covered = false;
    if (ready != null) {
      detail = CommunityChatDetail(null, ready.attachment);
      avatar = _authorAvatarAllowed && ready.authorCurrent?.call() != false
          ? ready.avatar
          : null;
      preview = ready.preview;
      // Everything this message shows is already here: no read, no waiting
      // frame (user report 2026-10-29: avatars reloading in an idle chat).
      covered =
          (ready.attachment != null || !widget.message.hasAttachment) &&
          (avatar != null || !_authorAvatarAllowed);
    }
    changes = widget.port.invalidations.listen((_) {
      epoch++;
      invalidated = true;
      if (mounted) {
        setState(() {
          detail = null;
          preview = null;
          avatar = null;
          loading = false;
        });
      }
    });
    if (!covered) unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CommunityChatMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seenAuthors != widget.seenAuthors) {
      oldWidget.seenAuthors?.removeListener(_seenAvatarChanged);
      widget.seenAuthors?.addListener(_seenAvatarChanged);
    }
    _readSeenAvatar();
    if (oldWidget.port != widget.port ||
        oldWidget.targetRef != widget.targetRef ||
        oldWidget.mediaCache != widget.mediaCache ||
        oldWidget.message.messageRef != widget.message.messageRef ||
        oldWidget.message.senderRef != widget.message.senderRef ||
        !_official &&
            (oldWidget.message.avatarVersion != widget.message.avatarVersion ||
                oldWidget.message.hasAvatar != widget.message.hasAvatar)) {
      // The same person with the same portrait keeps it on screen while the
      // renewed reference re-reads it; anyone else starts blank.
      final kept =
          oldWidget.message.messageRef == widget.message.messageRef &&
              oldWidget.message.senderRef == widget.message.senderRef &&
              oldWidget.message.avatarVersion == widget.message.avatarVersion &&
              oldWidget.message.hasAvatar == widget.message.hasAvatar
          ? avatar
          : null;
      epoch++;
      unawaited(changes.cancel());
      detail = null;
      preview = null;
      avatar = null;
      failed = loading = invalidated = false;
      _bind();
      if (kept != null && _authorAvatarAllowed) avatar ??= kept;
    } else if (oldWidget.message.avatarVersion !=
            widget.message.avatarVersion ||
        oldWidget.message.hasAvatar != widget.message.hasAvatar ||
        oldWidget.message.authorIdentity?.version !=
            widget.message.authorIdentity?.version ||
        oldWidget.message.authorIdentity?.state !=
            widget.message.authorIdentity?.state ||
        oldWidget.message.authorIdentity?.observedAt !=
            widget.message.authorIdentity?.observedAt ||
        oldWidget.message.authorIdentity?.validUntil !=
            widget.message.authorIdentity?.validUntil) {
      _authorEpoch++;
      // A newer observation of a still visible author with the same portrait
      // keeps it until the re-admitted one replaces it; a retired author or a
      // changed portrait version goes blank at once.
      if (!_authorAvatarAllowed ||
          oldWidget.message.avatarVersion != widget.message.avatarVersion ||
          oldWidget.message.hasAvatar != widget.message.hasAvatar) {
        avatar = null;
      }
      failed = false;
      // The content request remains current. Only its person publication retires.
      if (_authorAvatarAllowed) unawaited(_load());
    }
  }

  Future<void> _load({bool retry = false, bool personOnly = false}) async {
    if (loading ||
        invalidated ||
        _official && !_authorAvatarAllowed && !widget.message.hasAttachment ||
        !widget.message.hasAvatar &&
            !widget.message.hasAttachment &&
            (!widget.message.isSelf || _official)) {
      return;
    }
    final current = ++epoch, author = _authorEpoch;
    setState(() {
      loading = true;
      failed = false;
      _activitySource = retry
          ? captureStarBridgeActivationSource()()
          : InteractionSource.programmatic;
    });
    try {
      if (widget.mediaCache case final cache?) {
        final message = _authorAvatarAllowed
            ? widget.message
            : CommunityChatMessage.neutralAuthor(widget.message);
        final result = await cache.load(
          message,
          retry: retry,
          avatarOnly: personOnly,
        );
        if (!mounted || current != epoch || invalidated) return;
        setState(() {
          if (!personOnly) {
            detail = CommunityChatDetail(null, result.attachment);
            preview = result.preview;
          }
          avatar =
              author == _authorEpoch &&
                  _authorAvatarAllowed &&
                  result.authorCurrent?.call() != false
              ? result.avatar
              : null;
        });
        return;
      }
      final result = await assembleCommunityChatDetail(
        widget.port,
        widget.targetRef,
        widget.message.messageRef,
        senderRef: widget.message.senderRef,
        identity: !_official
            ? null
            : CommunityChatDetailIdentity.neutral(
                (offset, version, _) => widget.port.readChatDetail(
                  widget.targetRef,
                  widget.message.messageRef,
                  offset,
                  version,
                ),
              ),
        checkCurrent: () {
          if (!mounted || current != epoch || invalidated) {
            throw const FormatException();
          }
        },
      );
      if (!mounted || current != epoch) return;
      setState(() {
        if (!personOnly) detail = result;
        avatar =
            author != _authorEpoch ||
                !_authorAvatarAllowed ||
                result.avatar == null
            ? null
            : base64Decode(result.avatar!.split(',').last);
      });
    } catch (_) {
      if (mounted && current == epoch) setState(() => failed = true);
    } finally {
      if (mounted && current == epoch) {
        setState(() => loading = false);
        // Finish the same content, then acquire the latest admitted person once.
        // The existing endpoint may still return combined content; do not replace
        // its already authorized attachment/preview with a person-only result.
        if (author != _authorEpoch && _authorAvatarAllowed) {
          unawaited(_load(personOnly: true));
        }
      }
    }
  }

  @override
  void dispose() {
    widget.seenAuthors?.removeListener(_seenAvatarChanged);
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
    String t(String key) => communityChatText(context, key);
    final ownName = _ownIdentity?.ownChatName?.trim();
    final sender = ownName != null && ownName.isNotEmpty
        ? ownName
        : widget.port is CommunityAuthorProjectionPort && message.callsign.isEmpty
        ? t(message.isSelf ? 'self' : 'member')
        : message.gameId.isEmpty
        ? message.callsign
        : '${message.callsign} (${message.gameId})';
    Widget waiting(
      String part,
      double size,
      String label, {
      double stroke = 4,
    }) => SizedBox.square(
      key: ValueKey('community-chat-$part-wait'),
      dimension: size,
      child: Center(
        child: SocialReadActivity(
          key: ValueKey((part, epoch, _activitySource)),
          source: _activitySource,
          opening: false,
          label: label,
          circularStandard: true,
          circularSize: size,
          circularStrokeWidth: stroke,
        ),
      ),
    );
    final holo = OrganizationHolo.of(context);
    final role = StarBridgeTooltip(
      message: message.roleTitle,
      child: Text(
        message.roleTitle,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          color: Color(
            int.parse(message.roleColor.substring(1), radix: 16) | 0xff000000,
          ),
          fontSize: 12,
        ),
      ),
    );
    return ChatMessageBubble(
      senderExtra: holo ? role : null,
      incoming: !message.isSelf,
      sender: sender,
      time: communicationTime(message.createdAt, AppStrings.of(context).locale),
      avatarWidget: UserAvatarMenu(
        name: sender,
        avatarBytes: _shownAvatar,
        isSelf: message.isSelf,
        target: !organizationMemberActionsAvailable(widget.port)
            ? null
            : UserTarget.community(
                widget.targetRef,
                message.senderRef,
                query: message.gameId,
              ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: CommunityWorkspaceImage(
            bytes: _shownAvatar,
            loading: loading && _shownAvatar == null && !invalidated,
            waiting: waiting(
              'avatar',
              16.2,
              t('avatarActivityRead'),
              stroke: 2,
            ),
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
          if (!holo) role,
          if (message.text.isNotEmpty) SelectableText(message.text),
          if (message.hasAttachment)
            if (card != null)
              OverlaySharedPresetCard(
                name: card['title'] as String,
                preview: preview,
                onInspectSource:
                    !invalidated &&
                        widget.port is CommunityPresetPort &&
                        (widget.port as CommunityPresetPort)
                            .communityPresetsAvailable
                    ? (source) => showCommunityPresetDialog(
                        context,
                        source: source,
                        port: widget.port as CommunityPresetPort,
                        attachment: card,
                      )
                    : null,
              )
            else
              SizedBox(
                height: 176,
                width: 360,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: loading
                          ? waiting('attachment', 36, t('mediaActivityRead'))
                          : Text(t('mediaFailed')),
                    ),
                  ),
                ),
              ),
          if (failed)
            StarBridgeActionButton(
              controlKey: ValueKey((
                'community-chat-media-retry',
                message.messageRef,
              )),
              kind: StarBridgeActionKind.quiet,
              onActivate: invalidated ? null : (_) => _load(retry: true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StandardIcon(StandardIconSemantic.refresh, size: 14),
                  const SizedBox(width: 8),
                  Text(t('retry')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
