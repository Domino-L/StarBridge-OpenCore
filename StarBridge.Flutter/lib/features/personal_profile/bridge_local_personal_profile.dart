import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../hangar/local_hangar_port.dart';
import 'personal_profile_auto_import.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_edit_groups.dart';
import 'personal_profile_owner_lock.dart';
import 'personal_profile_port.dart';
import 'bridge_personal_profile_account_facts.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_visibility.dart';
import 'profile_read_failure.dart';
import 'profile_read_scope.dart';
import 'bridge_local_personal_profile_rebase.dart';
import 'bridge_local_personal_profile_save.dart';
import 'bridge_local_personal_profile_visibility.dart';

/// Local presentation writer. Legacy background publication is a separate,
/// narrow bridge contract; the whole-profile remote port remains read-only.
final class BridgeLocalPersonalProfile
    implements
        PersonalProfilePort,
        PersonalProfileAccountFactsReader,
        ProfileVisibilityAccess,
        PersonalProfileContentChanges,
        PersonalProfileDisplayReader,
        ProfileReadScopeOwner,
        ProfileReadGenerationOwner,
        ProfileReadAccountAdvanceOwner {
  BridgeLocalPersonalProfile(
    this._session, {
    required PersonalProfilePort remote,
    required LocalHangarPort Function() hangar,
    // Public constructor names describe the injected ports.
    // ignore: prefer_initializing_formals
  }) : _remote = remote,
       // ignore: prefer_initializing_formals
       _hangar = hangar {
    _invalidationGeneration = _session.activeGeneration;
    _saves = _ownerLocks.saves.listen((event) {
      final (owner, source) = event;
      if (!identical(source, this) &&
          owner.generation == activeReadGeneration &&
          _ownerLocks.isCurrent(owner)) {
        _contentChanged();
      }
    });
    _events = _session.events.listen((event) {
      if (const {
        'account.changed',
        'bootstrap.invalidated',
      }.contains(event.name)) {
        _readAccountAdvance = ProfileReadAccountAdvance.observe(
          event,
          _invalidationGeneration,
          _session.activeGeneration,
        );
        _invalidationGeneration = _session.activeGeneration;
        _epoch++;
        _readScope = null;
        _displayUpdate = null;
        _visibilityLease = null;
        _lease = null;
        _invalidations.add(null);
      } else if (const {
        'account.avatarChanged',
        'personalProfile.changed',
        'hangarReader.changed',
      }.contains(event.name)) {
        _contentChanged();
      }
    });
  }
  final BridgeClientSession _session;
  late final _ownerLocks = PersonalProfileOwnerLocks.of(_session);
  @override
  Future<PersonalProfilePublicFacts?> readAccountFacts() =>
      _closed ? Future.value(null) : readProfileAccountFacts(_session);
  @override
  int get activeReadGeneration => _session.activeGeneration;
  late int _invalidationGeneration;
  ProfileReadAccountAdvance? _readAccountAdvance;
  @override
  ProfileReadAccountAdvance? get readAccountAdvance => _readAccountAdvance;
  ProfileReadScope? _readScope;
  @override
  ProfileReadScope? get readScope => _readScope;
  final PersonalProfilePort _remote;
  final LocalHangarPort Function() _hangar;
  final _invalidations = StreamController<void>.broadcast();
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _events;
  _LocalLease? _lease;
  _LocalLease? _savingLease;
  bool _readDuringSave = false;
  late final StreamSubscription<(PersonalProfileOwnerLock, Object)> _saves;
  ({
    int epoch,
    int generation,
    Future<PersonalProfileSnapshot> result,
    Future<PersonalProfileSnapshot>? initial,
  })?
  _reading;
  ({int epoch, int generation, PersonalProfileSnapshot snapshot})?
  _displayUpdate;
  int _contentVersion = 0;
  // Observed capability for this owner, not an inferred historical origin.
  BridgeAccountContext? _versionedPageOwner;
  int _epoch = 0;
  bool _closed = false;
  ({ProfileVisibilityState state, int epoch})? _visibilityLease;
  static const _timeout = Duration(seconds: 60);

  @override
  Future<ProfileVisibilityState> readVisibility() => _visibility();
  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  ) => _visibility(expected, visibility);

  Future<ProfileVisibilityState> _visibility([
    ProfileVisibilityState? expected,
    PersonalProfileVisibility? visibility,
  ]) async {
    final lease = _lease;
    if (lease == null || !_current(lease.epoch, lease.generation)) {
      throw StateError('stale');
    }
    if (expected != null &&
        (!identical(_visibilityLease?.state, expected) ||
            _visibilityLease?.epoch != _epoch)) {
      throw StateError('stale');
    }
    if (expected != null &&
        !expected.availableVisibilities.contains(visibility)) {
      throw StateError('unsupported visibility');
    }
    _visibilityLease = null;
    final response = await requestLocalProfileVisibility(
      _session,
      lease.owner,
      _timeout,
      expected,
      visibility,
    );
    _validate(response, lease.owner);
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final state = parseLocalProfileVisibility(response.payload, visibility);
    _visibilityLease = (state: state, epoch: _epoch);
    return state;
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  Stream<void> get changes => _changes.stream;

  /// The Host may reject a local read with `profile_local.account_changed`
  /// for a few milliseconds while its local owner catches up with an account
  /// confirmation that the client already observed (device traces 2026-10-20:
  /// 3/20 cold starts left the profile page unavailable for the session).
  /// Retry only while this adapter's epoch and generation are unchanged.
  static const ownerPendingRetryDelays = [
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];
  bool _ownerPending = false;

  @override
  Future<PersonalProfileSnapshot> read() => _read(false);

  @override
  Future<PersonalProfileSnapshot> readForDisplay() => _read(true);

  void _contentChanged() {
    if (_closed) return;
    _contentVersion++;
    _displayUpdate = null;
    _changes.add(null);
  }

  Future<PersonalProfileSnapshot> _read(bool progressive) async {
    if (_closed) return _staleSnapshot;
    final saving = _savingLease;
    if (saving != null &&
        _current(saving.epoch, saving.generation) &&
        _ownerLocks.isCurrent(saving.ownerLock)) {
      _readDuringSave = true;
      return saving.displayed;
    }
    final reading = _reading;
    if (reading != null && _current(reading.epoch, reading.generation)) {
      return progressive ? reading.initial ?? reading.result : reading.result;
    }
    final update = _displayUpdate;
    _displayUpdate = null;
    if (progressive &&
        update != null &&
        _current(update.epoch, update.generation)) {
      return update.snapshot;
    }
    final epoch = _epoch, generation = activeReadGeneration;
    final contentVersion = _contentVersion;
    final initial = progressive ? Completer<PersonalProfileSnapshot>() : null;
    final result = _readWithOwnerRetry(initial?.complete);
    _reading = (
      epoch: epoch,
      generation: generation,
      result: result,
      initial: initial?.future,
    );
    final settled = result.then((snapshot) {
      if (identical(_reading?.result, result)) _reading = null;
      if (initial != null) {
        if (!initial.isCompleted) {
          initial.complete(snapshot);
        } else if (_current(epoch, generation)) {
          // Publish the settled read once without starting another import.
          if (_contentVersion == contentVersion) {
            _displayUpdate = (
              epoch: epoch,
              generation: generation,
              snapshot: snapshot,
            );
          }
          _changes.add(null);
        }
      }
      return snapshot;
    });
    return initial?.future ?? settled;
  }

  Future<PersonalProfileSnapshot> _readWithOwnerRetry(
    void Function(PersonalProfileSnapshot)? onPending,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final epoch = _epoch;
      final generation = _session.activeGeneration;
      _ownerPending = false;
      final snapshot = await _readOnce(onPending);
      if (!_ownerPending ||
          attempt >= ownerPendingRetryDelays.length ||
          !_current(epoch, generation)) {
        return snapshot;
      }
      await Future<void>.delayed(ownerPendingRetryDelays[attempt]);
      if (!_current(epoch, generation)) return snapshot;
    }
  }

  Future<PersonalProfileSnapshot> _readOnce(
    void Function(PersonalProfileSnapshot)? onPending,
  ) async {
    _readScope = null;
    _lease = null;
    _visibilityLease = null;
    final epoch = _epoch;
    final generation = _session.activeGeneration;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _timeout,
      );
      if (account.payload['schemaVersion'] is! int ||
          account.payload['schemaVersion'] != 1) {
        throw const FormatException();
      }
      if (!_current(epoch, account.sessionGeneration)) return _staleSnapshot;
      if (account.payload['state'] == 'signedOut' ||
          account.payload['state'] == 'reauthorizationRequired') {
        return const PersonalProfileSnapshot.signedOut();
      }
      if (!hasRelayAccount(account) || account.accountContext == null) {
        return const PersonalProfileSnapshot.unavailable();
      }
      final owner = _ownerLocks.forOwner(
        account.accountContext!,
        account.sessionGeneration,
      );
      final readStamp = owner.importStamp;
      // Observe errors on each future immediately; one failing source cannot
      // leave another asynchronous error unhandled.
      final results = await Future.wait<Object?>([
        _session.request(
          'personalProfile.localRead',
          accountContext: account.accountContext,
          payload: const {'schemaVersion': 1},
          timeout: _timeout,
        ),
        // The Host selects the existing S2 Relay read for an old account;
        // SCM accounts retain their existing SCM owner. Neither is a fallback.
        _readRemote(),
        _readHangar(),
      ], eagerError: true);
      if (!_current(epoch, account.sessionGeneration)) return _staleSnapshot;
      final response = results[0] as BridgeEnvelope;
      _validate(response, account.accountContext!);
      final local = parseLocalProfileRevision(response.payload);
      final (:revision, :content) = local;
      final remote = results[1] as PersonalProfileSnapshot;
      final scope = ProfileReadScope.fromLocalResponse(
        account,
        response,
        _session.activeGeneration,
      );
      bool sameRemoteOwner() =>
          _remote is! ProfileReadScopeOwner ||
          scope.sameOwner((_remote as ProfileReadScopeOwner).readScope);
      if (remote.availability == PersonalProfileAvailability.available &&
          !sameRemoteOwner()) {
        throw const FormatException(
          'Profile sources belong to different owners.',
        );
      }
      if (account.payload['state'] == 'signedIn' &&
          remote.presentation != null) {
        _versionedPageOwner = account.accountContext;
      }
      if (remote.availability == PersonalProfileAvailability.signedOut) {
        return remote;
      }
      if (remote.availability != PersonalProfileAvailability.available) {
        return const PersonalProfileSnapshot.unavailable(
          failureKey: 'profile.error.ownerReadFailed',
        );
      }
      PersonalProfileSnapshot project(
        PersonalProfileSnapshot source,
        Set<String> preferLocal,
        bool pending,
      ) => projectLocalProfile(
        source,
        content,
        results[2] as LocalHangarSnapshot?,
        DateTime.tryParse(response.payload['savedAt'] as String? ?? ''),
        draftDisplayName:
            (account.payload['displayName'] as String?)?.trim() ?? '',
        accountAvatarImageData: account.payload['avatarImageData'] as String?,
        legacyAccount: account.payload['state'] == 'legacySignedIn',
        accountCallSign: account.payload['state'] == 'signedIn',
        preferLocalGroups: preferLocal,
        autoImportPending: pending,
        timeZones: {
          for (final zone
              in (response.payload['timeZones'] as List? ?? const [])
                  .cast<Map>())
            zone['id'] as String: zone['label'] as String,
        },
      );
      final writer = _remote;
      bool current() =>
          _current(epoch, account.sessionGeneration) &&
          _ownerLocks.isCurrent(owner);
      final snapshot =
          account.payload['state'] == 'signedIn' &&
              revision > 0 &&
              content != null &&
              remote.presentation != null
          ? await autoImportPersonalProfile(
              remote: remote,
              content: content,
              owner: owner,
              readStamp: readStamp,
              writer: writer is PersonalProfilePresentationWriter
                  ? writer as PersonalProfilePresentationWriter
                  : null,
              project: project,
              current: current,
              sameOwner: () =>
                  activeReadGeneration == owner.generation &&
                  _ownerLocks.isCurrent(owner),
              onPending: onPending,
              onCommitted: () => _ownerLocks.notifySave(owner, this),
              refresh: () async {
                final latest = await _readRemote();
                if (!current() ||
                    !sameRemoteOwner() ||
                    latest.availability !=
                        PersonalProfileAvailability.available ||
                    latest.presentation == null) {
                  return null;
                }
                return latest;
              },
            )
          : project(remote, const {}, false);
      if (!current()) return _staleSnapshot;
      if (snapshot.allowEditing) {
        _lease = _LocalLease(
          owner,
          epoch,
          LocalProfileSaveBaseline(local),
          snapshot.callSign,
          account.payload['state'] == 'signedIn'
              ? snapshot.callSign
              : remote.callSign,
          snapshot,
        );
      }
      _readScope =
          snapshot.availability == PersonalProfileAvailability.available
          ? scope
          : null;
      return snapshot;
    } on Object catch (error) {
      _ownerPending =
          error is BridgeClientException &&
          error.code == 'profile_local.account_changed' &&
          _current(epoch, generation);
      return PersonalProfileSnapshot.unavailable(
        failureKey: localProfileFailureKey(error),
        transientReadFailure:
            _current(epoch, generation) && profileReadIsTransient(error),
      );
    }
  }

  Future<PersonalProfileSnapshot> _readRemote() async {
    try {
      return await _remote.read();
    } on Object {
      // The owner read keeps this failure distinct from a valid remote default.
      // No edit lease may be issued from a failed remote observation.
      return const PersonalProfileSnapshot.unavailable();
    }
  }

  Future<LocalHangarSnapshot?> _readHangar() async {
    try {
      return await _hangar().read();
    } on Object {
      return null;
    }
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    if (!ProfileFavoriteModules.valid(edit.moduleLayout)) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
        failureKey: 'profile.favorites.resize',
      );
    }
    final lease = _lease;
    if (lease == null ||
        !_current(lease.epoch, lease.generation) ||
        !_ownerLocks.isCurrent(lease.ownerLock) ||
        identical(lease, _savingLease)) {
      return _stale;
    }
    bool currentLease() =>
        identical(_lease, lease) &&
        _current(lease.epoch, lease.generation) &&
        _ownerLocks.isCurrent(lease.ownerLock);
    _savingLease = lease;
    _readDuringSave = false;
    final operation = lease.ownerLock.beginSave();
    var callSignConfirmed = false;
    var callSignAttempted = false;
    final baseline = lease.versionedEdit;
    var pageConfirmed = baseline?.hasConfirmedGroups == true;
    var keepLease = false;
    try {
      if (operation.previous case final previous?) await previous;
      if (!currentLease()) return _stale;
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _timeout,
      );
      if (!hasRelayAccount(account) ||
          !_same(account.accountContext, lease.owner) ||
          !currentLease()) {
        return _stale;
      }
      final syncBackground = account.payload['state'] == 'legacySignedIn';
      final rename =
          !syncBackground &&
          edit.callSign.trim() != (lease.confirmedCallSign ?? lease.callSign);
      // Reject a known unavailable step before committing any page fields.
      // This is capability preflight, not a substitute for Host authorization.
      if (rename &&
          (lease.remoteCallSign == null ||
              !_session.hostCapabilities.contains('account.callSign'))) {
        return const PersonalProfileActionResult(
          PersonalProfileActionOutcome.failed,
          failureKey: 'profile.callsign.unavailable',
        );
      }
      final presentation = lease.displayed.presentation;
      if (!syncBackground &&
          presentation == null &&
          (_same(_versionedPageOwner, lease.owner) ||
              (_session.hostCapabilities.contains(
                    'personalProfile.presentation.write.v1',
                  ) &&
                  lease.displayed.local?.remoteAvailable != true))) {
        // A failed/missing versioned read cannot silently change the writer to
        // local storage. Keep cached viewing, but require a fresh server lease.
        _lease = null;
        return _stale;
      }
      final groups = personalProfileEditGroups(lease.displayed, edit);
      final remoteGroups = baseline?.pendingGroups(edit, groups) ?? groups;
      if (!syncBackground && baseline != null && remoteGroups.isNotEmpty) {
        final writer = _remote;
        if (writer is! PersonalProfilePresentationWriter) return _stale;
        final result = await baseline.save(
          owner: lease.ownerLock,
          writer: writer as PersonalProfilePresentationWriter,
          readLatest: _readRemote,
          current: currentLease,
          sameOwner: () =>
              writer is! ProfileReadScopeOwner ||
              _readScope?.sameOwner(
                    (writer as ProfileReadScopeOwner).readScope,
                  ) ==
                  true,
          groups: remoteGroups,
        );
        if (result.outcome != PersonalProfileActionOutcome.completed) {
          if (result.requiresReload && identical(_lease, lease)) _lease = null;
          keepLease = !result.requiresReload;
          return result;
        }
        pageConfirmed = true;
      }
      if (rename) {
        callSignAttempted = true;
        final confirmed = await _session.request(
          'account.updateCallSign',
          accountContext: lease.owner,
          timeout: _timeout,
          payload: {
            'schemaVersion': 1,
            'expectedCallSign': lease.confirmedCallSign ?? lease.remoteCallSign,
            'callSign': edit.callSign.trim(),
          },
        );
        _validate(confirmed, lease.owner);
        if (!currentLease()) return _stale;
        if (confirmed.payload['callSign'] != edit.callSign.trim()) {
          throw const FormatException();
        }
        callSignConfirmed = true;
        lease.confirmedCallSign = edit.callSign.trim();
      }
      ({int revision, String wallpaper})? background;
      if (syncBackground) {
        try {
          background = await _backgroundRequest(lease);
        } on Object {
          // Online failure must not prevent the explicitly requested local save.
        }
        if (!currentLease()) return _stale;
      }
      final localResult = await lease.localEdit.save(
        displayed: lease.displayed,
        edit: edit,
        groups: groups,
        legacyRelay: syncBackground,
        current: currentLease,
        request: (name, payload) async {
          final response = await _session.request(
            name,
            accountContext: lease.owner,
            timeout: _timeout,
            payload: {'schemaVersion': 1, ...payload},
          );
          _validate(response, lease.owner);
          return response.payload;
        },
      );
      if (localResult != null) {
        keepLease = !localResult.requiresReload;
        return localResult;
      }
      if (!currentLease()) return _stale;
      _lease = null;
      if (syncBackground) {
        if (background == null) return _backgroundPending;
        try {
          if (background.wallpaper != edit.wallpaperId) {
            // A lost write response may still have advanced the server revision.
            _visibilityLease = null;
            await _backgroundRequest(
              lease,
              revision: background.revision,
              wallpaper: edit.wallpaperId,
            );
          }
        } on Object {
          if (!_current(lease.epoch, lease.generation)) return _stale;
          return _backgroundPending;
        }
        if (!_current(lease.epoch, lease.generation)) return _stale;
      }
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
        messageKey: !syncBackground && presentation == null
            ? 'profile.local.onlySaved'
            : null,
      );
    } on Object catch (error) {
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.failed,
        requiresReload: pageConfirmed || callSignAttempted,
        failureKey: pageConfirmed
            ? 'profile.error.refreshBeforeSave'
            : callSignConfirmed
            ? 'profile.callsign.localPending'
            : callSignAttempted &&
                  (error is BridgeTimeoutException ||
                      error is BridgeDisconnectedException ||
                      error is BridgeRemoteException &&
                          error.code == 'bridge.disconnected')
            ? 'profile.callsign.unconfirmed'
            : localProfileFailureKey(error),
      );
    } finally {
      operation.finish();
      _ownerLocks.notifySave(lease.ownerLock, this);
      // A rename may have committed even when its response or the later local
      // save failed. A fresh read, not another send from this edit lease, must
      // establish the next expected account presentation.
      if (!keepLease &&
          (pageConfirmed || callSignAttempted) &&
          identical(_lease, lease)) {
        _lease = null;
      }
      if (identical(_savingLease, lease)) {
        _savingLease = null;
        if (_readDuringSave && _current(lease.epoch, lease.generation)) {
          _contentChanged();
        }
        _readDuringSave = false;
      }
    }
  }

  Future<({int revision, String wallpaper})> _backgroundRequest(
    _LocalLease lease, {
    int? revision,
    String? wallpaper,
  }) async {
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final response = await _session.request(
      revision == null
          ? 'personalProfile.readBackground'
          : 'personalProfile.saveBackground',
      accountContext: lease.owner,
      timeout: _timeout,
      payload: {
        'schemaVersion': 1,
        'expectedRevision': ?revision,
        'wallpaperId': ?wallpaper,
      },
    );
    _validate(response, lease.owner);
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final receivedRevision = response.payload['revision'];
    final receivedWallpaper = response.payload['wallpaperId'];
    if (receivedRevision is! int ||
        receivedRevision < 0 ||
        receivedWallpaper is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{1,100}$').hasMatch(receivedWallpaper) ||
        revision != null &&
            (receivedRevision != revision + 1 ||
                receivedWallpaper != wallpaper)) {
      throw const FormatException();
    }
    return (revision: receivedRevision, wallpaper: receivedWallpaper);
  }

  static const _backgroundPending = PersonalProfileActionResult(
    PersonalProfileActionOutcome.failed,
    failureKey: 'profile.local.backgroundPending',
  );

  bool _current(int epoch, int generation) =>
      !_closed && _epoch == epoch && _session.activeGeneration == generation;
  static bool _same(BridgeAccountContext? a, BridgeAccountContext b) =>
      a?.environment == b.environment &&
      a?.authority == b.authority &&
      a?.subject == b.subject;
  static void _validate(BridgeEnvelope response, BridgeAccountContext owner) {
    if (!_same(response.accountContext, owner) ||
        response.payload['schemaVersion'] is! int ||
        response.payload['schemaVersion'] != 1) {
      throw const FormatException();
    }
  }

  static const _stale = staleProfileEdit;
  static const _staleSnapshot = PersonalProfileSnapshot.unavailable(
    failureKey: 'profile.error.refreshBeforeSave',
  );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    _lease = null;
    await Future.wait([_events.cancel(), _saves.cancel(), _remote.close()]);
    await _invalidations.close();
    await _changes.close();
  }
}

final class _LocalLease {
  _LocalLease(
    this.ownerLock,
    this.epoch,
    this.localEdit,
    this.callSign,
    this.remoteCallSign,
    this.displayed,
  );
  final PersonalProfileOwnerLock ownerLock;
  BridgeAccountContext get owner => ownerLock.owner;
  int get generation => ownerLock.generation;
  final int epoch;
  final LocalProfileSaveBaseline localEdit;
  final String callSign;
  final String? remoteCallSign;
  String? confirmedCallSign;
  final PersonalProfileSnapshot displayed;
  late final versionedEdit = displayed.presentation == null
      ? null
      : VersionedProfileEditBaseline(displayed.presentation!);
}
