import 'dart:convert';

import '../../features/communities/community_chat_media_cache.dart';
import '../../features/communities/community_chat_port.dart';
import '../../features/communities/community_own_avatar.dart';
import 'menu_organization_avatars.dart';

/// Authorized sender media stays in the primary engine and outside the text
/// archive. Each conversation owns its media cache; account reset discards all.
final class MenuChannelAvatars {
  final _media = <String, CommunityChatMediaCache>{};
  final _images = MenuOrganizationAvatars();
  final _photos = <(String, String, String, String?), Future<String?>>{};
  int _epoch = 0;
  Future<List<String?>> load(
    CommunityChatPort port,
    String target,
    List<CommunityChatMessage> messages, {
    void Function(int, String)? onPhoto,
  }) async {
    final epoch = _epoch;
    if (!_media.containsKey(target) && _media.length >= 12) {
      _media.remove(_media.keys.first)?.dispose();
    }
    final cache = _media.putIfAbsent(
      target,
      () => CommunityChatMediaCache(port, target),
    );
    return Future.wait(
      messages.indexed.map((entry) async {
        final (index, message) = entry;
        final Object source = port;
        final own = message.isSelf && source is CommunityOwnAvatarSource
            ? source.ownAvatarImageData
            : null;
        final key = (
          target,
          message.senderRef,
          own != null ? 'current' : message.avatarVersion ?? message.messageRef,
          own,
        );
        if (!_photos.containsKey(key) && _photos.length >= 96) {
          _photos.remove(_photos.keys.first);
        }
        final pending = _photos.putIfAbsent(key, () async {
          try {
            final media = await cache
                .load(message, avatarOnly: true, retry: true)
                .timeout(const Duration(seconds: 10));
            if (epoch != _epoch || media.avatar == null) return null;
            final photo = await _images.logo(
              'data:image/png;base64,${base64Encode(media.avatar!)}',
            );
            if (epoch != _epoch) return null;
            return photo;
          } on Object {
            return null;
          }
        });
        final photo = await pending;
        if (epoch != _epoch) return null;
        if (photo == null && identical(_photos[key], pending)) {
          _photos.remove(key);
        }
        if (photo != null) onPhoto?.call(index, photo);
        return photo;
      }),
    );
  }

  void clear() {
    _epoch++;
    for (final media in _media.values) {
      media.dispose();
    }
    _media.clear();
    _photos.clear();
    _images.clear();
  }

  void dispose() {
    clear();
    _images.dispose();
  }
}
