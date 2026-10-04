import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../hangar/local_hangar_port.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_port.dart';
import 'personal_profile_visibility.dart';

/// Local presentation writer. Legacy background publication is a separate,
/// narrow bridge contract; the whole-profile remote port remains read-only.
final class BridgeLocalPersonalProfile implements PersonalProfilePort, ProfileVisibilityAccess {
  BridgeLocalPersonalProfile(
    this._session, {
    required PersonalProfilePort remote,
    required LocalHangarPort Function() hangar,
    // Public constructor names describe the injected ports.
    // ignore: prefer_initializing_formals
  }) : _remote = remote,
       // ignore: prefer_initializing_formals
       _hangar = hangar {
    _events = _session.events.listen((event) {
      if (const {
        'account.changed',
        'bootstrap.invalidated',
        'personalProfile.changed',
        'hangarReader.changed',
      }.contains(event.name)) {
        _epoch++;
        _visibilityLease = null;
        _lease = null;
        _pending = null;
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession _session;
  final PersonalProfilePort _remote;
  final LocalHangarPort Function() _hangar;
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _events;
  _LocalLease? _lease;
  ({String content, String operation})? _pending;
  int _epoch = 0;
  bool _closed = false;
  ({ProfileVisibilityState state, int epoch})? _visibilityLease;
  static const _timeout = Duration(seconds: 60);

  @override
  Future<ProfileVisibilityState> readVisibility() => _visibility();
  @override
  Future<ProfileVisibilityState> saveVisibility(ProfileVisibilityState expected,
      PersonalProfileVisibility visibility) => _visibility(expected, visibility);

  Future<ProfileVisibilityState> _visibility([ProfileVisibilityState? expected,
      PersonalProfileVisibility? visibility]) async {
    final lease = _lease;
    if (lease == null || !_current(lease.epoch, lease.generation)) throw StateError('stale');
    if (expected != null && (!identical(_visibilityLease?.state, expected) ||
        _visibilityLease?.epoch != _epoch)) { throw StateError('stale'); }
    _visibilityLease = null;
    final response = await _session.request(
      expected == null ? 'personalProfile.readVisibility' : 'personalProfile.saveVisibility',
      accountContext: lease.owner,
      timeout: _timeout,
      payload: {'schemaVersion': 1,
        if (expected != null) 'expectedRevision': expected.revision,
        if (visibility != null) 'visibility': visibility.bridgeValue},
    );
    _validate(response, lease.owner);
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final revision = response.payload['revision'];
    final scope = response.payload['visibility'];
    if (revision is! int || revision < 0 || !const {
      'public', 'friendsFleetAndOrganizations', 'friendsOnly', 'private'
    }.contains(scope) || visibility != null && scope != visibility.bridgeValue) {
      throw const FormatException();
    }
    final state = ProfileVisibilityState(revision,
      PersonalProfileVisibility.fromBridgeValue(scope as String));
    _visibilityLease = (state: state, epoch: _epoch);
    return state;
  }

  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  Future<PersonalProfileSnapshot> read() async {
    _lease = null;
    final epoch = _epoch;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _timeout,
      );
      if (account.payload['schemaVersion'] != 1) {
        throw const FormatException();
      }
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
        );
      }
      return snapshot;
    } on Object catch (error) {
      return PersonalProfileSnapshot.unavailable(failureKey: _failure(error));
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
      ({int revision, String wallpaper})? background;
      if (syncBackground) {
        try {
          background = await _backgroundRequest(lease);
        } on Object {
          // Online failure must not prevent the explicitly requested local save.
        }
        if (!identical(_lease, lease) || !_current(lease.epoch, lease.generation)) {
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
            await _backgroundRequest(lease,
              revision: background.revision, wallpaper: edit.wallpaperId);
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
        failureKey: _failure(error),
      );
    }
  }

  Future<({int revision, String wallpaper})> _backgroundRequest(
    _LocalLease lease, {int? revision, String? wallpaper}) async {
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final response = await _session.request(
      revision == null ? 'personalProfile.readBackground' : 'personalProfile.saveBackground',
      accountContext: lease.owner,
      timeout: _timeout,
      payload: {'schemaVersion': 1,
        'expectedRevision': ?revision,
        'wallpaperId': ?wallpaper},
    );
    _validate(response, lease.owner);
    if (!_current(lease.epoch, lease.generation)) throw StateError('stale');
    final receivedRevision = response.payload['revision'];
    final receivedWallpaper = response.payload['wallpaperId'];
    if (receivedRevision is! int || receivedRevision < 0 ||
        receivedWallpaper is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{1,100}$').hasMatch(receivedWallpaper) ||
        revision != null && (receivedRevision != revision + 1 || receivedWallpaper != wallpaper)) {
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
        response.payload['schemaVersion'] != 1) {
      throw const FormatException();
    }
  }

  static String _failure(Object error) => switch (error) {
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
  );
  final BridgeAccountContext owner;
  final int generation, epoch, revision;
  final List<String>? favorites;
  final Map<String, Object?>? content;
}
