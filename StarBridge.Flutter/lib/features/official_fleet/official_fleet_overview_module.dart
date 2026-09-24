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
    _sourceRef = sourceRef;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    final sourceRef = _sourceRef;
    if (_disposed || sourceRef == null) {
      return;
    }
    final revision = ++_requestRevision;
    _projection.value = const OfficialFleetOverviewProjection.loading();
    try {
      final snapshot = await _port.read(sourceRef);
      if (_disposed || revision != _requestRevision) {
        return;
      }
      _projection.value = OfficialFleetOverviewProjection.fromSnapshot(
        snapshot,
      );
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
