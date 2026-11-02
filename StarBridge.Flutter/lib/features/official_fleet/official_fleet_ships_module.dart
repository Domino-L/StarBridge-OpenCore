import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_fleet_ships_models.dart';
import 'official_fleet_ships_port.dart';

abstract interface class OfficialFleetShipsModule {
  ValueListenable<OfficialFleetShipsProjection> get projection;

  Future<void> open(String sourceRef);
  Future<void> search(String value);
  Future<void> setFilter(OfficialFleetShipFilter value);
  Future<void> setPageSize(int value);
  Future<void> goToPage(int value);
  Future<void> refresh();
  void reset({bool preserveQuery = false});
  void dispose();
}

OfficialFleetShipsModule createOfficialFleetShipsModule(
  OfficialFleetShipsPort port, {
  DateTime Function()? now,
}) => _DefaultOfficialFleetShipsModule(port, now ?? DateTime.now);

final class _DefaultOfficialFleetShipsModule
    implements OfficialFleetShipsModule {
  _DefaultOfficialFleetShipsModule(this._port, this._now) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed && _query != null) {
        unawaited(refresh());
      }
    });
  }

  final OfficialFleetShipsPort _port;
  final DateTime Function() _now;
  final ValueNotifier<OfficialFleetShipsProjection> _projection = ValueNotifier(
    const OfficialFleetShipsProjection.idle(),
  );
  late final StreamSubscription<void> _subscription;
  OfficialFleetShipsQuery? _query;
  int _requestRevision = 0;
  Future<void>? _readTask;
  bool _suspended = true;
  bool _disposed = false;

  @override
  ValueListenable<OfficialFleetShipsProjection> get projection => _projection;

  @override
  Future<void> open(String sourceRef) async {
    if (_disposed || sourceRef.isEmpty) {
      return;
    }
    _suspended = false;
    if (_query?.sourceRef == sourceRef) {
      if (_projection.value.availability ==
          OfficialFleetShipsAvailability.idle) {
        await refresh();
      }
      return;
    }
    reset();
    _suspended = false;
    _query = OfficialFleetShipsQuery(sourceRef: sourceRef);
    await refresh();
  }

  @override
  Future<void> search(String value) => _replaceQuery(
    (query) => query.copyWith(search: value.trim(), pageNumber: 1),
  );

  @override
  Future<void> setFilter(OfficialFleetShipFilter value) =>
      _replaceQuery((query) => query.copyWith(filter: value, pageNumber: 1));

  @override
  Future<void> setPageSize(int value) =>
      _replaceQuery((query) => query.copyWith(pageSize: value, pageNumber: 1));

  @override
  Future<void> goToPage(int value) {
    final totalPages = _projection.value.totalPages;
    final page = totalPages == null ? value : value.clamp(1, totalPages);
    return _replaceQuery((query) => query.copyWith(pageNumber: page));
  }

  Future<void> _replaceQuery(
    OfficialFleetShipsQuery Function(OfficialFleetShipsQuery query) update,
  ) async {
    final query = _query;
    if (_disposed || _suspended || query == null) {
      return;
    }
    final next = update(query);
    if (_sameQuery(query, next)) return refresh();
    _query = next;
    _readTask = null;
    await refresh();
  }

  @override
  Future<void> refresh() {
    final query = _query;
    if (_disposed || _suspended || query == null) {
      return Future.value();
    }
    if (_readTask != null) return _readTask!;
    final revision = ++_requestRevision;
    final previous = _projection.value;
    _projection.value =
        previous.availability == OfficialFleetShipsAvailability.available &&
            previous.query != null &&
            _sameQuery(previous.query!, query)
        ? OfficialFleetShipsProjection.refreshing(previous)
        : OfficialFleetShipsProjection.loading(query);
    return _readTask = _read(query, revision).whenComplete(() {
      if (revision == _requestRevision) _readTask = null;
    });
  }

  Future<void> _read(OfficialFleetShipsQuery query, int revision) async {
    try {
      final snapshot = await _port.read(query);
      if (_disposed || revision != _requestRevision) {
        return;
      }
      if (!_sameQuery(snapshot.query, query) ||
          snapshot.ships.any((ship) => ship.shipRef.trim().isEmpty) ||
          snapshot.ships.map((ship) => ship.shipRef).toSet().length !=
              snapshot.ships.length) {
        throw StateError('Invalid fleet ship projection');
      }
      final previous = _projection.value;
      _projection.value =
          snapshot.availability == OfficialFleetShipsAvailability.unavailable &&
              snapshot.transientFailure &&
              previous.availability ==
                  OfficialFleetShipsAvailability.available &&
              previous.query != null &&
              _sameQuery(previous.query!, query)
          ? OfficialFleetShipsProjection.retained(
              previous,
              failureKey:
                  snapshot.failureKey ?? 'officialFleet.error.transient',
            )
          : OfficialFleetShipsProjection.fromSnapshot(
              snapshot,
              lastReadAtUtc:
                  snapshot.availability ==
                      OfficialFleetShipsAvailability.available
                  ? _now().toUtc()
                  : null,
            );
    } on Object {
      if (_disposed || revision != _requestRevision) {
        return;
      }
      _projection.value = OfficialFleetShipsProjection.fromSnapshot(
        OfficialFleetShipsSnapshot.unavailable(
          query: query,
          failureKey: 'officialFleet.ships.error.unavailable',
        ),
      );
    }
  }

  @override
  void reset({bool preserveQuery = false}) {
    if (_disposed) {
      return;
    }
    ++_requestRevision;
    _readTask = null;
    _suspended = true;
    if (!preserveQuery) {
      _query = null;
    }
    _projection.value = const OfficialFleetShipsProjection.idle();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _requestRevision++;
    unawaited(_subscription.cancel());
    _projection.dispose();
    unawaited(_port.close());
  }
}

bool _sameQuery(OfficialFleetShipsQuery a, OfficialFleetShipsQuery b) =>
    a.sourceRef == b.sourceRef &&
    a.search == b.search &&
    a.filter == b.filter &&
    a.pageNumber == b.pageNumber &&
    a.pageSize == b.pageSize;
