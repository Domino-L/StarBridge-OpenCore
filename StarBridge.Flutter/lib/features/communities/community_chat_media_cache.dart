import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'community_chat_port.dart';
import 'community_image_decoder.dart';
import 'community_avatar_cache.dart';
import 'community_own_avatar.dart';

class CommunityChatMedia {
  const CommunityChatMedia(this.avatar, this.attachment);
  final Uint8List? avatar;
  final Map<String, Object?>? attachment;
}

/// One authorized conversation owns its media; never keyed by display names.
/// Shared futures coalesce requests and retain avatar bytes between list mounts.
class CommunityChatMediaCache {
  CommunityChatMediaCache(
    this.port,
    this.targetRef, {
    CommunityAvatarCache? avatars,
  }) : avatars = avatars ?? CommunityAvatarCache(),
       _ownsAvatars = avatars == null {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityChatPort port;
  final String targetRef;
  final CommunityAvatarCache avatars;
  final bool _ownsAvatars;
  CommunityImageDecodeCache get images => avatars.images;
  late final StreamSubscription<void> _subscription;
  final _details = <(String, String?), Future<CommunityChatMedia>>{};
  final _queue = <Completer<void>>[];
  int _active = 0;
  bool _invalidated = false;

  void _current() {
    if (_invalidated) throw StateError('Invalidated conversation media');
  }

  Future<CommunityChatMedia> load(
    CommunityChatMessage message, {
    bool retry = false,
    bool avatarOnly = false,
  }) async {
    _current();
    if (retry) {
      _details.remove((message.messageRef, message.avatarVersion));
    }
    Future<Uint8List?> avatar() {
      final Object source = port;
      final current = source is CommunityOwnAvatarSource
          ? source.ownAvatarImageData
          : null;
      if (message.isSelf && current != null && current.length <= 700000) {
        final version = sha256.convert(utf8.encode(current)).toString();
        // Display our current account photo on old messages too. Keep it out of
        // the historical sender/version cache; never substitute another sender.
        return avatars.get(
          '${message.senderRef}:current-account',
          version,
          () async =>
              readOwnCommunityAvatar(source, isSelf: true, version: version),
          retry: retry,
        );
      }
      if (!message.hasAvatar) return Future<Uint8List?>.value(null);
      return avatars.get(
        message.senderRef,
        message.avatarVersion,
        () async =>
            readOwnCommunityAvatar(
              port,
              isSelf: message.isSelf,
              version: message.avatarVersion,
            ) ??
            (await _detail(message)).avatar,
        retry: retry,
      );
    }

    if (avatarOnly || !message.hasAttachment) {
      final bytes = message.hasAvatar || message.isSelf ? await avatar() : null;
      _current();
      return CommunityChatMedia(bytes, null);
    }
    final pending = _detail(message);
    final avatarRead = message.hasAvatar || message.isSelf
        ? avatar()
        : Future<Uint8List?>.value(null);
    avatarRead.ignore();
    final detail = await pending;
    _current();
    return CommunityChatMedia(await avatarRead, detail.attachment);
  }

  Future<CommunityChatMedia> _detail(CommunityChatMessage message) {
    final reference = (message.messageRef, message.avatarVersion);
    if (!_details.containsKey(reference) && _details.length >= 32) {
      _details.remove(_details.keys.first);
    }
    return _details.putIfAbsent(reference, () => _read(message.messageRef));
  }

  Future<CommunityChatMedia> _read(String reference) async {
    _current();
    if (_active >= 3) {
      final ready = Completer<void>();
      _queue.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      _current();
      final detail = await assembleCommunityChatDetail(
        port,
        targetRef,
        reference,
        checkCurrent: _current,
      );
      _current();
      return CommunityChatMedia(
        detail.avatar == null
            ? null
            : base64Decode(detail.avatar!.split(',').last),
        detail.attachment,
      );
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  void invalidate({bool clearShared = true}) {
    _invalidated = true;
    _details.clear();
    if (clearShared) avatars.clear();
  }

  void dispose() {
    invalidate(clearShared: _ownsAvatars);
    if (_ownsAvatars) avatars.dispose();
    unawaited(_subscription.cancel());
  }
}
