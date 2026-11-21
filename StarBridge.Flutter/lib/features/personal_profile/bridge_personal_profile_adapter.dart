import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_showcases.dart';
import 'personal_profile_models.dart';
import 'personal_profile_presentation.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_port.dart';
import 'bridge_personal_profile_account_facts.dart';
import 'profile_read_failure.dart';
import 'profile_read_scope.dart';
import 'profile_edit_lease.dart';
import 'personal_profile_snapshot_wire.dart';

export 'personal_profile_snapshot_wire.dart' show parsePersonalProfileSnapshot;

/// Reads and writes the StarBridge personal-profile contract through the Native
/// Host. The adapter never receives the SCM bearer or backend identity keys.
final class BridgePersonalProfileAdapter
    implements
        PersonalProfilePort,
        PersonalProfileAccountFactsReader,
        PersonalProfilePresentationWriter,
        PersonalProfileContentChanges,
        ProfileReadScopeOwner,
        ProfileReadGenerationOwner,
        ProfileReadAccountAdvanceOwner {
  BridgePersonalProfileAdapter(this._session) {
    _invalidationGeneration = _session.activeGeneration;
    _eventSubscription = _session.events.listen(_onBridgeEvent);
  }

  final BridgeClientSession _session;
  @override
  Future<PersonalProfilePublicFacts?> readAccountFacts() =>
      readProfileAccountFacts(_session);
  @override
  int get activeReadGeneration => _session.activeGeneration;
  // Profile reads share the Host account queue and may include session restore.
  static const _readTimeout = Duration(seconds: 60);
  final _invalidations = StreamController<void>.broadcast();
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _eventSubscription;
  ProfileEditLease? _editLease;
  bool _closed = false;
  late int _invalidationGeneration;
  ProfileReadAccountAdvance? _readAccountAdvance;
  @override
  ProfileReadAccountAdvance? get readAccountAdvance => _readAccountAdvance;
  ProfileReadScope? _readScope;
  @override
  ProfileReadScope? get readScope => _readScope;

  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonalProfileSnapshot> read() async {
    if (_closed) return const PersonalProfileSnapshot.unavailable();
    _readScope = null;
    _editLease = null;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _readTimeout,
      );
      ProfileReadScope.requireSchema(account.payload);
      final state = requireProfileWireString(account.payload, 'state');
      if (account.sessionGeneration != _session.activeGeneration) {
        throw BridgeStaleGenerationException(
          account.sessionGeneration,
          _session.activeGeneration,
        );
      }
      if (state == 'signedOut' || state == 'reauthorizationRequired') {
        return const PersonalProfileSnapshot.signedOut();
      }
      if ((state != 'signedIn' && state != 'legacySignedIn') ||
          account.accountContext == null) {
        throw const BridgeFormatException(
          'Signed-in personal profile requires accountContext.',
        );
      }

      final response = await _session.request(
        'personalProfile.getSelf',
        payload: const {'schemaVersion': 1},
        accountContext: account.accountContext,
        timeout: _readTimeout,
      );
      final profile = requireProfileWireMap(response.payload, 'profile');
      final snapshot = parsePersonalProfileSnapshot(response.payload);
      final scope = ProfileReadScope.fromResponse(
        account,
        response,
        _session.activeGeneration,
      );
      if (_closed) return const PersonalProfileSnapshot.unavailable();
      if (state == 'signedIn' && snapshot.allowEditing) {
        _editLease = ProfileEditLease(
          account.accountContext!,
          account.sessionGeneration,
          requireProfileWireRevision(profile, 'revision'),
          snapshot.presentation,
        );
      }
      _readScope =
          snapshot.availability == PersonalProfileAvailability.available
          ? scope
          : null;
      return snapshot;
    } on Object catch (error) {
      return PersonalProfileSnapshot.unavailable(
        failureKey: profileReadFailureKey(error),
        transientReadFailure: profileReadIsTransient(error),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    final lease = _editLease;
    if (lease == null) return _refreshBeforeSave;
    // Versioned pages must use explicit groups. Never downgrade a new server
    // lease to the legacy whole-page writer.
    if (lease.presentation != null) return _refreshBeforeSave;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      ProfileReadScope.requireSchema(account.payload);
      if (requireProfileWireString(account.payload, 'state') != 'signedIn' ||
          account.accountContext == null) {
        return const PersonalProfileActionResult(
          PersonalProfileActionOutcome.rejected,
          failureKey: 'profile.error.reauthorizationRequired',
        );
      }
      if (!identical(_editLease, lease) ||
          !lease.matches(account) ||
          _session.activeGeneration != lease.generation) {
        _editLease = null;
        return _refreshBeforeSave;
      }
      final response = await _session.request(
        'personalProfile.updateSelf',
        payload: <String, Object?>{
          'schemaVersion': 1,
          'patch': <String, Object?>{
            'expectedRevision': lease.revision,
            'visibility': edit.visibility.bridgeValue,
            'callSign': edit.callSign.trim(),
            'avatarStyle': edit.avatarStyle,
            'wallpaperId': edit.wallpaperId,
            'introduction': edit.about.trim(),
            'modules': <Object?>[
              for (final module in PersonalProfileShowcases.modulesOf(
                edit.moduleLayout,
              ))
                <String, Object?>{
                  'id': module.moduleId,
                  'span': module.size.span,
                  'isVisible': module.isVisible,
                  'position': module.position,
                },
            ],
          },
        },
        accountContext: account.accountContext,
      );
      ProfileReadScope.requireSchema(response.payload);
      if (!identical(_editLease, lease) ||
          _session.activeGeneration != lease.generation) {
        return _refreshBeforeSave;
      }
      _editLease = ProfileEditLease(
        lease.context,
        lease.generation,
        requireProfileWireRevision(
          requireProfileWireMap(response.payload, 'profile'),
          'revision',
        ),
      );
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
      );
    } on Object catch (error) {
      if (error is BridgeClientException &&
          error.code == 'personal_profile.write_conflict' &&
          identical(_editLease, lease)) {
        _editLease = null;
      }
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.failed,
        failureKey: profileSaveFailureKey(error),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> savePresentation(
    PersonalProfilePresentation expected,
    Map<String, Map<String, Object?>> edits,
  ) async {
    final lease = _editLease;
    var attempted = false;
    if (lease == null ||
        !identical(lease.presentation, expected) ||
        !_session.hostCapabilities.contains(
          'personalProfile.presentation.write.v1',
        )) {
      return _refreshBeforeSave;
    }
    try {
      final payload = expected.editRequest(edits);
      if (payload == null) {
        return const PersonalProfileActionResult(
          PersonalProfileActionOutcome.completed,
        );
      }
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      ProfileReadScope.requireSchema(account.payload);
      if (account.payload['state'] != 'signedIn' ||
          !lease.matches(account) ||
          !identical(_editLease, lease) ||
          _session.activeGeneration != lease.generation ||
          !_session.hostCapabilities.contains(
            'personalProfile.presentation.write.v1',
          )) {
        _editLease = null;
        return _refreshBeforeSave;
      }
      attempted = true;
      final response = await _session.request(
        'personalProfile.updatePresentation',
        payload: payload,
        accountContext: lease.context,
        timeout: _readTimeout,
      );
      // An already dispatched write can still have a valid receipt after
      // its view closes. The surviving entry point shares the owner lock.
      if ((!_closed && !identical(_editLease, lease)) ||
          !lease.matches(response) ||
          _session.activeGeneration != lease.generation) {
        throw const BridgeFormatException('Stale page confirmation.');
      }
      final confirmed = parsePersonalProfileSnapshot(response.payload);
      final saved = confirmed.presentation;
      if (saved == null ||
          saved.revision != lease.revision + 1 ||
          edits.keys.any((group) => saved.origins[group] != 'custom')) {
        throw const FormatException('Page confirmation');
      }
      // Require a new displayed read before another edit, including uncertain
      // writes. No rebase or automatic replay with a newer revision.
      _editLease = null;
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
        confirmedProfile: confirmed,
      );
    } on Object catch (error) {
      if (identical(_editLease, lease)) _editLease = null;
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.failed,
        requiresReload: true,
        presentationDispatched: attempted,
        failureKey: attempted
            ? profilePageSaveFailureKey(error)
            : profileSaveFailureKey(error),
      );
    }
  }

  void _onBridgeEvent(BridgeEnvelope event) {
    if (event.name == 'account.changed' ||
        event.name == 'bootstrap.invalidated') {
      _readAccountAdvance = ProfileReadAccountAdvance.observe(
        event,
        _invalidationGeneration,
        _session.activeGeneration,
      );
      _invalidationGeneration = _session.activeGeneration;
      _readScope = null;
      _editLease = null;
      _invalidations.add(null);
    } else if (event.name == 'personalProfile.changed') {
      _changes.add(null);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _editLease = null;
    _readScope = null;
    await _eventSubscription.cancel();
    await _invalidations.close();
    await _changes.close();
  }
}

const _refreshBeforeSave = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  requiresReload: true,
  presentationDispatched: false,
  failureKey: 'profile.error.refreshBeforeSave',
);
