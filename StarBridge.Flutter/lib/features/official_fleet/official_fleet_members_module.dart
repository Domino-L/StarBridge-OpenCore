import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_fleet_members_models.dart';
import 'official_fleet_members_port.dart';
import 'official_fleet_self_presence.dart';
export 'official_fleet_self_presence.dart';

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
  Future<void> refresh({bool silent = false});
  void bindSelfPresence(
    Listenable changes,
    OfficialFleetSelfPresence Function(String sourceRef) read,
  );
  void reset({bool preserveQuery = false});
  void dispose();
}

OfficialFleetMembersModule createOfficialFleetMembersModule(
  OfficialFleetMembersPort port, {
  DateTime Function()? now,
}) => _DefaultOfficialFleetMembersModule(port, now ?? DateTime.now);

final class _DefaultOfficialFleetMembersModule
    implements OfficialFleetMembersModule {
  _DefaultOfficialFleetMembersModule(this._port, this._now) {
    _subscription = _port.invalidations.listen((_) {
      if (!_disposed && _query != null) {
        unawaited(refresh());
      }
    });
    if (_port case final OfficialFleetMembersActivityPort activity) {
      _runtimeChanges = activity.runtimeChanges.listen((_) {
        if (!_disposed && !_suspended && _query != null) {
          unawaited(refresh(silent: true));
        }
      });
      _runtimeInvalidations = activity.runtimeScopeInvalidations.listen((_) {
        final query = _query;
        if (_disposed || _suspended || query == null) return;
        ++_requestRevision;
        _readTask = null;
        _pendingReread = false;
        _snapshot = null;
        _clearRetry();
        _selectedMemberRef.value = null;
        _projection.value = OfficialFleetMemberDirectoryProjection.loading(
          query,
          presenceWasShown: _presenceShown,
        );
        unawaited(refresh());
      });
    }
  }

  final OfficialFleetMembersPort _port;
  final DateTime Function() _now;
  final ValueNotifier<OfficialFleetMemberDirectoryProjection> _projection =
      ValueNotifier(const OfficialFleetMemberDirectoryProjection.idle());
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _runtimeChanges, _runtimeInvalidations;
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
  Future<void>? _readTask;
  bool _pendingReread = false;
  OfficialFleetMemberDirectorySnapshot? _snapshot;
  Listenable? _localChanges;
  OfficialFleetSelfPresence Function(String)? _localPresence;

  @override
  void bindSelfPresence(
    Listenable changes,
    OfficialFleetSelfPresence Function(String) read,
  ) {
    _localChanges?.removeListener(_publishLocal);
    _localChanges = changes;
    _localPresence = read;
    changes.addListener(_publishLocal);
    _publishLocal();
  }

  void _publishLocal() {
    final snapshot = _snapshot;
    if (_disposed ||
        _suspended ||
        snapshot == null ||
        _projection.value.availability !=
            OfficialFleetMemberDirectoryAvailability.available) {
      return;
    }
    final previous = _projection.value;
    final next = _project(snapshot, previous.lastReadAtUtc);
    if (listEquals(previous.members, next.members)) return;
    _projection.value = previous.isRefreshing
        ? OfficialFleetMemberDirectoryProjection.refreshing(next)
        : next;
  }

  OfficialFleetMemberDirectoryProjection _project(
    OfficialFleetMemberDirectorySnapshot snapshot,
    DateTime? readAt,
  ) {
    final old = {for (final m in _projection.value.members) m.memberRef: m};
    final local = snapshot.runtimeCapabilities.presence
        ? _localPresence?.call(snapshot.query.sourceRef)
        : null;
    _presenceShown =
        _presenceShown ||
        snapshot.availability ==
                OfficialFleetMemberDirectoryAvailability.available &&
            snapshot.runtimeCapabilities.presence;
    return OfficialFleetMemberDirectoryProjection.fromSnapshot(
      snapshot,
      lastReadAtUtc: readAt,
      presenceWasShown: _presenceShown,
      projectedMembers: snapshot.members.map((member) {
        final next = local?.project(member) ?? member;
        final previous = old[next.memberRef];
        return previous != null && previous.sameValue(next) ? previous : next;
      }).toList(),
    );
  }

  bool _suspended = true;
  bool _disposed = false;
  bool _presenceShown = false;

  // A failed read clears the page's rows, so look again soon rather than wait
  // for the next hint. Bounded: each read costs requests upstream.
  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];
  Timer? _retry;
  int _retries = 0;

  void _clearRetry() {
    _retry?.cancel();
    _retry = null;
    _retries = 0;
  }

  void _retryAfterFailure() {
    _retry?.cancel();
    _retry = null;
    final failure = _projection.value.failureKey;
    if (failure == null) {
      _retries = 0;
      return;
    }
    if (_retries >= _retryDelays.length ||
        !const {
          'officialFleet.members.error.transient',
          'officialFleet.members.error.unavailable',
        }.contains(failure)) {
      return;
    }
    _retry = Timer(_retryDelays[_retries++], () {
      _retry = null;
      unawaited(refresh(silent: true));
    });
  }

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
    reset();
    _suspended = false;
    _query = OfficialFleetMemberDirectoryQuery(sourceRef: sourceRef);
    _selectedMemberRef.value = null;
    _scrollOffset = 0;
    await refresh();
  }

  @override
  Future<void> search(String value) {
    final search = value.trim();
    if (!OfficialFleetMemberDirectoryQuery.isValidSearch(search)) {
      return Future.value();
    }
    return _replaceQuery(
      (query) => query.copyWith(search: search, pageNumber: 1),
    );
  }

  @override
  Future<void> setFilter(OfficialFleetMemberFilter value) async {
    if (value != OfficialFleetMemberFilter.all &&
        !_projection.value.runtimeCapabilities.presence) {
      return;
    }
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
    final next = update(query);
    if (_sameQuery(query, next)) return refresh();
    _query = next;
    _readTask = null;
    _pendingReread = false;
    _snapshot = null;
    _clearRetry();
    _selectedMemberRef.value = null;
    _scrollOffset = 0;
    await refresh();
  }

  @override
  Future<void> refresh({bool silent = false}) {
    final query = _query;
    if (_disposed || _suspended || query == null) {
      return Future.value();
    }
    // Any read in progress decides what comes next, not an older retry.
    _retry?.cancel();
    _retry = null;
    if (_readTask != null) {
      if (silent) _pendingReread = true;
      if (!silent) _showLoading(query);
      return _readTask!;
    }
    final revision = ++_requestRevision;
    if (!silent) _showLoading(query);
    return _readTask = _drainRead(query, revision).whenComplete(() {
      if (revision == _requestRevision) _readTask = null;
    });
  }

  Future<void> _drainRead(
    OfficialFleetMemberDirectoryQuery query,
    int revision,
  ) async {
    do {
      _pendingReread = false;
      await _read(query, revision);
      if (_disposed || _suspended || revision != _requestRevision) return;
    } while (_pendingReread);
    _retryAfterFailure();
  }

  void _showLoading(OfficialFleetMemberDirectoryQuery query) {
    final previous = _projection.value;
    _projection.value =
        previous.availability ==
                OfficialFleetMemberDirectoryAvailability.available &&
            previous.query != null &&
            _sameQuery(previous.query!, query)
        ? OfficialFleetMemberDirectoryProjection.refreshing(previous)
        : OfficialFleetMemberDirectoryProjection.loading(
            query,
            presenceWasShown: _presenceShown,
          );
  }

  Future<void> _read(
    OfficialFleetMemberDirectoryQuery query,
    int revision,
  ) async {
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
      final previous = _projection.value;
      if (snapshot.availability ==
              OfficialFleetMemberDirectoryAvailability.unavailable &&
          snapshot.transientFailure &&
          previous.availability ==
              OfficialFleetMemberDirectoryAvailability.available &&
          !previous.members.any((member) => member.identityState != null) &&
          previous.query != null &&
          _sameQuery(previous.query!, query)) {
        _projection.value = OfficialFleetMemberDirectoryProjection.retained(
          previous,
          failureKey:
              snapshot.failureKey ?? 'officialFleet.members.error.transient',
        );
        return;
      }
      if (!snapshot.members.any(
        (member) => member.memberRef == _selectedMemberRef.value,
      )) {
        _selectedMemberRef.value = null;
      }
      _snapshot = snapshot;
      _projection.value = _project(
        snapshot,
        snapshot.availability ==
                OfficialFleetMemberDirectoryAvailability.available
            ? _now().toUtc()
            : null,
      );
    } on Object {
      if (_disposed || revision != _requestRevision) {
        return;
      }
      _selectedMemberRef.value = null;
      _snapshot = null;
      _projection.value = OfficialFleetMemberDirectoryProjection.fromSnapshot(
        OfficialFleetMemberDirectorySnapshot.unavailable(
          query: query,
          failureKey: 'officialFleet.members.error.unavailable',
        ),
        presenceWasShown: _presenceShown,
      );
    }
  }

  @override
  void reset({bool preserveQuery = false}) {
    if (_disposed) {
      return;
    }
    ++_requestRevision;
    if (_port case final OfficialFleetMembersActivityPort activity) {
      activity.retireRuntimeActivity();
    }
    _readTask = null;
    _pendingReread = false;
    _snapshot = null;
    _suspended = true;
    _presenceShown = false;
    _clearRetry();
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
    _clearRetry();
    _localChanges?.removeListener(_publishLocal);
    unawaited(_runtimeChanges?.cancel());
    unawaited(_runtimeInvalidations?.cancel());
    _requestRevision++;
    unawaited(_subscription.cancel());
    _projection.dispose();
    _selectedMemberRef.dispose();
    unawaited(_port.close());
  }
}

bool _sameQuery(
  OfficialFleetMemberDirectoryQuery a,
  OfficialFleetMemberDirectoryQuery b,
) =>
    a.sourceRef == b.sourceRef &&
    a.search == b.search &&
    a.filter == b.filter &&
    a.pageNumber == b.pageNumber &&
    a.pageSize == b.pageSize;
