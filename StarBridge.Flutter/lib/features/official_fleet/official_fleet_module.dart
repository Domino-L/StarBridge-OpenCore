import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_fleet_models.dart';
import 'official_fleet_members_module.dart';
import 'official_fleet_members_port.dart';
import 'official_fleet_overview_module.dart';
import 'official_fleet_overview_port.dart';
import 'official_fleet_port.dart';
import 'official_fleet_ships_module.dart';
import 'official_fleet_ships_port.dart';

abstract interface class OfficialFleetModule {
  ValueListenable<OfficialFleetProjection> get projection;
  OfficialFleetOverviewModule get overview;
  OfficialFleetMembersModule get members;
  OfficialFleetShipsModule get ships;

  Future<void> initialize();
  Future<void> refresh();
  void dispose();
}

OfficialFleetModule createOfficialFleetModule(
  OfficialFleetPort port,
  OfficialFleetOverviewPort overviewPort,
  OfficialFleetMembersPort membersPort,
  OfficialFleetShipsPort shipsPort,
) => _DefaultOfficialFleetModule(port, overviewPort, membersPort, shipsPort);

final class _DefaultOfficialFleetModule implements OfficialFleetModule {
  _DefaultOfficialFleetModule(
    this._port,
    OfficialFleetOverviewPort overviewPort,
    OfficialFleetMembersPort membersPort,
    OfficialFleetShipsPort shipsPort,
  ) : overview = createOfficialFleetOverviewModule(overviewPort),
      members = createOfficialFleetMembersModule(membersPort),
      ships = createOfficialFleetShipsModule(shipsPort) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        unawaited(_refresh(discardContext: true));
      }
    });
  }

  final OfficialFleetPort _port;
  @override
  final OfficialFleetOverviewModule overview;
  @override
  final OfficialFleetMembersModule members;
  @override
  final OfficialFleetShipsModule ships;
  final ValueNotifier<OfficialFleetProjection> _projection = ValueNotifier(
    const OfficialFleetProjection.loading(),
  );
  late final StreamSubscription<void> _subscription;
  bool _initialized = false;
  Future<void>? _readTask;
  int _requestRevision = 0;
  bool _disposed = false;

  @override
  ValueListenable<OfficialFleetProjection> get projection => _projection;

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  @override
  Future<void> refresh() => _refresh(discardContext: false);

  Future<void> _refresh({required bool discardContext}) {
    if (_disposed) {
      return Future<void>.value();
    }
    ++_requestRevision;
    // Remove viewer-scoped data immediately, including requests still in flight.
    // Manual refresh retains filters; identity invalidation drops that context.
    overview.reset();
    members.reset(preserveQuery: !discardContext);
    ships.reset(preserveQuery: !discardContext);
    _projection.value = const OfficialFleetProjection.loading();
    return _readTask ??= _readLatest().whenComplete(() => _readTask = null);
  }

  Future<void> _readLatest() async {
    while (!_disposed) {
      final revision = _requestRevision;
      OfficialFleetSnapshot snapshot;
      try {
        snapshot = await _port.read();
      } on Object {
        snapshot = const OfficialFleetSnapshot.unavailable(
          failureKey: 'officialFleet.error.unavailable',
        );
      }
      if (_disposed) {
        return;
      }
      if (revision != _requestRevision) {
        continue;
      }
      if (snapshot.availability != OfficialFleetAvailability.available) {
        members.reset();
        ships.reset();
      }
      _projection.value = OfficialFleetProjection.fromSnapshot(snapshot);
      if (revision == _requestRevision &&
          !_disposed &&
          snapshot.fleet != null) {
        final sourceRef = snapshot.fleet!.sourceRef;
        unawaited(
          Future.wait([
            overview.open(sourceRef),
            members.open(sourceRef),
            ships.open(sourceRef),
          ]),
        );
      }
      // A listener can invalidate the identity while processing this projection.
      if (revision == _requestRevision) {
        return;
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_subscription.cancel());
    _projection.dispose();
    overview.dispose();
    members.dispose();
    ships.dispose();
    unawaited(_port.close());
  }
}
