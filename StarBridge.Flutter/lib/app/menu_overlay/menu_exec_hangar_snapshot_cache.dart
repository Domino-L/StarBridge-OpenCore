import '../../platform/window/menu_exec_hangar_summary.dart';

/// Retains an authorized summary across hides, never across an account epoch.
/// Elapsed time is monotonic; this cache does not fetch or persist business data.
final class MenuExecHangarSnapshotCache {
  MenuExecHangarSummary? _snapshot;
  final _age = Stopwatch();

  MenuExecHangarSummary? get current {
    final snapshot = _snapshot;
    return snapshot == null
        ? null
        : MenuExecHangarSummary(
            snapshot.now.add(_age.elapsed),
            snapshot.reliable,
            snapshot.fetchedAt,
            snapshot.phases,
            snapshot.windows,
          );
  }

  void accept(MenuExecHangarSummary snapshot) {
    _snapshot = snapshot;
    _age
      ..reset()
      ..start();
  }

  void clear() {
    _snapshot = null;
    _age.reset();
  }
}
