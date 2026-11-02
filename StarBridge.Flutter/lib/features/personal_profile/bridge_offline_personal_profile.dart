import '../../platform/bridge/bridge_client_session.dart';
import '../hangar/bridge_local_hangar.dart';
import '../hangar/local_hangar_port.dart';
import '../onboarding/connection_mode_port.dart';
import 'personal_profile_local_projection.dart';
import 'personal_profile_models.dart';
import 'personal_profile_port.dart';
import 'profile_read_failure.dart';
import 'bridge_personal_profile_adapter.dart' show parsePersonalProfileSnapshot;

/// Reads only Native-selected original local and cached self presentation. No remote fallback,
/// account binding, publication, migration or editor lease is created here.
final class BridgeOfflinePersonalProfile implements PersonalProfilePort {
  BridgeOfflinePersonalProfile(this.session, ConnectionModeControl mode)
    : mode = mode,
      revision = mode.snapshot.revision!,
      scope = mode.snapshot.scope,
      _readId = null,
      isCurrent = null;
  BridgeOfflinePersonalProfile.retained(
    this.session,
    String readId, {
    required this.isCurrent,
  }) : mode = null,
       revision = 0,
       scope = session.activeGeneration,
       _readId = readId;
  final BridgeClientSession session;
  final ConnectionModeControl? mode;
  final String? _readId;
  final bool Function()? isCurrent;
  final int revision;
  final Object scope;
  bool _closed = false;
  bool get _current =>
      !_closed &&
      (_readId != null
          ? session.activeGeneration == scope && isCurrent!()
          : !mode!.failed &&
                mode!.snapshot.isOffline &&
                mode!.snapshot.revision == revision &&
                mode!.snapshot.scope == scope &&
                mode!.snapshot.offlineAccount != null);

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) => const {
          'account.changed',
          'bootstrap.invalidated',
        }.contains(event.name),
      )
      .map((_) {});

  @override
  Future<PersonalProfileSnapshot> read() async {
    if (!_current) return const PersonalProfileSnapshot.unavailable();
    final generation = session.activeGeneration;
    try {
      final response = await session.request(
        _readId != null
            ? 'account.offlineData.read'
            : 'onboarding.mode.profile',
        payload: _readId != null
            ? {'schemaVersion': 1, 'readId': _readId, 'kind': 'profile'}
            : {'schemaVersion': 1, 'revision': revision},
      );
      if (!_current ||
          session.activeGeneration != generation ||
          response.sessionGeneration != generation ||
          response.accountContext != null ||
          response.payload['schemaVersion'] is! int ||
          response.payload['schemaVersion'] != 1) {
        return const PersonalProfileSnapshot.unavailable();
      }
      final content = response.payload['content'];
      final profileRevision = response.payload['revision'];
      final savedAt = DateTime.tryParse(
        response.payload['savedAt'] as String? ?? '',
      );
      var remote = const PersonalProfileSnapshot.unavailable();
      DateTime? confirmedAt;
      if (response.payload['remote'] case final Map cached) {
        final payload = cached['payload'];
        final rawAt = cached['cachedAtUtc'];
        confirmedAt = rawAt is String ? DateTime.tryParse(rawAt) : null;
        if (payload is! Map ||
            payload['editable'] != false ||
            confirmedAt == null ||
            !confirmedAt.isUtc ||
            !confirmedAt.isAfter(
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            ) ||
            confirmedAt.isAfter(
              DateTime.now().toUtc().add(const Duration(minutes: 5)),
            )) {
          return const PersonalProfileSnapshot.unavailable();
        }
        remote = parsePersonalProfileSnapshot(payload.cast<String, Object?>());
        if (remote.allowEditing ||
            remote.gameHandle.isNotEmpty ||
            remote.affiliations.isNotEmpty ||
            remote.presenceIntent != PersonalProfilePresenceIntent.none) {
          return const PersonalProfileSnapshot.unavailable();
        }
      }
      // Absence is not a newly created empty profile. Preserve the original file.
      final localAvailable =
          profileRevision is int &&
          profileRevision > 0 &&
          content is Map &&
          savedAt != null;
      if (!localAvailable &&
          remote.availability != PersonalProfileAvailability.available) {
        return const PersonalProfileSnapshot.unavailable();
      }
      LocalHangarSnapshot? hangar;
      try {
        hangar =
            await (_readId != null
                    ? BridgeLocalHangar.retained(
                        session,
                        _readId,
                        isCurrent: () => _current,
                      )
                    : BridgeLocalHangar.offline(session, revision))
                .read();
      } on Object {
        /* An unavailable inventory never becomes an empty inventory. */
      }
      if (!_current || session.activeGeneration != generation) {
        return const PersonalProfileSnapshot.unavailable();
      }
      return projectLocalProfile(
        remote,
        localAvailable ? content.cast<String, Object?>() : null,
        hangar,
        confirmedAt ?? savedAt,
        readOnly: true,
      );
    } on Object catch (error) {
      return PersonalProfileSnapshot.unavailable(
        transientReadFailure:
            _current &&
            session.activeGeneration == generation &&
            profileReadIsTransient(error),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);
  @override
  Future<void> close() async {
    _closed = true;
  }
}
