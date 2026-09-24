import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_ships_port.dart';

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
  String? error;
  bool busy = false, invalidated = false;
  int _epoch = 0;
  bool _closed = false;

  void invalidate() {
    if (_closed) return;
    _epoch++;
    ship = null;
    busy = false;
    invalidated = true;
    error = 'identityUnavailable';
    notifyListeners();
  }

  Future<void> load({bool background = false}) async {
    if (_closed || invalidated || busy) return;
    final epoch = ++_epoch;
    if (!background) ship = null;
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
        return selected;
      }

      // The new client displays catalog artwork only. Keep legacy image/crop
      // metadata intact, but never fetch the member's custom image here.
      ship = await readSelected();
    } catch (e) {
      if (_closed || epoch != _epoch) return;
      ship = null;
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
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
