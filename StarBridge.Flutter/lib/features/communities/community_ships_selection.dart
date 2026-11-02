import 'dart:async';

import 'package:flutter/foundation.dart';

import 'community_ships_controller.dart';
import 'community_ships_locate.dart';
import 'community_ships_port.dart';

/// Which ship the wide layout's right column shows, and the page it came from.
final class CommunityShipsSelection {
  CommunityShipsSelection({
    required this.model,
    required this.port,
    required this.targetRef,
    required this.pageHolding,
    required this.update,
    required this.alive,
  });

  final CommunityShipsController Function() model;
  final CommunityShipsPort Function() port;
  final String Function() targetRef;
  final CommunityShipsPage? Function(String shipRef) pageHolding;
  final void Function(VoidCallback change) update;
  final bool Function() alive;

  CommunityShipsPage? page;
  bool lookingUp = false;
  int _lookup = 0;

  void clear() {
    model()
      ..selectedShipRef = null
      ..selectionIsDefault = false;
    page = null;
  }

  /// Stops any search and forgets the page, for another organization.
  void reset() {
    _lookup++;
    lookingUp = false;
    page = null;
  }

  /// A new list page may replace the one shown, or say the ship has gone.
  void afterPage(CommunityShipsPage read) {
    final after = communityShipSelectionAfter(
      read,
      page,
      model().selectedShipRef,
    );
    if (after?.gone == true) {
      clear();
    } else if (after != null) {
      page = after.page;
    }
  }

  /// [byUser] reads it again; a default selection shows the row already held.
  Future<void> pick(
    CommunitySharedShip ship,
    String culture, {
    required bool byUser,
    VoidCallback? onPicked,
  }) async {
    final current = model();
    if (current.selectedShipRef == ship.shipRef &&
        page != null &&
        current.selectionIsDefault != byUser) {
      return;
    }
    final lookup = ++_lookup;
    final held = pageHolding(ship.shipRef);
    update(() {
      current
        ..selectedShipRef = ship.shipRef
        ..selectionIsDefault = !byUser;
      page = held;
      lookingUp = held == null;
    });
    onPicked?.call();
    if (held != null) return;
    final found = await locateCommunityShipPage(
      port(),
      targetRef(),
      ship,
      culture,
      isCurrent: () => alive() && lookup == _lookup,
    );
    if (!alive() || lookup != _lookup) return;
    update(() {
      page = found;
      lookingUp = false;
      if (found == null) current.selectedShipRef = null;
    });
  }
}
