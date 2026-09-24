import 'dart:async';

import 'package:flutter/foundation.dart';

import 'personal_profile_models.dart';
import 'personal_profile_port.dart';
import 'personal_profile_visibility.dart';
import 'personal_profile_wallpaper_catalog.dart';

abstract interface class PersonalProfileModule {
  ValueListenable<PersonalProfileProjection> get projection;

  Future<PersonalProfileActionResult> initialize();
  Future<PersonalProfileActionResult> refresh();
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit);
  void renameCommunity(String code, String name);
  void dispose();
}

PersonalProfileModule createPersonalProfileModule(PersonalProfilePort port) =>
    _DefaultPersonalProfileModule(port);

final class _DefaultPersonalProfileModule implements PersonalProfileModule, ProfileVisibilityAccess {
  _DefaultPersonalProfileModule(this._port) {
    _invalidationSubscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        _epoch++;
        _pendingNames.clear();
        _projection.value = const PersonalProfileProjection.loading();
        if (_reading) {
          _refreshPending = true;
        } else {
          unawaited(refresh());
        }
      }
    });
  }

  final PersonalProfilePort _port;

  @override
  Future<ProfileVisibilityState> readVisibility() async {
    final epoch = _epoch;
    final port = _port;
    if (_disposed || port is! ProfileVisibilityAccess) throw StateError('unavailable');
    final state = await (port as ProfileVisibilityAccess).readVisibility();
    if (_disposed || epoch != _epoch) throw StateError('stale');
    return state;
  }

  @override
  Future<ProfileVisibilityState> saveVisibility(ProfileVisibilityState expected,
      PersonalProfileVisibility visibility) async {
    final epoch = _epoch;
    final port = _port;
    if (_disposed || port is! ProfileVisibilityAccess) throw StateError('unavailable');
    final state = await (port as ProfileVisibilityAccess).saveVisibility(expected, visibility);
    if (_disposed || epoch != _epoch) throw StateError('stale');
    _projection.value = _projection.value.copyWith(visibility: state.visibility);
    return state;
  }
  final ValueNotifier<PersonalProfileProjection> _projection = ValueNotifier(
    const PersonalProfileProjection.loading(),
  );
  bool _disposed = false;
  bool _initialized = false;
  bool _reading = false;
  bool _refreshPending = false;
  int _epoch = 0;
  final _pendingNames = <String, String>{};
  late final StreamSubscription<void> _invalidationSubscription;

  @override
  ValueListenable<PersonalProfileProjection> get projection => _projection;

  @override
  Future<PersonalProfileActionResult> initialize() async {
    if (_disposed) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (_initialized) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
      );
    }
    _initialized = true;
    return refresh();
  }

  @override
  Future<PersonalProfileActionResult> refresh() async {
    if (_disposed) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (_reading) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    _reading = true;
    _pendingNames.clear();
    final epoch = _epoch;
    _projection.value =
        _projection.value.availability ==
            PersonalProfileAvailability.unavailable
        ? _projection.value.copyWith(
            operation: PersonalProfileOperation.refreshing,
          )
        : const PersonalProfileProjection.loading();
    final snapshot = await _port.read();
    _reading = false;
    if (_disposed) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (epoch == _epoch) {
      var next = PersonalProfileProjection.fromSnapshot(snapshot);
      for (final entry in _pendingNames.entries.toList()) {
        next = _renamed(next, entry.key, entry.value);
      }
      _projection.value = next;
    }
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
    return const PersonalProfileActionResult(
      PersonalProfileActionOutcome.completed,
    );
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    if (_disposed ||
        !_projection.value.canEdit ||
        edit.callSign.trim().isEmpty ||
        !PersonalProfileWallpaperCatalog.contains(edit.wallpaperId)) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    final epoch = _epoch;
    _projection.value = _projection.value.copyWith(
      operation: PersonalProfileOperation.saving,
      clearFailure: true,
    );
    final result = await _port.save(edit);
    if (_disposed || epoch != _epoch) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (result.outcome == PersonalProfileActionOutcome.completed) {
      await refresh();
    } else {
      _projection.value = _projection.value.copyWith(
        operation: PersonalProfileOperation.none,
        failureKey: result.failureKey ?? 'profile.error.saveFailed',
      );
    }
    return result;
  }

  @override
  void renameCommunity(String code, String name) {
    if (_disposed) return;
    if (_reading) _pendingNames[code] = name;
    _projection.value = _renamed(_projection.value, code, name);
  }

  PersonalProfileProjection _renamed(
    PersonalProfileProjection before,
    String code,
    String name,
  ) {
    if (!before.affiliations.any(
      (row) =>
          row.kind == PersonalProfileAffiliationKind.featuredCommunity &&
          row.code == code &&
          row.name != name,
    )) {
      return before;
    }
    return before.copyWith(
      affiliations: List.unmodifiable(
        before.affiliations.map(
          (row) =>
              row.kind == PersonalProfileAffiliationKind.featuredCommunity &&
                  row.code == code
              ? PersonalProfileAffiliationSummary(
                  kind: row.kind,
                  name: name,
                  code: row.code,
                  positionLabelKey: row.positionLabelKey,
                  logoUrl: row.logoUrl,
                  logoImageData: row.logoImageData,
                )
              : row,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_invalidationSubscription.cancel());
    _projection.dispose();
    unawaited(_port.close());
  }
}
