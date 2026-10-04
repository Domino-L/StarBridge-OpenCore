import 'dart:async';

import '../../features/communities/community_chat_port.dart';
import 'menu_channel_avatars.dart';

/// Completed display media can survive an authorized reference renewal. Pending
/// work and permission bindings never migrate to the replacement reference.
final class MenuOrganizationChatPortraits {
  final messages = <String, List<CommunityChatMessage>>{};
  final photos = <String, Map<String, String>>{};
  final _loader = MenuChannelAvatars();

  void rebind(String old, String target) {
    final previous = messages.remove(old);
    final images = photos.remove(old);
    if (previous != null) messages[target] = List.of(previous);
    if (images != null) photos[target] = Map.of(images);
  }

  void remove(String target) {
    messages.remove(target);
    photos.remove(target);
  }

  void load(
    CommunityChatPort port,
    String target,
    List<CommunityChatMessage> next,
    bool Function() current,
    void Function() changed,
  ) {
    final previous = {
      for (final m in messages[target] ?? <CommunityChatMessage>[])
        m.messageRef: m,
    };
    final images = photos.putIfAbsent(target, () => {});
    final incoming = {for (final m in next) m.messageRef: m};
    images.removeWhere((reference, _) {
      final before = previous[reference], after = incoming[reference];
      return after == null ||
          !after.hasAvatar ||
          before?.senderRef != after.senderRef ||
          before?.avatarVersion != after.avatarVersion;
    });
    messages[target] = List.of(next);
    final missing = next
        .where((m) => !images.containsKey(m.messageRef))
        .toList();
    unawaited(
      _loader
          .load(
            port,
            target,
            missing,
            onPhoto: (index, photo) {
              final source = missing[index];
              final latest = messages[target]
                  ?.where((m) => m.messageRef == source.messageRef)
                  .firstOrNull;
              if (!current() ||
                  !identical(photos[target], images) ||
                  latest == null ||
                  (!latest.hasAvatar && !latest.isSelf) ||
                  latest.senderRef != source.senderRef ||
                  latest.avatarVersion != source.avatarVersion ||
                  latest.hasAvatar != source.hasAvatar ||
                  images[source.messageRef] == photo) {
                return;
              }
              images[source.messageRef] = photo;
              changed();
            },
          )
          .then((_) {}),
    );
  }

  void clear() {
    messages.clear();
    photos.clear();
    _loader.clear();
  }

  void dispose() {
    clear();
    _loader.dispose();
  }
}
