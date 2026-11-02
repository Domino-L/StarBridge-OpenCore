/// Borrowed renderer network lifetime only, never a Native or account receipt.
final class ConnectionModeNetworkWork {
  const ConnectionModeNetworkWork({
    required this.pause,
    required this.reconcile,
  });
  final Future<void> Function() pause, reconcile;
}
