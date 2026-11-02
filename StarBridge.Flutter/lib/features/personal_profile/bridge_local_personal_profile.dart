import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../hangar/local_hangar_port.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_edit_groups.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_port.dart';
import 'personal_profile_visibility.dart';
import 'profile_read_failure.dart';
import 'profile_read_scope.dart';

/// Local presentation writer. Legacy background publication is a separate,
/// narrow bridge contract; the whole-profile remote port remains read-only.
final class BridgeLocalPersonalProfile
    implements
        PersonalProfilePort,
        ProfileVisibilityAccess,
        PersonalProfileContentChanges,
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
        _visibilityLease = null;
        _lease = null;
        _pending = null;
        _invalidations.add(null);
      } else if (const {
        'account.avatarChanged',
        'personalProfile.changed',
        'hangarReader.changed',
      }.contains(event.name)) {
        _changes.add(null);
      }
    });
  }
  final BridgeClientSession _session;
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
  // Observed capability for this owner, not an inferred historical origin.
  BridgeAccountContext? _versionedPageOwner;
  ({String content, String operation})? _pending;
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
    final response = await _session.request(
      expected == null
          ? 'personalProfile.readVisibility'
          : 'personalProfile.saveVisibility',
      accountContext: lease.owner,
      timeout: _timeout,
      payload: {
        'schemaVersion': 1,
        if (expected != null) 'expectedRevision': expected.revision,
        if (visibility != null) 'visibility': visibility.bridgeValue,
      },
    );
    _validate(response, lease.owner);
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final revision = response.payload['revision'];
    final scope = response.payload['visibility'];
    final rawChoices = response.payload['availableVisibilities'];
    final List<PersonalProfileVisibility> choices;
    if (rawChoices == null) {
      choices = ProfileVisibilityState.legacyVisibilities;
    } else {
      if (rawChoices is! List ||
          rawChoices.isEmpty ||
          rawChoices.length > 5 ||
          rawChoices.toSet().length != rawChoices.length ||
          rawChoices.any(
            (v) => !PersonalProfileVisibility.values.any(
              (known) => known.bridgeValue == v,
            ),
          )) {
        throw const FormatException();
      }
      choices = List.unmodifiable(
        rawChoices.map(
          (v) => PersonalProfileVisibility.fromBridgeValue(v as String),
        ),
      );
    }
    if (revision is! int ||
        revision < 0 ||
        !const {
          'public',
          'friendsAndMainFleet',
          'friendsFleetAndOrganizations',
          'friendsOnly',
          'private',
        }.contains(scope) ||
        !choices.any((v) => v.bridgeValue == scope) ||
        visibility != null && scope != visibility.bridgeValue) {
      throw const FormatException();
    }
    final state = ProfileVisibilityState(
      revision,
      PersonalProfileVisibility.fromBridgeValue(scope as String),
      availableVisibilities: choices,
    );
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
  Future<PersonalProfileSnapshot> read() async {
    for (var attempt = 0; ; attempt++) {
      final epoch = _epoch;
      final generation = _session.activeGeneration;
      _ownerPending = false;
      final snapshot = await _readOnce();
      if (!_ownerPending ||
          attempt >= ownerPendingRetryDelays.length ||
          !_current(epoch, generation)) {
        return snapshot;
      }
      await Future<void>.delayed(ownerPendingRetryDelays[attempt]);
      if (!_current(epoch, generation)) return snapshot;
    }
  }

  Future<PersonalProfileSnapshot> _readOnce() async {
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
      final revision = response.payload['revision'] as int;
      if (revision < 0) throw const FormatException();
      final content = (response.payload['content'] as Map?)
          ?.cast<String, Object?>();
      if ((revision == 0) != (content == null)) throw const FormatException();
      final remote = results[1] as PersonalProfileSnapshot;
      final scope = ProfileReadScope.fromLocalResponse(
        account,
        response,
        _session.activeGeneration,
      );
      if (remote.availability == PersonalProfileAvailability.available &&
          _remote is ProfileReadScopeOwner &&
          !scope.sameOwner((_remote as ProfileReadScopeOwner).readScope)) {
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
      final snapshot = projectLocalProfile(
        remote,
        content,
        results[2] as LocalHangarSnapshot?,
        DateTime.tryParse(response.payload['savedAt'] as String? ?? ''),
        draftDisplayName:
            (account.payload['displayName'] as String?)?.trim() ?? '',
        accountAvatarImageData: account.payload['avatarImageData'] as String?,
        legacyAccount: account.payload['state'] == 'legacySignedIn',
        accountCallSign: account.payload['state'] == 'signedIn',
        timeZones: {
          for (final zone
              in (response.payload['timeZones'] as List? ?? const [])
                  .cast<Map>())
            zone['id'] as String: zone['label'] as String,
        },
      );
      // A successful read establishes the next edit revision, including a
      // save whose response was lost. Do not reuse that completed operation.
      _pending = null;
      if (snapshot.allowEditing) {
        _lease = _LocalLease(
          account.accountContext!,
          account.sessionGeneration,
          epoch,
          revision,
          snapshot.local!.favoriteShipIds,
          content,
          snapshot.callSign,
          remote.availability == PersonalProfileAvailability.available
              ? remote.callSign
              : null,
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
        failureKey: _failure(error),
        transientReadFailure:
            _current(epoch, generation) && profileReadIsTransient(error),
      );
    }
  }

  Future<PersonalProfileSnapshot> _readRemote() async {
    try {
      return await _remote.read();
    } on Object {
      // Optional online details cannot turn a successful local read into an
      // empty-file claim or prevent an explicitly requested local save.
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
    if (lease == null || !_current(lease.epoch, lease.generation)) {
      return _stale;
    }
    var callSignConfirmed = false;
    var callSignAttempted = false;
    var pageConfirmed = false;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _timeout,
      );
      if (!hasRelayAccount(account) ||
          !_same(account.accountContext, lease.owner) ||
          !identical(_lease, lease) ||
          !_current(lease.epoch, lease.generation)) {
        return _stale;
      }
      final syncBackground = account.payload['state'] == 'legacySignedIn';
      final rename = !syncBackground && edit.callSign.trim() != lease.callSign;
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
      if (!syncBackground && presentation != null) {
        final groups = personalProfileEditGroups(lease.displayed, edit);
        if (groups.isNotEmpty) {
          final writer = _remote;
          if (writer is! PersonalProfilePresentationWriter) return _stale;
          final result = await (writer as PersonalProfilePresentationWriter)
              .savePresentation(presentation, groups);
          if (result.outcome != PersonalProfileActionOutcome.completed) {
            _lease = null;
            return result;
          }
          pageConfirmed = true;
          if (!identical(_lease, lease) ||
              !_current(lease.epoch, lease.generation)) {
            return _stale;
          }
        }
      }
      if (rename) {
        callSignAttempted = true;
        final confirmed = await _session.request(
          'account.updateCallSign',
          accountContext: lease.owner,
          timeout: _timeout,
          payload: {
            'schemaVersion': 1,
            'expectedCallSign': lease.remoteCallSign,
            'callSign': edit.callSign.trim(),
          },
        );
        _validate(confirmed, lease.owner);
        if (!identical(_lease, lease) ||
            !_current(lease.epoch, lease.generation)) {
          return _stale;
        }
        if (confirmed.payload['callSign'] != edit.callSign.trim()) {
          throw const FormatException();
        }
        callSignConfirmed = true;
      }
      ({int revision, String wallpaper})? background;
      if (syncBackground) {
        try {
          background = await _backgroundRequest(lease);
        } on Object {
          // Online failure must not prevent the explicitly requested local save.
        }
        if (!identical(_lease, lease) ||
            !_current(lease.epoch, lease.generation)) {
          return _stale;
        }
      }
      final content = <String, Object?>{
        'callSign': edit.callSign.trim(),
        'introduction': edit.about.trim(),
        'avatarStyle': edit.avatarStyle,
        'wallpaperId': edit.wallpaperId,
        'preserveEmptyFields': true,
        'favoriteShipIds':
            edit.favoriteShipIds ??
            ProfileFavoriteModules.selections(edit.moduleLayout) ??
            lease.favorites,
        if (edit.playStyle != null || lease.content?['playStyle'] != null)
          'playStyle': {
            ...?(lease.content?['playStyle'] as Map?)?.cast<String, Object?>(),
            ...?edit.playStyle?.toJson(),
          },
        if (edit.schedule != null || lease.content?['schedule'] != null)
          'schedule': edit.schedule?.toJson() ?? lease.content?['schedule'],
        'modules': [
          for (final item in edit.moduleLayout)
            {
              'id': item.moduleId,
              'span': item.size.span,
              'isVisible': item.isVisible,
              'position': item.position,
              if (item.favoriteShipIds != null && edit.favoriteShipIds == null)
                'favoriteShipIds': item.favoriteShipIds,
            },
        ],
      };
      final encoded = jsonEncode(content);
      if (_pending?.content != encoded) {
        final random = Random.secure();
        _pending = (
          content: encoded,
          operation: List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
        );
      }
      final response = await _session.request(
        'personalProfile.localSave',
        accountContext: lease.owner,
        timeout: _timeout,
        payload: {
          'schemaVersion': 1,
          'expectedRevision': lease.revision,
          'operationId': _pending!.operation,
          'content': content,
        },
      );
      _validate(response, lease.owner);
      if (!identical(_lease, lease) ||
          !_current(lease.epoch, lease.generation)) {
        return _stale;
      }
      if (response.payload['operationId'] != _pending!.operation ||
          response.payload['revision'] != lease.revision + 1) {
        throw const FormatException();
      }
      _lease = null;
      _pending = null;
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
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
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
            : _failure(error),
      );
    } finally {
      // A rename may have committed even when its response or the later local
      // save failed. A fresh read, not another send from this edit lease, must
      // establish the next expected account presentation.
      if (pageConfirmed || callSignAttempted) _lease = null;
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

  static String _failure(Object error) => switch (error) {
    BridgeRemoteException(code: 'account.callsign_conflict') =>
      'profile.error.refreshBeforeSave',
    BridgeRemoteException(code: 'account.callsign_invalid') =>
      'profile.collab.invalid',
    BridgeRemoteException(code: 'account.callsign_unconfirmed') =>
      'profile.callsign.unconfirmed',
    BridgeRemoteException(code: 'account.callsign_unavailable') =>
      'profile.callsign.unavailable',
    BridgeRemoteException(code: 'personal_profile.write_forbidden') =>
      'profile.callsign.forbidden',
    BridgeCancelledException() => 'profile.callsign.cancelled',
    BridgeRemoteException(code: 'profile_local.conflict') =>
      'profile.error.refreshBeforeSave',
    BridgeRemoteException(code: 'profile_local.account_changed') ||
    BridgeStaleGenerationException() => 'profile.error.refreshBeforeSave',
    BridgeRemoteException(code: 'profile_local.hangar_changed') =>
      'profile.local.hangarChanged',
    BridgeRemoteException(code: 'profile_local.read_failed') =>
      'profile.local.readFailed',
    BridgeRemoteException(code: 'profile_local.invalid_request') =>
      'profile.collab.invalid',
    _ => 'profile.local.failed',
  };
  static const _stale = PersonalProfileActionResult(
    PersonalProfileActionOutcome.rejected,
    requiresReload: true,
    failureKey: 'profile.error.refreshBeforeSave',
  );
  static const _staleSnapshot = PersonalProfileSnapshot.unavailable(
    failureKey: 'profile.error.refreshBeforeSave',
  );

  @override
  Future<void> close() async {
    _closed = true;
    _epoch++;
    _lease = null;
    _pending = null;
    await _events.cancel();
    await _remote.close();
    await _invalidations.close();
    await _changes.close();
  }
}

final class _LocalLease {
  const _LocalLease(
    this.owner,
    this.generation,
    this.epoch,
    this.revision,
    this.favorites,
    this.content,
    this.callSign,
    this.remoteCallSign,
    this.displayed,
  );
  final BridgeAccountContext owner;
  final int generation, epoch, revision;
  final List<String>? favorites;
  final Map<String, Object?>? content;
  final String callSign;
  final String? remoteCallSign;
  final PersonalProfileSnapshot displayed;
}
