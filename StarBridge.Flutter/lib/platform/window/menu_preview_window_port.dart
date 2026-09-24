abstract interface class MenuPreviewWindowPort {
  Future<bool> open({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  });
}

abstract interface class MenuLiveWindowPort implements MenuPreviewWindowPort {
  bool get liveAvailable;
  Future<bool> openLive({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  });
  void dispose();
}

abstract interface class MenuFriendsReadLease {
  void show(bool visible);
  void dispose();
}

abstract interface class MenuCommsReadLease implements MenuFriendsReadLease {
  void act(String action, String key);
}

abstract interface class MenuCommsComposeLease {
  void compose(String action, String key, String text, int revision);
}

abstract interface class MenuFriendsActionLease {
  void act(String action, String key, String value);
}

/// Resolved only inside the authenticated primary engine, never serialized.
final class MenuChatTarget {
  const MenuChatTarget(
    this.reference,
    this.name, {
    this.avatar,
    this.stableKey,
  });
  final String reference, name;
  final String? avatar, stableKey;
}

abstract interface class MenuChatTargets {
  MenuChatTarget? chatTarget(String key);
}

abstract interface class MenuChatOpener {
  void openChat(MenuChatTarget? target);
}
