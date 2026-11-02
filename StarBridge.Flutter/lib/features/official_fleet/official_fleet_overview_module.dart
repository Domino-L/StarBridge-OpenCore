import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_fleet_overview_models.dart';
import 'official_fleet_overview_port.dart';

abstract interface class OfficialFleetOverviewModule {
  ValueListenable<OfficialFleetOverviewProjection> get projection;

  Future<void> open(String sourceRef);
  Future<void> refresh();
  void reset();
  void dispose();
}

OfficialFleetOverviewModule createOfficialFleetOverviewModule(
  OfficialFleetOverviewPort port,
) => _DefaultOfficialFleetOverviewModule(port);

final class _DefaultOfficialFleetOverviewModule
    implements OfficialFleetOverviewModule {
  _DefaultOfficialFleetOverviewModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed && _sourceRef != null) {
        unawaited(refresh());
      }
    });
  }

  final OfficialFleetOverviewPort _port;
  final ValueNotifier<OfficialFleetOverviewProjection> _projection =
      ValueNotifier(const OfficialFleetOverviewProjection.idle());
  late final StreamSubscription<void> _subscription;
  String? _sourceRef;
  int _requestRevision = 0;
  Future<void>? _readTask;
  bool _disposed = false;

  @override
  ValueListenable<OfficialFleetOverviewProjection> get projection =>
      _projection;

  @override
  Future<void> open(String sourceRef) async {
    if (_disposed || sourceRef.isEmpty) {
      return;
    }
    if (_sourceRef == sourceRef &&
        _projection.value.availability !=
            OfficialFleetOverviewAvailability.idle) {
      return;
    }
    reset();
    _sourceRef = sourceRef;
    await refresh();
  }

  @override
  Future<void> refresh() {
    final sourceRef = _sourceRef;
    if (_disposed || sourceRef == null) {
      return Future.value();
    }
    if (_readTask != null) return _readTask!;
    final revision = ++_requestRevision;
    final previous = _projection.value;
    _projection.value =
        previous.availability == OfficialFleetOverviewAvailability.available
        ? OfficialFleetOverviewProjection.refreshing(previous)
        : const OfficialFleetOverviewProjection.loading();
    return _readTask = _read(sourceRef, revision).whenComplete(() {
      if (revision == _requestRevision) _readTask = null;
    });
  }

  Future<void> _read(String sourceRef, int revision) async {
    try {
      final snapshot = await _port.read(sourceRef);
      if (_disposed || revision != _requestRevision) {
        return;
      }
      final previous = _projection.value;
      _projection.value =
          snapshot.availability ==
                  OfficialFleetOverviewAvailability.unavailable &&
              snapshot.transientFailure &&
              previous.availability ==
                  OfficialFleetOverviewAvailability.available
          ? OfficialFleetOverviewProjection.retained(
              previous,
              failureKey:
                  snapshot.failureKey ?? 'officialFleet.error.transient',
            )
          : OfficialFleetOverviewProjection.fromSnapshot(snapshot);
    } on Object {
      if (_disposed || revision != _requestRevision) {
        return;
      }
      _projection.value = OfficialFleetOverviewProjection.fromSnapshot(
        const OfficialFleetOverviewSnapshot.unavailable(
          failureKey: 'officialFleet.overview.error.unavailable',
        ),
      );
    }
  }

  @override
  void reset() {
    if (_disposed) {
      return;
    }
    ++_requestRevision;
    _readTask = null;
    _sourceRef = null;
    _projection.value = const OfficialFleetOverviewProjection.idle();
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
