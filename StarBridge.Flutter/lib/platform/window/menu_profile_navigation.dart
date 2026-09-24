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

/// Main-engine read leases. IDs are renderer-local, never authority references.
abstract interface class MenuProfilesReadLease {
  void open(String window, MenuProfileTarget target);
  void refresh(String window);
  void closeWindow(String window);
  void hide();
  void dispose();
}
