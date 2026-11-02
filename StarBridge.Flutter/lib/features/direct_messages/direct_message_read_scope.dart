/// Cache invalidation key only. Never an account or permission receipt.
final class DirectMessageReadScope {
  const DirectMessageReadScope(
    this.transport,
    this.generation,
    this.modeRevision,
  );
  final Object transport;
  final int generation, modeRevision;
  @override
  bool operator ==(Object other) =>
      other is DirectMessageReadScope &&
      identical(transport, other.transport) &&
      generation == other.generation &&
      modeRevision == other.modeRevision;
  @override
  int get hashCode =>
      Object.hash(identityHashCode(transport), generation, modeRevision);
}

abstract interface class DirectMessageReadScopePort {
  DirectMessageReadScope? get readScope;

  /// Hard identity changes retire views; network drain/reconcile only retires
  /// offered reads and must preserve drafts while the same viewer is verified.
  void Function() observeReadScope(void Function(bool hard) changed);
}
