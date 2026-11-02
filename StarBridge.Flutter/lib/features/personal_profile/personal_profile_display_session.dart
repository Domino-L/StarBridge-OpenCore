import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import 'personal_profile_module.dart';
import 'personal_profile_models.dart';
import 'personal_profile_port.dart';
import 'profile_read_scope.dart';
import 'readonly_profile_handoff.dart';
import 'personal_profile_view_state.dart';
import 'personal_profile_access.dart';
import 'personal_profile_visibility.dart';
import 'personal_profile_draft.dart';
import 'personal_profile_read_admission.dart';

/// Feature-owned display lifetime. Original online business module is borrowed.
final class PersonalProfileDisplaySession extends ChangeNotifier
    implements PersonalProfileAccess, ProfileVisibilityAccess {
  PersonalProfileDisplaySession({
    required this.mode,
    required this.createPort,
    required this.onlineModule,
    this.account,
    this.createRetainedPort,
  }) {
    if (onlineModule is PersonalProfileReadAdmission) {
      _releaseReadAdmission = (onlineModule as PersonalProfileReadAdmission)
          .registerReadAdmission(_readAdmitted);
    }
    _trackAdmission();
    mode.addListener(_changed);
    account?.addListener(_changed);
    onlineModule?.projection.addListener(_changed);
  }
  final ConnectionModeControl mode;
  final PersonalProfilePort Function() createPort;
  final PersonalProfileModule? onlineModule;
  final ValueListenable<AccountProjection>? account;
  final PersonalProfilePort Function(String readId)? createRetainedPort;
  VoidCallback? _releaseReadAdmission;
  int _admissionEpoch = 0;
  bool _lastReadAdmitted = true;
  Object? _admissionStamp;
  bool _activated = false, _disposed = false;
  PersonalProfileModule? get displayModule =>
      _module == null &&
          onlineModule?.projection.value.availability ==
              PersonalProfileAvailability.signedOut
      ? onlineModule
      : _usingFresh
      ? onlineModule
      : _module ?? _normalGate;
  bool get onlineDisplay =>
      !_disposed && (_module == null ? _normalGate == null : _usingFresh);
  Object? get pageKey => _key;
  void activate() {
    if (_disposed) return;
    _activated = true;
    _trackAdmission();
    _resumeReading();
    _sync();
    _syncNormal();
  }

  void _changed() {
    if (!_disposed && _activated) {
      _trackAdmission();
      _resumeReading();
      _sync();
      _syncNormal();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    mode.removeListener(_changed);
    account?.removeListener(_changed);
    onlineModule?.projection.removeListener(_changed);
    _module?.dispose();
    _normalGate?.dispose();
    _view.current = false;
    _blockedView.current = false;
    if (onlineModule is PersonalProfileDraftSession &&
        (onlineModule as PersonalProfileDraftSession).editingLeaseActive &&
        onlineModule is PersonalProfileEditingSession) {
      (onlineModule as PersonalProfileEditingSession).endEditing();
    }
    _releaseReadAdmission?.call();
    _releaseReadAdmission = null;
    super.dispose();
  }

  void _trackAdmission() {
    final stamp = (
      _binding,
      mode.failed,
      mode.allowsOnlineTraffic,
      account?.value.sessionState,
    );
    if (stamp != _admissionStamp) {
      _admissionStamp = stamp;
      _admissionEpoch++;
    }
  }

  bool _readAdmitted() {
    if (_disposed) return false;
    if (!_activated) return true;
    if (!_modeAdmitted) return false;
    final current = account?.value;
    final proof = current?.hasDisplayHandoff == true
        ? current?.displayHandoff
        : _confirmedFresh &&
              current?.isSignedIn == true &&
              current?.generation == _acceptedHandoff?.generation
        ? _acceptedHandoff
        : null;
    // Loading account preferences is not a veto on the original Native root.
    // The port still obtains a new root and validates its actual domain owner.
    return proof != null && _sameDisplayMode(proof) || _normalModeMatches;
  }

  void _resumeReading() {
    final admitted = _readAdmitted();
    final resume = !_lastReadAdmitted && admitted;
    _lastReadAdmitted = admitted;
    if (resume && onlineModule is PersonalProfileReadAdmission) {
      (onlineModule as PersonalProfileReadAdmission).resumeAdmittedReads();
    }
  }

  PersonalProfileViewState _view = PersonalProfileViewState();
  PersonalProfileViewState _blockedView = PersonalProfileViewState();
  PersonalProfileViewState get view =>
      _normalGate == null ? _view : _blockedView;
  ReadonlyProfileHandoff? _normalGate;
  (int?, Object, int?, ConnectionModeState)? _normalBinding;
  ProfileReadScope? _normalScope;
  ProfileReadObservation? _normalRetired;
  bool _normalNeedsRead = false, _normalSawReading = false;
  bool _normalRequested = false, _normalHard = false;
  bool _normalFirstRead = false;

  void _clearView() {
    _view.current = false;
    _blockedView.current = false;
    _view = PersonalProfileViewState();
    _blockedView = PersonalProfileViewState();
  }

  (int?, Object, int?, ConnectionModeState) get _binding => (
    account?.value.generation,
    mode.snapshot.scope,
    mode.snapshot.revision,
    mode.snapshot.state,
  );
  bool get _modeAdmitted =>
      !_disposed && !mode.failed && mode.allowsOnlineTraffic;
  bool get _accountAdmitted =>
      account == null ||
      account!.value.isSignedIn ||
      account!.value.isLegacyAccount;
  ProfileReadScope? get _scope => onlineModule is ProfileReadScopeOwner
      ? (onlineModule as ProfileReadScopeOwner).readScope
      : null;
  ProfileReadObservation? get _observation =>
      onlineModule is ProfileReadObservationOwner
      ? (onlineModule as ProfileReadObservationOwner).readObservation
      : null;
  bool get _normalReadMatches {
    final generation = account?.value.generation ?? _observation?.generation;
    // Ports without a domain receipt remain useful for review/local adapters;
    // production Bridge ports always publish a scoped receipt.
    return _observation?.generation == null ||
        _scope != null &&
            _scope!.generation == generation &&
            _observation!.generation == generation;
  }

  bool get _normalModeMatches =>
      account == null ||
      // Unsupported has no account mode owner. Preserve the controller's
      // original traffic policy and the independently checked domain receipt.
      mode.snapshot.state == ConnectionModeState.unsupported && _modeAdmitted ||
      mode.snapshot.scope == account!.value.generation;
  bool get _hasLease =>
      onlineModule is PersonalProfileDraftSession &&
      (onlineModule as PersonalProfileDraftSession).editingLeaseActive;

  void _withdrawNormal({bool hard = false}) {
    if (_normalGate == null) {
      _normalFirstRead = _normalBinding == null;
      _normalRetired = _observation;
      _normalNeedsRead = true;
      _normalSawReading = false;
      _normalRequested = false;
      _normalGate = ReadonlyProfileHandoff(
        PersonalProfileProjection.fromSnapshot(
          PersonalProfileSnapshot.unavailable(
            failureKey: 'profile.error.unavailable',
          ),
        ),
        onRefresh: _retryNormal,
      )..withdraw('profile.error.unavailable');
    }
    if (hard && !_normalHard) {
      _normalHard = true;
      _normalFirstRead = false;
      _clearView();
      if (onlineModule is PersonalProfileEditingSession) {
        (onlineModule as PersonalProfileEditingSession).endEditing();
      }
    }
  }

  void _syncNormal() {
    if (_module != null || onlineModule == null) return;
    final binding = _binding;
    if (!_modeAdmitted || !_accountAdmitted || !_normalModeMatches) {
      _withdrawNormal(
        hard:
            _normalBinding != null &&
            ((account?.value.generation != _normalBinding!.$1) ||
                mode.snapshot.state == ConnectionModeState.online &&
                    _normalBinding != binding ||
                !_accountAdmitted),
      );
      // Every unconfirmed interval retires its own outstanding revalidation.
      _normalRetired = _observation;
      _normalSawReading = false;
      _normalRequested = false;
      return;
    }
    if (_normalBinding != null && _normalBinding != binding) {
      _withdrawNormal(hard: true);
    }
    _normalBinding ??= binding;
    if (_normalGate == null) {
      if (_observation?.phase == ProfileReadPhase.available &&
          !_normalReadMatches) {
        _withdrawNormal(hard: true);
      } else {
        _normalScope = _scope;
        return;
      }
    }
    // A failed mode observation quarantines a still-live editor. Only the exact
    // original mode and read receipt can resume that lease without rebasing it.
    if (!_normalHard &&
        _normalBinding == binding &&
        _hasLease &&
        (_normalScope?.sameOwner(_scope) ?? _observation?.generation == null)) {
      _normalGate!.dispose();
      _normalGate = null;
      _normalNeedsRead = false;
      return;
    }
    final observed = _observation;
    if (_normalNeedsRead &&
        observed?.phase == ProfileReadPhase.reading &&
        !identical(observed, _normalRetired)) {
      _normalSawReading = true;
    }
    if ((_normalSawReading || _normalFirstRead) &&
        observed?.phase == ProfileReadPhase.available &&
        _normalReadMatches &&
        onlineModule!.projection.value.availability ==
            PersonalProfileAvailability.available) {
      _normalGate!.dispose();
      _normalGate = null;
      _normalNeedsRead = false;
      _normalHard = false;
      _normalBinding = binding;
      _normalScope = _scope;
      return;
    }
    _normalGate!.observe(
      waiting: observed?.phase == ProfileReadPhase.reading,
      failureKey: onlineModule!.projection.value.failureKey,
    );
    if (!_normalRequested && observed?.phase != ProfileReadPhase.reading) {
      _normalRequested = true;
      scheduleMicrotask(() {
        if (!_disposed && _normalGate != null) unawaited(_retryNormal());
      });
    }
  }

  Future<PersonalProfileActionResult> _retryNormal() async {
    if (!_modeAdmitted ||
        !_accountAdmitted ||
        !_normalModeMatches ||
        _hasLease) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    return onlineModule!.refresh();
  }

  @override
  bool get permitsEditing =>
      _modeAdmitted &&
      _accountAdmitted &&
      onlineDisplay &&
      onlineModule?.projection.value.canEdit == true &&
      (_acceptedHandoff != null
          ? _scope?.matches(_acceptedHandoff!) == true
          : _normalModeMatches && _normalReadMatches);
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      permitsEditing &&
          !(onlineModule is PersonalProfileDraftSession &&
              (onlineModule as PersonalProfileDraftSession).draftRequiresReload)
      ? onlineModule!.save(edit)
      : const PersonalProfileActionResult(
          PersonalProfileActionOutcome.rejected,
        );
  @override
  ProfileVisibilityAccess get visibility => this;
  ProfileVisibilityAccess _visibilityOwner() {
    if (!permitsEditing || onlineModule is! ProfileVisibilityAccess) {
      throw StateError('unavailable');
    }
    return onlineModule as ProfileVisibilityAccess;
  }

  @override
  Future<ProfileVisibilityState> readVisibility() async {
    final epoch = _admissionEpoch;
    final binding = _binding;
    final result = await _visibilityOwner().readVisibility();
    if (!permitsEditing || binding != _binding || epoch != _admissionEpoch) {
      throw StateError('stale');
    }
    return result;
  }

  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  ) async {
    final epoch = _admissionEpoch;
    final binding = _binding;
    final result = await _visibilityOwner().saveVisibility(
      expected,
      visibility,
    );
    if (!permitsEditing || binding != _binding || epoch != _admissionEpoch) {
      throw StateError('stale');
    }
    return result;
  }

  PersonalProfileModule? _module;
  Object? _key;
  bool _usingFresh = false;
  AccountDisplayHandoff? _acceptedHandoff;

  Object? _displayMode;
  bool _confirmedFresh = false, _needsNewRead = false;
  ProfileReadObservation? _retiredRead;
  Object _modeStamp({ConnectionModeSnapshot? snapshot, Object? scope}) => (
    scope ?? snapshot?.scope ?? mode.snapshot.scope,
    snapshot?.revision ?? mode.snapshot.revision,
    snapshot?.state ?? mode.snapshot.state,
    mode.failed,
    (snapshot ?? mode.snapshot).offlineAccount?.displayName,
    (snapshot ?? mode.snapshot).offlineAccount?.cachedAtUtc,
  );
  bool _sameDisplayMode(AccountDisplayHandoff proof) {
    final mode = this.mode;
    if (!mode.failed &&
        mode.allowsOnlineTraffic &&
        (_displayMode == _modeStamp() ||
            mode.snapshot.scope == proof.generation &&
                _displayMode == _modeStamp(scope: proof.sourceGeneration))) {
      return true;
    }
    final continuity = mode is ConnectionModeDisplayContinuitySource
        ? (mode as ConnectionModeDisplayContinuitySource).displayContinuity
        : null;
    return !mode.failed &&
        mode.snapshot.state == ConnectionModeState.unavailable &&
        continuity != null &&
        continuity.sourceGeneration == proof.sourceGeneration &&
        continuity.generation == proof.generation &&
        _displayMode ==
            _modeStamp(
              snapshot: ConnectionModeSnapshot(
                scope: continuity.sourceGeneration,
                revision: continuity.revision,
                state: ConnectionModeState.online,
              ),
            );
  }

  void _retireDisplay() {
    _clearView();
    _module?.dispose();
    _module = null;
    _key = null;
    _usingFresh = false;
    _acceptedHandoff = null;
    _displayMode = null;
    _confirmedFresh = false;
    _needsNewRead = false;
    _retiredRead = null;
  }

  Future<PersonalProfileActionResult> _retry() async {
    final proof = _acceptedHandoff;
    final account = this.account?.value;
    if (_disposed ||
        proof == null ||
        !mode.allowsOnlineTraffic ||
        !_sameDisplayMode(proof) ||
        mode.failed ||
        account?.isSignedIn != true ||
        account?.hasDisplayHandoff != true ||
        account?.generation != proof.generation ||
        account?.displayHandoff?.displayKey != proof.displayKey ||
        !proof.matchesRoute(account?.displayHandoff?.route)) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    return onlineModule?.refresh() ??
        const PersonalProfileActionResult(
          PersonalProfileActionOutcome.rejected,
        );
  }

  void _sync() {
    final mode = this.mode;
    final snapshot = mode.snapshot;
    final account = this.account?.value;
    var handoff = account?.hasDisplayHandoff == true
        ? account?.displayHandoff
        : null;
    final accepted = _acceptedHandoff;
    final onlineOwner = onlineModule;
    if (handoff == null &&
        accepted != null &&
        _confirmedFresh &&
        account?.isSignedIn == true &&
        account?.generation == accepted.generation &&
        onlineOwner is ProfileReadScopeOwner &&
        (onlineOwner as ProfileReadScopeOwner).readScope?.matches(accepted) ==
            true &&
        _sameDisplayMode(accepted)) {
      handoff = accepted;
    }
    if (accepted != null &&
        (handoff == null ||
            handoff.displayKey != accepted.displayKey ||
            handoff.sourceGeneration != accepted.sourceGeneration ||
            !accepted.matchesRoute(handoff.route))) {
      _retireDisplay();
    }
    if (handoff != null &&
        _key == ('retained', handoff.sourceGeneration, handoff.displayKey) &&
        (_module?.projection.value.availability ==
                PersonalProfileAvailability.available ||
            _module is ReadonlyProfileHandoff)) {
      if (_module is! ReadonlyProfileHandoff) {
        final display = _module!.projection.value;
        _module!.dispose();
        _acceptedHandoff = handoff;
        _module = ReadonlyProfileHandoff(display, onRefresh: _retry);
      }
      final online = onlineModule;
      final observed = online is ProfileReadObservationOwner
          ? (online as ProfileReadObservationOwner).readObservation
          : null;
      final frozen = _module as ReadonlyProfileHandoff;
      if (!_sameDisplayMode(handoff)) {
        if (!_needsNewRead) {
          _confirmedFresh = false;
          _retiredRead = observed;
          _needsNewRead = true;
          frozen.withdraw('profile.error.unavailable');
        }
        _usingFresh = false;
        return;
      }
      if (_needsNewRead) {
        if (observed?.phase == ProfileReadPhase.reading &&
            !identical(observed, _retiredRead)) {
          _needsNewRead = false;
        } else {
          _usingFresh = false;
          return;
        }
      }
      final applies =
          account!.isSignedIn && observed?.generation == handoff.generation;
      final preparingCurrentOwner =
          !_confirmedFresh &&
          observed?.accountAdvance?.matches(handoff) == true;
      if (applies &&
          (observed!.phase == ProfileReadPhase.unavailable ||
              observed.phase == ProfileReadPhase.invalidated &&
                  !preparingCurrentOwner)) {
        _usingFresh = false;
        _confirmedFresh = false;
        frozen.withdraw(
          online?.projection.value.failureKey ?? 'profile.error.unavailable',
        );
        return;
      }
      final matchingOwner =
          (_confirmedFresh ||
              applies && observed!.phase == ProfileReadPhase.available) &&
          account.isSignedIn &&
          account.generation == handoff.generation &&
          online is ProfileReadScopeOwner &&
          (online as ProfileReadScopeOwner).readScope?.matches(handoff) ==
              true &&
          online?.projection.value.availability ==
              PersonalProfileAvailability.available;
      _usingFresh = mode.allowsOnlineTraffic && matchingOwner;
      if (!matchingOwner &&
          applies &&
          observed!.phase == ProfileReadPhase.available) {
        _confirmedFresh = false;
        frozen.withdraw('profile.error.invalidResponse');
        return;
      }
      if (matchingOwner) {
        _confirmedFresh = true;
        frozen.capture(online!.projection.value);
      }
      if (!_usingFresh) {
        frozen.observe(
          waiting:
              !applies || observed!.phase != ProfileReadPhase.transientFailure,
          failureKey: online?.projection.value.failureKey,
        );
      }
      return;
    }
    _usingFresh = false;
    final readId =
        !mode.failed &&
            mode.allowsOnlineTraffic &&
            account?.hasRetainedDisplayRead == true &&
            createRetainedPort != null
        ? account?.retainedReadId
        : null;
    final key =
        !mode.failed && snapshot.isOffline && snapshot.offlineAccount != null
        ? (
            snapshot.scope,
            snapshot.revision,
            snapshot.offlineAccount!.cachedAtUtc,
          )
        : readId == null
        ? null
        : ('retained', account!.generation, readId);
    if (_key == key) return;
    _retireDisplay();
    _key = key;
    _displayMode = readId == null ? null : _modeStamp();
    if (key != null) {
      _module = createPersonalProfileModule(
        readId != null ? createRetainedPort!(readId) : createPort(),
      );
      unawaited(_module!.initialize());
    }
  }
}
