import 'dart:async';

import 'package:flutter/foundation.dart';

import 'personal_profile_models.dart';
import 'personal_profile_port.dart';
import 'personal_profile_visibility.dart';
import 'personal_profile_wallpaper_catalog.dart';
import 'profile_read_failure.dart';
import 'profile_read_scope.dart';
import 'personal_profile_draft.dart';
import 'personal_profile_read_admission.dart';

/// Holds the current editing revision while display updates are deferred.
/// Hard ownership invalidation still ends editing immediately.
abstract interface class PersonalProfileEditingSession {
  bool beginEditing();
  void endEditing();
}

abstract interface class PersonalProfileModule {
  ValueListenable<PersonalProfileProjection> get projection;

  Future<PersonalProfileActionResult> initialize();
  Future<PersonalProfileActionResult> refresh();
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit);
  void renameCommunity(String code, String name);
  void dispose();
}

PersonalProfileModule createPersonalProfileModule(
  PersonalProfilePort port, {
  // Read-only observer refresh after the complete coordinated save settles.
  // Failure may still mean a remote step committed; never resubmit here.
  VoidCallback? onSaveSettled,
  DateTime Function()? clock,
  // Visitor reads can require revalidation before showing any prior content.
  bool retainContentOnRefresh = true,
}) => _DefaultPersonalProfileModule(
  port,
  onSaveSettled,
  clock ?? DateTime.now,
  retainContentOnRefresh,
);

final class _DefaultPersonalProfileModule
    implements
        PersonalProfileModule,
        ProfileVisibilityAccess,
        PersonalProfileEditingSession,
        ProfileReadScopeOwner,
        ProfileReadObservationOwner,
        PersonalProfileDraftSession,
        PersonalProfileReadAdmission {
  _DefaultPersonalProfileModule(
    this._port,
    this._onSaveSettled,
    this._clock,
    this._retainContentOnRefresh,
  ) {
    _invalidationSubscription = _port.invalidations.listen((_) {
      if (!_disposed) {
        _readScope = null;
        _readObservation = ProfileReadObservation(
          _activeReadGeneration,
          ProfileReadPhase.invalidated,
          accountAdvance: _port is ProfileReadAccountAdvanceOwner
              ? (_port as ProfileReadAccountAdvanceOwner).readAccountAdvance
              : null,
        );
        _epoch++;
        _editing = false;
        _draft = null;
        _draftRequiresReload = false;
        _editorVersion++;
        _pendingNames.clear();
        _projection.value = const PersonalProfileProjection.loading();
        if (_reading) {
          _refreshPending = true;
        } else {
          _refreshPending = false;
          unawaited(refresh());
        }
      }
    });
    if (_port case PersonalProfileContentChanges source) {
      _changesSubscription = source.changes.listen((_) {
        if (_disposed) return;
        _refreshPending = true;
        _drainRefresh();
      });
    }
  }

  final PersonalProfilePort _port;
  final VoidCallback? _onSaveSettled;
  final DateTime Function() _clock;
  final bool _retainContentOnRefresh;
  StreamSubscription<void>? _changesSubscription;
  final _readAdmissions = <bool Function()>{};
  bool get _readsAdmitted =>
      !_disposed && _readAdmissions.every((admit) => admit());
  @override
  VoidCallback registerReadAdmission(bool Function() admitsRead) {
    _readAdmissions.add(admitsRead);
    return () => _readAdmissions.remove(admitsRead);
  }

  @override
  void resumeAdmittedReads() => _drainRefresh();
  bool _editing = false;
  PersonalProfileEditorDraft? _draft;
  bool _draftRequiresReload = false;
  int _editorVersion = 0;
  @override
  bool get editingLeaseActive => !_disposed && _editing;
  @override
  bool get draftRequiresReload => _draftRequiresReload;
  @override
  bool keepEditorDraft(PersonalProfileEditorDraft draft) {
    if (_disposed ||
        !_editing ||
        _projection.value.availability !=
            PersonalProfileAvailability.available) {
      return false;
    }
    _draft = draft;
    _editorVersion++;
    return true;
  }

  @override
  PersonalProfileEditorDraft? takeEditorDraft() {
    if (_disposed ||
        !_editing ||
        !_projection.value.canEdit &&
            _projection.value.operation != PersonalProfileOperation.saving) {
      return null;
    }
    final draft = _draft;
    _draft = null;
    return draft;
  }

  ProfileReadScope? _readScope;
  @override
  ProfileReadScope? get readScope => _readScope;
  ProfileReadObservation? _readObservation;
  @override
  ProfileReadObservation? get readObservation => _readObservation;
  int? get _activeReadGeneration => _port is ProfileReadGenerationOwner
      ? (_port as ProfileReadGenerationOwner).activeReadGeneration
      : null;

  @override
  bool beginEditing() {
    if (_disposed || _editing || _reading || !_projection.value.canEdit) {
      return false;
    }
    _editing = true;
    _draftRequiresReload = false;
    return true;
  }

  @override
  void endEditing() {
    if (!_editing) return;
    _editing = false;
    _draft = null;
    _draftRequiresReload = false;
    _editorVersion++;
    _drainRefresh();
  }

  void _drainRefresh() {
    if (_readsAdmitted &&
        _refreshPending &&
        !_editing &&
        !_reading &&
        _projection.value.operation != PersonalProfileOperation.saving) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  @override
  Future<ProfileVisibilityState> readVisibility() async {
    final epoch = _epoch;
    final port = _port;
    if (_disposed ||
        !_projection.value.canEdit ||
        port is! ProfileVisibilityAccess) {
      throw StateError('unavailable');
    }
    final state = await (port as ProfileVisibilityAccess).readVisibility();
    if (_disposed || epoch != _epoch) throw StateError('stale');
    return state;
  }

  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  ) async {
    final epoch = _epoch;
    final port = _port;
    if (_disposed ||
        !_projection.value.canEdit ||
        port is! ProfileVisibilityAccess) {
      throw StateError('unavailable');
    }
    final state = await (port as ProfileVisibilityAccess).saveVisibility(
      expected,
      visibility,
    );
    if (_disposed || epoch != _epoch) throw StateError('stale');
    _projection.value = _projection.value.copyWith(
      visibility: state.visibility,
    );
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
    if (!_readsAdmitted) {
      if (!_disposed) _refreshPending = true;
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (_reading) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (_editing ||
        _projection.value.operation == PersonalProfileOperation.saving) {
      _refreshPending = true;
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    _refreshPending = false;
    _reading = true;
    _pendingNames.clear();
    final epoch = _epoch;
    // The policy also fences transient failures: a visitor's previous result
    // must not be restored after the refresh has withdrawn it from display.
    final previous = _retainContentOnRefresh
        ? _projection.value
        : const PersonalProfileProjection.loading();
    final generation = _activeReadGeneration;
    _readObservation = ProfileReadObservation(
      generation,
      ProfileReadPhase.reading,
    );
    _projection.value =
        previous.availability != PersonalProfileAvailability.loading &&
            previous.availability != PersonalProfileAvailability.signedOut
        ? _projection.value.copyWith(
            operation: PersonalProfileOperation.refreshing,
            refreshFailed: false,
            clearFailure: true,
          )
        : const PersonalProfileProjection.loading();
    PersonalProfileSnapshot snapshot;
    try {
      snapshot = await _port.read();
    } catch (error) {
      snapshot = PersonalProfileSnapshot.unavailable(
        transientReadFailure: profileReadIsTransient(error),
      );
    } finally {
      _reading = false;
    }
    if (_disposed) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    if (epoch == _epoch) {
      _readObservation = ProfileReadObservation(
        generation,
        snapshot.availability == PersonalProfileAvailability.available
            ? ProfileReadPhase.available
            : snapshot.transientReadFailure
            ? ProfileReadPhase.transientFailure
            : ProfileReadPhase.unavailable,
      );
      if (!snapshot.transientReadFailure &&
          snapshot.availability != PersonalProfileAvailability.available) {
        _readScope = null;
      }
      var next = PersonalProfileProjection.fromSnapshot(snapshot);
      if (snapshot.availability == PersonalProfileAvailability.available) {
        _readScope = _port is ProfileReadScopeOwner
            ? (_port as ProfileReadScopeOwner).readScope
            : null;
        next = next.copyWith(
          synchronizedAtUtc: snapshot.cachedAtUtc?.toUtc() ?? _clock().toUtc(),
        );
      } else if (snapshot.availability ==
              PersonalProfileAvailability.unavailable &&
          snapshot.transientReadFailure &&
          previous.availability == PersonalProfileAvailability.available) {
        next = previous.copyWith(
          operation: PersonalProfileOperation.none,
          allowEditing: false,
          refreshFailed: true,
          failureKey: snapshot.failureKey ?? 'profile.error.unavailable',
        );
      }
      for (final entry in _pendingNames.entries.toList()) {
        next = _renamed(next, entry.key, entry.value);
      }
      _projection.value = next;
    }
    _drainRefresh();
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
    final editorVersion = _editorVersion;
    final result = await _port.save(edit);
    if (_disposed || epoch != _epoch) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    _draftRequiresReload = result.requiresReload;
    if (result.outcome == PersonalProfileActionOutcome.completed &&
        editorVersion != _editorVersion) {
      _draft = null;
      _editing = false;
    }
    // An observer cannot turn a settled write into an apparent write failure.
    // Epoch validation above prevents old-account completions from notifying.
    try {
      _onSaveSettled?.call();
    } on Object {
      // Observer refresh is best effort, independent of the write outcome.
    }
    if (result.outcome == PersonalProfileActionOutcome.completed) {
      _projection.value = _projection.value.copyWith(
        operation: PersonalProfileOperation.none,
      );
      _refreshPending = false;
      await refresh();
    } else {
      _projection.value = _projection.value.copyWith(
        operation: PersonalProfileOperation.none,
        failureKey: result.failureKey ?? 'profile.error.saveFailed',
      );
      _drainRefresh();
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
    _readAdmissions.clear();
    _draft = null;
    _editing = false;
    unawaited(_invalidationSubscription.cancel());
    unawaited(_changesSubscription?.cancel());
    _projection.dispose();
    unawaited(_port.close());
  }
}
