import '../../shared/ships/ship_catalog_display.dart';
import '../../shared/ships/ship_reviewed_display.dart';

/// Data changed without invalidating the authenticated organization context.
abstract interface class CommunityShipsRefreshPort {
  Stream<void> get shipRefreshes;
}

abstract interface class CommunityShipsPort {
  Stream<void> get invalidations;
  bool get shipsAvailable;
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  });
}

final class CommunityShipQuery {
  CommunityShipQuery({
    String text = '',
    this.filter = 'all',
    this.sort = 'spec',
    this.descending = true,
    this.culture = 'zh-CN',
  }) : text = text.trim() {
    if (text.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) ||
        !const {
          'all',
          'capital',
          'large',
          'medium',
          'small',
          'flyable',
          'concept',
          'unknown',
        }.contains(filter) ||
        !const {
          'name',
          'spec',
          'status',
          'price',
          'role',
          'owner',
        }.contains(sort) ||
        !const {'zh-CN', 'zh-TW', 'en-US'}.contains(culture)) {
      throw const FormatException();
    }
  }
  factory CommunityShipQuery.parse(Map<String, Object?> row) =>
      CommunityShipQuery(
        text: _text(row, 'text', 128),
        filter: _text(row, 'filter', 16),
        sort: _text(row, 'sort', 16),
        descending: _flag(row, 'descending'),
        culture: _text(row, 'culture', 16),
      );
  final String text, filter, sort, culture;
  final bool descending;
  Map<String, Object?> toPayload() => {
    'text': text,
    'filter': filter,
    'sort': sort,
    'descending': descending,
    'culture': culture,
  };
  @override
  bool operator ==(Object other) =>
      other is CommunityShipQuery &&
      text == other.text &&
      filter == other.filter &&
      sort == other.sort &&
      descending == other.descending &&
      culture == other.culture;
  @override
  int get hashCode => Object.hash(text, filter, sort, descending, culture);
}

final class CommunitySharedShip {
  CommunitySharedShip.parse(Map<String, Object?> row)
    : shipRef = _reference(row, 'shipRef'),
      code = _text(row, 'code', 256),
      displayName = _text(row, 'displayName', 512),
      englishName = _optional(row, 'englishName', 256),
      manufacturer = _optional(row, 'manufacturer', 128),
      ownerMemberRef = _reference(row, 'ownerMemberRef'),
      ownerGameName = _text(row, 'ownerGameName', 256),
      ownerCallsign = _text(row, 'ownerCallsign', 256),
      ownerOnline = _flag(row, 'ownerOnline'),
      ownerLiveStatus = _text(row, 'ownerLiveStatus', 64),
      ownerIsSelf = _flag(row, 'ownerIsSelf'),
      ownerHasAvatar = _flag(row, 'ownerHasAvatar'),
      ownerAvatarVersion = _optional(row, 'ownerAvatarVersion', 64),
      sharedAt = _date(row, 'sharedAt'),
      hangarImportedAt = _date(row, 'hangarImportedAt'),
      roleCategory = _optional(row, 'roleCategory', 64),
      catalogSpec = _optional(row, 'catalogSpec', 256),
      catalogRole = _optional(row, 'catalogRole', 512),
      display = ShipReviewedDisplay.parse(row['display']),
      catalogIconKey = _optional(row, 'catalogIconKey', 64),
      catalogStatus = _optional(row, 'catalogStatus', 256),
      catalogPriceUsd = _optional(row, 'catalogPriceUsd', 128),
      catalogImageAsset = ShipCatalogDisplay.image(
        _optional(row, 'catalogImageAsset', 256),
      ),
      catalogThumbnailAsset = ShipCatalogDisplay.image(
        _optional(row, 'catalogThumbnailAsset', 256),
      ),
      loaners = _loaners(row),
      hasCustomImage = _flag(row, 'hasCustomImage'),
      customImageCropFocusX = _crop(row, 'customImageCropFocusX', 0, 1),
      customImageCropFocusY = _crop(row, 'customImageCropFocusY', 0, 1),
      customImageCropZoom = _crop(row, 'customImageCropZoom', .1, 20) {
    if (code.isEmpty) throw const FormatException();
    if (ownerAvatarVersion != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(ownerAvatarVersion!)) {
      throw const FormatException();
    }
  }
  final String shipRef,
      code,
      displayName,
      ownerMemberRef,
      ownerGameName,
      ownerCallsign,
      ownerLiveStatus;
  final bool ownerOnline, ownerIsSelf, ownerHasAvatar, hasCustomImage;
  final String? englishName, manufacturer;
  String? subtitleFor(String languageCode) {
    final value = languageCode == 'en' ? manufacturer : englishName;
    return value == null || value.trim().isEmpty ? null : value;
  }

  final String? ownerAvatarVersion;
  final DateTime? sharedAt, hangarImportedAt;
  final ShipReviewedDisplay? display;
  String? get displaySpec => display?.spec ?? catalogSpec;
  String? get displayRole =>
      display?.role ?? catalogRole?.split('/').first.trim().toLowerCase();
  String? get displayCategory => display?.role ?? roleCategory;
  String? get displayIcon =>
      display != null ? display!.iconKey : catalogIconKey;
  final String? roleCategory,
      catalogIconKey,
      catalogImageAsset,
      catalogThumbnailAsset,
      catalogSpec,
      catalogRole,
      catalogStatus,
      catalogPriceUsd;
  final double customImageCropFocusX,
      customImageCropFocusY,
      customImageCropZoom;

  /// Null means the local matrix was not available; an empty list is a known result.
  final List<CommunityShipLoaner>? loaners;
}

final class CommunityShipLoaner {
  CommunityShipLoaner.parse(Map<String, Object?> row)
    : code = _text(row, 'code', 256),
      displayName = _text(row, 'displayName', 512),
      catalogSpec = _optional(row, 'catalogSpec', 256),
      catalogStatus = _optional(row, 'catalogStatus', 256),
      catalogRole = _optional(row, 'catalogRole', 512),
      roleCategory = _optional(row, 'roleCategory', 64),
      display = ShipReviewedDisplay.parse(row['display']),
      catalogIconKey = _optional(row, 'catalogIconKey', 64),
      catalogPriceUsd = _optional(row, 'catalogPriceUsd', 128),
      catalogImageAsset = ShipCatalogDisplay.image(
        _optional(row, 'catalogImageAsset', 256),
      ),
      catalogThumbnailAsset = ShipCatalogDisplay.image(
        _optional(row, 'catalogThumbnailAsset', 256),
      ) {
    if (code.isEmpty) throw const FormatException();
  }
  final String code, displayName;
  final ShipReviewedDisplay? display;
  String? get displaySpec => display?.spec ?? catalogSpec;
  String? get displayRole => display?.role ?? roleCategory;
  final String? catalogSpec,
      catalogStatus,
      catalogRole,
      roleCategory,
      catalogIconKey,
      catalogPriceUsd,
      catalogImageAsset,
      catalogThumbnailAsset;

  /// Presentation candidate only; retains the source reference, never a new owned instance.
  CommunitySharedShip forDispatch(CommunitySharedShip source) =>
      CommunitySharedShip.parse({
        'shipRef': source.shipRef,
        'code': code,
        'displayName': displayName,
        'ownerMemberRef': source.ownerMemberRef,
        'ownerGameName': source.ownerGameName,
        'ownerCallsign': source.ownerCallsign,
        'ownerOnline': source.ownerOnline,
        'ownerLiveStatus': source.ownerLiveStatus,
        'ownerIsSelf': source.ownerIsSelf,
        'ownerHasAvatar': source.ownerHasAvatar,
        'ownerAvatarVersion': source.ownerAvatarVersion,
        'sharedAt': null,
        'hangarImportedAt': null,
        'catalogSpec': catalogSpec,
        'catalogStatus': catalogStatus,
        'catalogRole': catalogRole,
        'roleCategory': roleCategory,
        'catalogIconKey': catalogIconKey,
        'display': display?.toMap(),
        'catalogPriceUsd': catalogPriceUsd,
        'catalogImageAsset': catalogImageAsset,
        'catalogThumbnailAsset': catalogThumbnailAsset,
        'hasCustomImage': false,
        'customImageCropFocusX': .5,
        'customImageCropFocusY': .5,
        'customImageCropZoom': 1.0,
      });
}

List<CommunityShipLoaner>? _loaners(Map<String, Object?> row) {
  final value = row['loaners'];
  if (value == null) return null;
  if (value is! List || value.length > 16) throw const FormatException();
  final result = value.map((item) {
    if (item is! Map) throw const FormatException();
    return CommunityShipLoaner.parse(Map<String, Object?>.from(item));
  }).toList();
  if (result.map((item) => item.code.toLowerCase()).toSet().length !=
      result.length) {
    throw const FormatException();
  }
  return List.unmodifiable(result);
}

final class CommunityShipsPage {
  CommunityShipsPage.parse(Map<String, Object?> root)
    : targetRef = _reference(root, 'targetRef'),
      revision = _text(root, 'revision', 64),
      offset = _number(root, 'offset'),
      next = root['next'] == null ? null : _number(root, 'next'),
      totalCount = _number(root, 'totalCount'),
      matchedCount = root['matchedCount'] == null
          ? _number(root, 'totalCount')
          : _number(root, 'matchedCount'),
      query = root['query'] == null
          ? null
          : CommunityShipQuery.parse(
              Map<String, Object?>.from(root['query'] as Map),
            ),
      ships = List.unmodifiable(_rows(root).map(CommunitySharedShip.parse)) {
    if (root['schemaVersion'] != 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision) ||
        offset % 20 != 0 ||
        (query != null
            ? root['queryVersion'] != 2
            : root['queryVersion'] != null && root['queryVersion'] != 0) ||
        matchedCount > totalCount ||
        offset > matchedCount ||
        ships.length != (matchedCount - offset).clamp(0, 20) ||
        next !=
            (offset + ships.length < matchedCount
                ? offset + ships.length
                : null) ||
        ships.map((s) => s.shipRef).toSet().length != ships.length) {
      throw const FormatException();
    }
  }
  final String targetRef, revision;
  final int offset, totalCount, matchedCount;
  final CommunityShipQuery? query;
  final int? next;
  final List<CommunitySharedShip> ships;
}

String _text(Map<String, Object?> row, String key, int max) {
  final value = row[key];
  if (value is! String ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

String? _optional(Map<String, Object?> row, String key, int max) =>
    row[key] == null ? null : _text(row, key, max);
String _reference(Map<String, Object?> row, String key) {
  final value = _text(row, key, 32);
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) throw const FormatException();
  return value;
}

bool _flag(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! bool) throw const FormatException();
  return value;
}

int _number(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! int || value < 0 || value > 1000000) {
    throw const FormatException();
  }
  return value;
}

DateTime? _date(Map<String, Object?> row, String key) {
  final value = _optional(row, key, 64);
  if (value == null) return null;
  final date = DateTime.tryParse(value);
  if (date == null) throw const FormatException();
  return date;
}

double _crop(Map<String, Object?> row, String key, double min, double max) {
  final value = row[key];
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw const FormatException();
  }
  return value.toDouble();
}

List<Map<String, Object?>> _rows(Map<String, Object?> root) {
  final value = root['ships'];
  if (value is! List || value.length > 20) throw const FormatException();
  return value.map((item) {
    if (item is! Map) throw const FormatException();
    return Map<String, Object?>.from(item);
  }).toList();
}
