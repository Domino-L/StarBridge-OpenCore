import 'package:flutter/foundation.dart';

enum OfficialFleetShipsAvailability { idle, loading, available, unavailable }

enum OfficialFleetShipFilter { all, requestable, sharedByMe }

enum OfficialFleetShipSize { capital, large, medium, small, unknown }

enum OfficialFleetShipCatalogStatus { flightReady, concept, unknown }

enum OfficialFleetShipRequestState { requestable, unavailable, ownedByViewer }

@immutable
final class OfficialFleetSharedShip {
  const OfficialFleetSharedShip({
    required this.shipRef,
    required this.displayName,
    required this.modelCode,
    required this.ownerDisplay,
    required this.ownerCallsign,
    required this.size,
    required this.roleLabel,
    required this.catalogStatus,
    required this.requestState,
    required this.priceUsd,
    this.imageUrl,
    this.catalogImageAsset,
  });

  final String shipRef;
  final String displayName;
  final String modelCode;
  final String ownerDisplay;
  final String ownerCallsign;
  final OfficialFleetShipSize size;
  final String roleLabel;
  final OfficialFleetShipCatalogStatus catalogStatus;
  final OfficialFleetShipRequestState requestState;
  final int priceUsd;
  final String? imageUrl;
  // Legacy URL is retained for compatibility, not displayed by the new client.
  final String? catalogImageAsset;
}

@immutable
final class OfficialFleetShipsQuery {
  const OfficialFleetShipsQuery({
    required this.sourceRef,
    this.search = '',
    this.filter = OfficialFleetShipFilter.all,
    this.pageNumber = 1,
    this.pageSize = 25,
  }) : assert(pageNumber > 0),
       assert(pageSize == 25 || pageSize == 50 || pageSize == 100);

  final String sourceRef;
  final String search;
  final OfficialFleetShipFilter filter;
  final int pageNumber;
  final int pageSize;

  OfficialFleetShipsQuery copyWith({
    String? search,
    OfficialFleetShipFilter? filter,
    int? pageNumber,
    int? pageSize,
  }) => OfficialFleetShipsQuery(
    sourceRef: sourceRef,
    search: search ?? this.search,
    filter: filter ?? this.filter,
    pageNumber: pageNumber ?? this.pageNumber,
    pageSize: pageSize ?? this.pageSize,
  );
}

@immutable
final class OfficialFleetShipsSnapshot {
  const OfficialFleetShipsSnapshot.available({
    required this.query,
    required this.ships,
    required this.totalCount,
    required this.requestableCount,
    required this.ownerCount,
    required this.totalValueUsd,
    required this.totalPages,
    required this.sizeCounts,
  }) : availability = OfficialFleetShipsAvailability.available,
       failureKey = null;

  const OfficialFleetShipsSnapshot.unavailable({
    required this.query,
    required this.failureKey,
  }) : availability = OfficialFleetShipsAvailability.unavailable,
       ships = const [],
       totalCount = null,
       requestableCount = null,
       ownerCount = null,
       totalValueUsd = null,
       totalPages = null,
       sizeCounts = const {};

  final OfficialFleetShipsAvailability availability;
  final OfficialFleetShipsQuery query;
  final List<OfficialFleetSharedShip> ships;
  final int? totalCount;
  final int? requestableCount;
  final int? ownerCount;
  final int? totalValueUsd;
  final int? totalPages;
  final Map<OfficialFleetShipSize, int> sizeCounts;
  final String? failureKey;
}

@immutable
final class OfficialFleetShipsProjection {
  const OfficialFleetShipsProjection.idle()
    : availability = OfficialFleetShipsAvailability.idle,
      query = null,
      ships = const [],
      totalCount = null,
      requestableCount = null,
      ownerCount = null,
      totalValueUsd = null,
      totalPages = null,
      sizeCounts = const {},
      failureKey = null;

  const OfficialFleetShipsProjection.loading(this.query)
    : availability = OfficialFleetShipsAvailability.loading,
      ships = const [],
      totalCount = null,
      requestableCount = null,
      ownerCount = null,
      totalValueUsd = null,
      totalPages = null,
      sizeCounts = const {},
      failureKey = null;

  OfficialFleetShipsProjection.fromSnapshot(OfficialFleetShipsSnapshot snapshot)
    : availability = snapshot.availability,
      query = snapshot.query,
      ships = snapshot.ships,
      totalCount = snapshot.totalCount,
      requestableCount = snapshot.requestableCount,
      ownerCount = snapshot.ownerCount,
      totalValueUsd = snapshot.totalValueUsd,
      totalPages = snapshot.totalPages,
      sizeCounts = snapshot.sizeCounts,
      failureKey = snapshot.failureKey;

  final OfficialFleetShipsAvailability availability;
  final OfficialFleetShipsQuery? query;
  final List<OfficialFleetSharedShip> ships;
  final int? totalCount;
  final int? requestableCount;
  final int? ownerCount;
  final int? totalValueUsd;
  final int? totalPages;
  final Map<OfficialFleetShipSize, int> sizeCounts;
  final String? failureKey;
}
