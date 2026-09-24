import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_fleet_members_models.dart';
import 'official_fleet_members_port.dart';

abstract interface class OfficialFleetMembersModule {
  ValueListenable<OfficialFleetMemberDirectoryProjection> get projection;
  ValueListenable<String?> get selectedMemberRef;
  double get scrollOffset;
  void selectMember(String? memberRef);
  void rememberScrollOffset(double value);

  Future<void> open(String sourceRef);
  Future<void> search(String value);
  Future<void> setFilter(OfficialFleetMemberFilter value);
  Future<void> setPageSize(int value);
  Future<void> goToPage(int value);
  Future<void> refresh();
  void reset({bool preserveQuery = false});
  void dispose();
}

OfficialFleetMembersModule createOfficialFleetMembersModule(
  OfficialFleetMembersPort port,
) => _DefaultOfficialFleetMembersModule(port);

final class _DefaultOfficialFleetMembersModule
    implements OfficialFleetMembersModule {
  _DefaultOfficialFleetMembersModule(this._port) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed && _query != null) {
        unawaited(refresh());
      }
    });
  }

  final OfficialFleetMembersPort _port;
  final ValueNotifier<OfficialFleetMemberDirectoryProjection> _projection =
      ValueNotifier(const OfficialFleetMemberDirectoryProjection.idle());
  late final StreamSubscription<void> _subscription;
  OfficialFleetMemberDirectoryQuery? _query;
  final ValueNotifier<String?> _selectedMemberRef = ValueNotifier(null);
  double _scrollOffset = 0;

  @override
  ValueListenable<String?> get selectedMemberRef => _selectedMemberRef;
  @override
  double get scrollOffset => _scrollOffset;

  @override
  void selectMember(String? memberRef) {
    if (_disposed || _suspended) return;
    if (memberRef != null &&
        !_projection.value.members.any(
          (member) => member.memberRef == memberRef,
        )) {
      return;
    }
    _selectedMemberRef.value = memberRef;
  }

  @override
  void rememberScrollOffset(double value) {
    if (!_disposed && !_suspended && value.isFinite && value >= 0) {
      _scrollOffset = value;
    }
  }

  int _requestRevision = 0;
  bool _suspended = true;
  bool _disposed = false;

  @override
  ValueListenable<OfficialFleetMemberDirectoryProjection> get projection =>
      _projection;

  @override
  Future<void> open(String sourceRef) async {
    if (_disposed || sourceRef.isEmpty) {
      return;
    }
    _suspended = false;
    if (_query?.sourceRef == sourceRef) {
      if (_projection.value.availability ==
          OfficialFleetMemberDirectoryAvailability.idle) {
        await refresh();
      }
      return;
    }
    _query = OfficialFleetMemberDirectoryQuery(sourceRef: sourceRef);
    _selectedMemberRef.value = null;
    _scrollOffset = 0;
    await refresh();
  }

  @override
  Future<void> search(String value) => _replaceQuery(
    (query) => query.copyWith(search: value.trim(), pageNumber: 1),
  );

  @override
  Future<void> setFilter(OfficialFleetMemberFilter value) async {
    if (!_projection.value.supportedFilters.contains(value)) return;
    await _replaceQuery(
      (query) => query.copyWith(filter: value, pageNumber: 1),
    );
  }

  @override
  Future<void> setPageSize(int value) async {
    if (![25, 50, 100].contains(value)) return;
    await _replaceQuery(
      (query) => query.copyWith(pageSize: value, pageNumber: 1),
    );
  }

  @override
  Future<void> goToPage(int value) {
    final totalPages = _projection.value.totalPages;
    if (totalPages == null || totalPages < 1) return Future.value();
    final page = value.clamp(1, totalPages);
    return _replaceQuery((query) => query.copyWith(pageNumber: page));
  }

  Future<void> _replaceQuery(
    OfficialFleetMemberDirectoryQuery Function(
      OfficialFleetMemberDirectoryQuery query,
    )
    update,
  ) async {
    final query = _query;
    if (_disposed || _suspended || query == null) {
      return;
    }
    _query = update(query);
    _selectedMemberRef.value = null;
    _scrollOffset = 0;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    final query = _query;
    if (_disposed || _suspended || query == null) {
      return;
    }
    final revision = ++_requestRevision;
    _projection.value = OfficialFleetMemberDirectoryProjection.loading(query);
    try {
      final snapshot = await _port.read(query);
      if (_disposed || revision != _requestRevision) {
        return;
      }
      if (snapshot.query.sourceRef != query.sourceRef ||
          snapshot.query.search != query.search ||
          snapshot.query.filter != query.filter ||
          snapshot.query.pageNumber != query.pageNumber ||
          snapshot.query.pageSize != query.pageSize ||
          snapshot.members.any((member) => member.memberRef.trim().isEmpty) ||
          snapshot.members.map((member) => member.memberRef).toSet().length !=
              snapshot.members.length) {
        throw StateError('Invalid member directory projection');
      }
      if (!snapshot.members.any(
        (member) => member.memberRef == _selectedMemberRef.value,
      )) {
        _selectedMemberRef.value = null;
      }
      _projection.value = OfficialFleetMemberDirectoryProjection.fromSnapshot(
        snapshot,
      );
    } on Object {
      if (_disposed || revision != _requestRevision) {
        return;
      }
      _selectedMemberRef.value = null;
      _projection.value = OfficialFleetMemberDirectoryProjection.fromSnapshot(
        OfficialFleetMemberDirectorySnapshot.unavailable(
          query: query,
          failureKey: 'officialFleet.members.error.unavailable',
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
    _suspended = true;
    _selectedMemberRef.value = null;
    if (!preserveQuery) {
      _query = null;
      _scrollOffset = 0;
    }
    _projection.value = const OfficialFleetMemberDirectoryProjection.idle();
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
    _selectedMemberRef.dispose();
    unawaited(_port.close());
  }
}
