import '../../platform/bridge/bridge_client_session.dart';
import 'online_installation_port.dart';

final class BridgeOnlineInstallationAdapter implements OnlineInstallationPort {
  BridgeOnlineInstallationAdapter(this.session);
  static const capability = 'onboarding.onlineInstallation.v1';
  final BridgeClientSession session;
  bool _disposed = false;
  @override
  bool get supported =>
      !_disposed && session.hostCapabilities.contains(capability);
  @override
  Future<OnlineInstallationSnapshot> read(int revision) =>
      _request('read', revision);
  @override
  Future<OnlineInstallationSnapshot> install(int revision) =>
      _request('install', revision);

  Future<OnlineInstallationSnapshot> _request(
    String action,
    int revision,
  ) async {
    if (!supported || revision < 0 || revision > 9223372036854775807) {
      throw StateError('Installation observation is unavailable.');
    }
    final generation = session.activeGeneration;
    final response = await session.request(
      'onboarding.onlineInstallation.$action',
      payload: {'schemaVersion': 1, 'revision': revision},
      timeout: const Duration(seconds: 45),
    );
    if (!supported ||
        session.activeGeneration != generation ||
        response.sessionGeneration != generation ||
        response.accountContext != null) {
      throw StateError('Installation context changed.');
    }
    final observed = OnlineInstallationWire.parse(
      response.payload,
      revision,
      generation,
    );
    // The Host's exact original-task route advances transport freshness only.
    // Neither this observation nor generation supplies an account context;
    // callers must reread real mode/account before reopening online traffic.
    if (observed.controlGeneration > generation) {
      session.advanceGeneration(observed.controlGeneration);
    }
    return observed;
  }

  void dispose() => _disposed = true;
}

abstract final class OnlineInstallationWire {
  static OnlineInstallationSnapshot parse(
    Map<String, Object?> raw,
    int revision,
    int generation,
  ) {
    const fields = {
      'schemaVersion',
      'revision',
      'phase',
      'controlGeneration',
      'modeRevision',
      'modeState',
    };
    final phase = OnlineInstallationPhase.values
        .where((p) => p.name == raw['phase'])
        .singleOrNull;
    final control = raw['controlGeneration'],
        modeRevision = raw['modeRevision'],
        state = raw['modeState'];
    if (raw.keys.any((key) => !fields.contains(key) && key != 'failure') ||
        !fields.every(raw.containsKey) ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        raw['revision'] is! int ||
        raw['revision'] != revision ||
        phase == null ||
        control is! int ||
        control < generation ||
        control > 9223372036854775807 ||
        modeRevision is! int ||
        modeRevision < 0 ||
        modeRevision > 9223372036854775807 ||
        !const {
          'unavailable',
          'online',
          'local',
          'offline',
          'switching',
          'signInRequired',
          'recoveryRequired',
        }.contains(state) ||
        phase == OnlineInstallationPhase.idle && modeRevision != revision ||
        phase == OnlineInstallationPhase.completed &&
            !const {
              'online',
              'local',
              'offline',
              'recoveryRequired',
            }.contains(state) ||
        phase == OnlineInstallationPhase.completed &&
            state == 'online' &&
            modeRevision != revision + 1) {
      throw const FormatException('Invalid installation observation.');
    }
    OnlineInstallationFailure? failure;
    if (raw.containsKey('failure')) {
      final value = raw['failure'];
      if (phase != OnlineInstallationPhase.completed ||
          state == 'online' ||
          value is! Map ||
          value.length != 2 ||
          !const {
            'prepareAccount',
            'drainNative',
            'retireLocalSources',
            'stageBusiness',
            'configureBusiness',
            'activateBusiness',
            'installNative',
            'commitMode',
          }.contains(value['stage']) ||
          !const {
            'cancelled',
            'rejected',
            'storage',
            'timeout',
            'unexpected',
            'notCommitted',
          }.contains(value['kind'])) {
        throw const FormatException('Invalid installation diagnostic.');
      }
      failure = OnlineInstallationFailure(
        value['stage'] as String,
        value['kind'] as String,
      );
    }
    return OnlineInstallationSnapshot(
      revision: revision,
      phase: phase,
      controlGeneration: control,
      modeRevision: modeRevision,
      modeState: state as String,
      failure: failure,
    );
  }
}
