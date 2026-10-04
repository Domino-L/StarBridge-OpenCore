import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'community_chat_port.dart';
import 'community_image_decoder.dart';
import 'community_avatar_cache.dart';
import 'community_own_avatar.dart';
import 'community_preset_port.dart';
import '../overlay_settings/overlay_preset_inspection_port.dart';
import '../overlay_settings/overlay_preset_transfer.dart';

class CommunityChatMedia {
  const CommunityChatMedia(this.avatar, this.attachment, {this.preview});
  final Uint8List? avatar;
  final Map<String, Object?>? attachment;
  final OverlayPresetTransfer? preview;
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
  final _ready = <(String, String?), CommunityChatMedia>{};
  CommunityChatMedia? peek(CommunityChatMessage message) =>
      _invalidated ? null : _ready[(message.messageRef, message.avatarVersion)];
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
      _ready.remove((message.messageRef, message.avatarVersion));
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
    return CommunityChatMedia(
      await avatarRead,
      detail.attachment,
      preview: detail.preview,
    );
  }

  Future<CommunityChatMedia> _detail(CommunityChatMessage message) {
    final reference = (message.messageRef, message.avatarVersion);
    if (!_details.containsKey(reference) && _details.length >= 32) {
      final oldest = _details.keys.first;
      _details.remove(oldest);
      _ready.remove(oldest);
    }
    return _details.putIfAbsent(reference, () {
      late final Future<CommunityChatMedia> pending;
      pending = _read(message.messageRef).then((value) {
        _current();
        if (identical(_details[reference], pending)) _ready[reference] = value;
        return value;
      });
      return pending;
    });
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
      OverlayPresetTransfer? preview;
      final Object source = port;
      if (detail.attachment != null &&
          source is CommunityPresetPort &&
          source.communityPresetsAvailable &&
          source is OverlayPresetInspectionPort) {
        try {
          final catalog = await source.readCommunityPresets();
          _current();
          preview = await (source as OverlayPresetInspectionPort).inspectPreset(
            detail.attachment!['overlayPresetPackage'] as String,
            catalog.revision,
          );
        } catch (_) {
          // A thumbnail failure must not remove the authorized attachment.
          // The explicit detail action can retry local inspection.
        }
        _current();
      }
      return CommunityChatMedia(
        detail.avatar == null
            ? null
            : base64Decode(detail.avatar!.split(',').last),
        detail.attachment,
        preview: preview,
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
    _ready.clear();
    if (clearShared) avatars.clear();
  }

  void dispose() {
    invalidate(clearShared: _ownsAvatars);
    if (_ownsAvatars) avatars.dispose();
    unawaited(_subscription.cancel());
  }
}
