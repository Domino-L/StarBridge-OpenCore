class HangarInventoryShip {
  const HangarInventoryShip(
    this.id,
    this.original,
    this.cn,
    this.tw,
    this.size,
  );
  final String id, original;
  final String? cn, tw, size;
}

class HangarInventorySnapshot {
  const HangarInventorySnapshot(this.revision, this.savedAt, this.ships);
  final int revision;
  final DateTime? savedAt;
  final List<HangarInventoryShip> ships;
}

class HangarInventoryImport {
  const HangarInventoryImport(
    this.id,
    this.revision,
    this.digest,
    this.ships,
    this.added,
    this.removed,
    this.retained,
    this.ambiguous,
  );
  final String id, digest;
  final int revision, added, removed, retained;
  final List<HangarInventoryShip> ships;
  final bool ambiguous;
}

class HangarInventoryFailure implements Exception {
  const HangarInventoryFailure(this.code);
  final String code;
}

abstract interface class HangarInventoryPort {
  Future<bool> available();
  Future<HangarInventorySnapshot> read(String account);
  Future<HangarInventoryImport> preview(
    String account,
    String scenario,
    String key,
    int revision,
  );
  Future<HangarInventorySnapshot> commit(
    String account,
    HangarInventoryImport preview,
    String key,
    bool clear,
  );
  Future<HangarInventorySnapshot?> result(String account, String id);
}
