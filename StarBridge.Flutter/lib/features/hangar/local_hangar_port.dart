import '../../shared/ships/ship_reviewed_display.dart';

/// Reads the Host's `yyyy-MM-dd` pledge date as a local calendar date.
DateTime? parseAcquiredOn(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!), month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (year <= 1 || month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

class LocalHangarShip {
  const LocalHangarShip({
    required this.id,
    required this.title,
    this.liner,
    this.manufacturer,
    this.cn,
    this.tw,
    this.size,
    this.addedAt,
    this.acquiredOn,
    this.removedAt,
    this.catalogId,
    this.category,
    this.sizeClass,
    this.deliveryStatus,
    this.priceUsd,
    this.imageAsset,
    this.thumbnailAsset,
    this.display,
    this.isFavorite = false,
    this.nickname,
    this.notes,
  });
  final String id, title;
  final String? nickname, notes;
  final String? liner, cn, tw, size;

  /// The catalog's maker, in the catalog's English spelling.
  final String? manufacturer;

  /// When this client first saved the ship. Not shown as "入库时间".
  final DateTime? addedAt;

  /// Official RSI hangar pledge date ("入库时间"), a calendar date in local
  /// time; null when RSI showed none (user 11-12: never the import time).
  final DateTime? acquiredOn;
  final DateTime? removedAt;
  String get modelKey => catalogId?.trim().isNotEmpty == true
      ? 'catalog:${catalogId!.trim().toLowerCase()}'
      : 'name:${title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';
  // Optional display facts from the same catalog, not persisted ownership.
  final String? catalogId, category, sizeClass, deliveryStatus, imageAsset;
  final String? thumbnailAsset;
  final num? priceUsd;
  final ShipReviewedDisplay? display;
  final bool isFavorite;
}

class LocalHangarSnapshot {
  const LocalHangarSnapshot({
    required this.revision,
    required this.ships,
    this.savedAt,
    this.inventorySavedAt,
    this.operationId,
    this.partial = false,
    this.fromLegacyProfile = false,
    this.formerShips = const [],
  });
  final int revision;
  final List<LocalHangarShip> ships;
  final List<LocalHangarShip> formerShips;
  final DateTime? savedAt;

  /// Last confirmed RSI inventory save; local metadata writes preserve it.
  final DateTime? inventorySavedAt;
  DateTime? get inventoryReadSavedAt => inventorySavedAt ?? savedAt;
  final String? operationId;
  final bool partial;
  final bool fromLegacyProfile;

  /// History uses the same local identity as current inventory. Another owned
  /// ship of this model never hides an archived instance or its metadata.
  /// Sort a copy, keeping the immutable Host snapshot intact.
  List<LocalHangarShip> get formerInstances => [...formerShips]
    ..sort(
      (a, b) => (b.removedAt ?? b.addedAt ?? DateTime(1970)).compareTo(
        a.removedAt ?? a.addedAt ?? DateTime(1970),
      ),
    );
}

class LocalHangarFailure implements Exception {
  const LocalHangarFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
}

/// Optional adapter classification; it does not change the exception contract.
abstract interface class LocalHangarReadFailures {
  bool isTransientReadFailure(Object error);
}

bool isRecoverableLocalHangarRead(Object error) =>
    error is LocalHangarFailure &&
    error.retryable &&
    const {
      'bridge.timeout',
      'bridge.disconnected',
      'hangar.read_unavailable',
      'hangar.storage_busy',
      'hangar.unavailable',
      'storage.unavailable',
    }.contains(error.code);

/// The current authenticated owner's local inventory. No identity or ship list
/// is accepted from the caller when saving; the Host retains the verified scan.
abstract interface class LocalHangarPort {
  Future<LocalHangarSnapshot> read();
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  });
}

/// Account-scoped bookmarks. Separate from the personal profile's favorites.
abstract interface class LocalHangarFavoritesPort {
  bool get favoritesAvailable;
  Future<LocalHangarSnapshot> setFavorite(
    String shipId,
    bool favorite,
    int expectedRevision,
  );
}

/// Local collection metadata only; no organization publication contract.
abstract interface class LocalHangarPersonalDataPort {
  bool get personalDataAvailable;

  /// Fresh Host inventory receipt, bypassing a refresh admitted before the edit.
  Future<LocalHangarSnapshot> readPersonalDataReceipt();
  Future<LocalHangarSnapshot> savePersonalData(
    String shipId,
    String? nickname,
    String? notes,
    int expectedRevision, {
    required String operationId,
  });
}
