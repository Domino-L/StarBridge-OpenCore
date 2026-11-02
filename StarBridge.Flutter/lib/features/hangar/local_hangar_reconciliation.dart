import 'local_hangar_port.dart';

/// A choice among local instances, not a claimed RSI child identity.
class LocalHangarRemovalGroup {
  const LocalHangarRemovalGroup({
    required this.id,
    required this.requiredCount,
    required this.shipIds,
  });
  final String id;
  final int requiredCount;
  final List<String> shipIds;
}

/// Optional Host capability. The verified scan stays in Host; only the user's
/// selected local IDs cross the bridge. No client-supplied replacement ships.
abstract interface class LocalHangarReconciliationPort {
  bool get reconciliationAvailable;
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  );
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  });
}
