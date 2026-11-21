import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ships_locate.dart';
import 'community_ships_port.dart';
import 'community_ship_image_port.dart';
import 'community_ship_report_port.dart';
import '../common/organization_ship_image_features.dart';

/// Reauthorizes the selected page before presenting a shared instance's details.
final class CommunityShipDetailController extends ChangeNotifier {
  CommunityShipDetailController(
    this.port,
    CommunityShipsPage page,
    String shipRef, {
    this.onRelocated,
  }) : _page = page,
       _shipRef = shipRef {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityShipsPort port;

  /// The page the ship was last read from; it moves when the ship had to be
  /// found again on another page or revision.
  CommunityShipsPage get page => _page;
  String get shipRef => _shipRef;
  CommunityShipsPage _page;
  final String _shipRef;

  /// The list the ship was picked from is out of date: the ship was found on
  /// another page or revision. The owner may read it again.
  final VoidCallback? onRelocated;
  late final StreamSubscription<void> _subscription;
  CommunitySharedShip? ship;
  CommunityShipImage? image;
  OrganizationShipImageFeatures? _imageFeatures;
  String? imageError;
  bool imageBusy = false;
  bool get canReadImage =>
      ship?.hasCustomImage == true &&
      _imageFeatures?.read == true &&
      port is CommunityShipImagePort &&
      (port as CommunityShipImagePort).shipImageAvailable;
  bool get canReportImage =>
      image != null &&
      !busy &&
      !invalidated &&
      ship?.ownerIsSelf == false &&
      image!.version == ship?.imageVersion &&
      _imageFeatures?.report == true &&
      port is CommunityShipReportPort &&
      (port as CommunityShipReportPort).shipReportAvailable;
  String? error;
  bool busy = false, invalidated = false;
  int _epoch = 0;
  bool _closed = false;

  void invalidate() {
    if (_closed) return;
    _epoch++;
    ship = null;
    image = null;
    _imageFeatures = null;
    imageError = null;
    imageBusy = false;
    busy = false;
    invalidated = true;
    error = 'identityUnavailable';
    notifyListeners();
  }

  /// [fromPage] shows the row already read for the list: the same data, and no
  /// request for a ship nobody picked. Picking it reads as usual.
  Future<void> load({bool background = false, bool fromPage = false}) async {
    if (_closed || invalidated || busy) return;
    final epoch = ++_epoch;
    if (!background) {
      ship = null;
      image = null;
    }
    error = null;
    busy = true;
    if (!background) notifyListeners();
    void current() {
      if (_closed || epoch != _epoch) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    try {
      Future<CommunitySharedShip> readSelected(
        CommunityShipsPage from,
        String reference,
      ) async {
        // The first page needs no pinned revision: a changed list answers with
        // its new one instead of refusing (user report 2026-11-15).
        final pinned = from.offset == 0 ? null : from.revision;
        final result = await port.readShips(
          from.targetRef,
          offset: from.offset,
          revision: pinned,
          query: from.query,
        );
        current();
        if (result.targetRef != from.targetRef ||
            result.offset != from.offset ||
            result.query != from.query ||
            pinned != null && result.revision != pinned) {
          throw const CommunityFailure('dataInvalid');
        }
        final selected = result.ships
            .where((s) => s.shipRef == reference)
            .firstOrNull;
        if (selected == null) throw const CommunityFailure('shipsChanged');
        _imageFeatures = result.imageFeatures;
        return selected;
      }

      // The list's revision may have moved (owners' presence still moves the
      // Relay's until r50), or the ship moved to another page: read the list
      // again once from the top and read the ship on the page that holds it.
      // Only a second failure says the library changed.
      Future<CommunitySharedShip> readOrRelocate() async {
        try {
          return await readSelected(_page, _shipRef);
        } on CommunityFailure catch (e) {
          if (e.code != 'shipsChanged') rethrow;
          final found = await relocateCommunityShip(
            port,
            _page,
            _shipRef,
            checkCurrent: current,
          );
          if (found == null) rethrow;
          final selected = await readSelected(found, _shipRef);
          _page = found;
          onRelocated?.call();
          return selected;
        }
      }

      // Legacy community metadata does not opt into custom-image display.
      // Only the official negotiated page plus an actual image port can do so.
      if (fromPage) {
        final held = _page.ships
            .where((s) => s.shipRef == _shipRef)
            .firstOrNull;
        if (held == null) throw const CommunityFailure('shipsChanged');
        _imageFeatures = _page.imageFeatures;
        ship = held;
      } else {
        ship = await readOrRelocate();
      }
      if (!canReadImage) {
        image = null;
        imageError = null;
      } else if (image?.version != ship!.imageVersion) {
        image = null;
        imageError = null;
        imageBusy = true;
        notifyListeners();
        try {
          final loaded = await assembleCommunityShipImage(
            port as CommunityShipImagePort,
            _page.targetRef,
            _shipRef,
            checkCurrent: current,
            expectedVersion: ship!.imageVersion,
          );
          current();
          image = loaded;
        } catch (e) {
          current();
          image = null;
          imageError = e is CommunityFailure ? e.code : 'dataInvalid';
          if (const {
            'identityUnavailable',
            'notAllowed',
            'refreshRequired',
          }.contains(imageError)) {
            rethrow;
          }
        } finally {
          if (!_closed && epoch == _epoch) imageBusy = false;
        }
      }
    } catch (e) {
      if (_closed || epoch != _epoch) return;
      ship = null;
      image = null;
      imageBusy = false;
      error = e is CommunityFailure ? e.code : 'unavailable';
      if (const {
        'identityUnavailable',
        'notAllowed',
        'refreshRequired',
      }.contains(error)) {
        invalidated = true;
      }
    }
    if (_closed || epoch != _epoch) return;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    ship = null;
    image = null;
    _imageFeatures = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
