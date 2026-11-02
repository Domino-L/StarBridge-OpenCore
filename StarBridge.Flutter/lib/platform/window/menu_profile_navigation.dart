/// Main-engine-only target. Never serialize references or this lease to the
/// auxiliary renderer. The owning directory must still recognize the UI key.
final class MenuProfileTarget {
  const MenuProfileTarget({
    required this.source,
    required this.reference,
    required this.query,
    required this.isCurrent,
    required this.isAccountCurrent,
    this.avatar,
    this.contextRef,
    this.refreshReference,
  });
  final String source, reference, query;
  final String? avatar;
  final String? contextRef;
  // Chat author grants expire independently of cached text. Renew from the
  // authenticated message, never from the displayed nickname.
  final Future<String> Function()? refreshReference;
  final bool Function() isCurrent;
  // A profile window may outlive its source list, but not account invalidation.
  final bool Function() isAccountCurrent;
}

abstract interface class MenuProfileTargets {
  MenuProfileTarget? profileTarget(String key);
}

bool validMenuProfileWindow(Map arguments, int? opening) =>
    arguments['opening'] == opening &&
    arguments['window'] is String &&
    RegExp(r'^p[1-9][0-9]{0,8}$').hasMatch(arguments['window'] as String);

/// Resolve only through the original source lease, retaining its current-grant
/// check. Renderer-local keys never become profile authority references.
MenuProfileTarget? resolveMenuProfileTarget(
  Map arguments,
  Object? friends,
  Object? communications,
  Map<String, Object?> features,
) {
  final key = arguments['key'];
  if (key is! String) return null;
  final owner = switch (arguments['source']) {
    'friends' => friends,
    'comms' => communications,
    'organizations' => features['organizations'],
    'organizationChat' => features['organizationChat'],
    _ => null,
  };
  final target = owner is MenuProfileTargets ? owner.profileTarget(key) : null;
  return key.length <= 64 && target != null && target.isCurrent()
      ? target
      : null;
}

/// Main-engine read leases. IDs are renderer-local, never authority references.
abstract interface class MenuProfilesReadLease {
  void open(String window, MenuProfileTarget target);
  void refresh(String window);
  void closeWindow(String window);
  void hide();
  void dispose();
}
