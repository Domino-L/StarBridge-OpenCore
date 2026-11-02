import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ships_port.dart';
import 'community_ship_image_port.dart';
import 'community_ship_report_port.dart';
import '../common/organization_ship_image_features.dart';

/// Reauthorizes the selected page before presenting a shared instance's details.
final class CommunityShipDetailController extends ChangeNotifier {
  CommunityShipDetailController(this.port, this.page, this.shipRef) {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityShipsPort port;
  final CommunityShipsPage page;
  final String shipRef;
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
      Future<CommunitySharedShip> readSelected() async {
        final result = await port.readShips(
          page.targetRef,
          offset: page.offset,
          revision: page.revision,
          query: page.query,
        );
        current();
        if (result.targetRef != page.targetRef ||
            result.offset != page.offset ||
            result.query != page.query ||
            result.revision != page.revision) {
          throw const CommunityFailure('dataInvalid');
        }
        final selected = result.ships
            .where((s) => s.shipRef == shipRef)
            .firstOrNull;
        if (selected == null) throw const CommunityFailure('shipsChanged');
        _imageFeatures = result.imageFeatures;
        return selected;
      }

      // Legacy community metadata does not opt into custom-image display.
      // Only the official negotiated page plus an actual image port can do so.
      if (fromPage) {
        final held = page.ships.where((s) => s.shipRef == shipRef).firstOrNull;
        if (held == null) throw const CommunityFailure('shipsChanged');
        _imageFeatures = page.imageFeatures;
        ship = held;
      } else {
        ship = await readSelected();
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
            page.targetRef,
            shipRef,
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
