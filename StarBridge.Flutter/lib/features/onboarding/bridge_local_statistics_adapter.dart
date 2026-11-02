import '../../platform/bridge/bridge_client_session.dart';
import 'local_statistics_port.dart';

final class BridgeLocalStatisticsAdapter implements LocalStatisticsPort {
  BridgeLocalStatisticsAdapter(this.session);
  static const capability = 'onboarding.localStatistics.v1';
  final BridgeClientSession session;
  LocalStatisticsSnapshot? _current;
  int? _generation;
  int _epoch = 0;
  void _invalidate() {
    _epoch++;
    _current = null;
    _generation = null;
  }

  @override
  Stream<void> get invalidations => session.events
      .where(
        (event) => const {
          'account.changed',
          'bootstrap.invalidated',
          'onboarding.changed',
          'gameLog.changed',
          'onboarding.localStatistics.changed',
        }.contains(event.name),
      )
      .map((_) {
        _invalidate();
      });
  @override
  Future<LocalStatisticsSnapshot> read() async {
    if (!session.hostCapabilities.contains(capability)) {
      _invalidate();
      return const LocalStatisticsSnapshot();
    }
    return _request('onboarding.localStatistics.read', const {});
  }

  @override
  Future<LocalStatisticsSnapshot> confirm(String choiceKey, bool allowed) {
    if (!session.hostCapabilities.contains(capability) ||
        _generation != session.activeGeneration ||
        _current?.choiceKey != choiceKey ||
        _current?.canChoose != true) {
      throw StateError('Local recording choice is no longer current.');
    }
    return _request('onboarding.localStatistics.confirm', {
      'choiceKey': choiceKey,
      'allowed': allowed,
    });
  }

  Future<LocalStatisticsSnapshot> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    final epoch = ++_epoch;
    final generation = session.activeGeneration;
    _current = null;
    _generation = null;
    try {
      final response = await session.request(
        name,
        payload: {'schemaVersion': 1, ...payload},
      );
      if (epoch != _epoch ||
          generation != session.activeGeneration ||
          response.sessionGeneration != generation ||
          !session.hostCapabilities.contains(capability) ||
          response.status != 'ok' ||
          response.error != null) {
        throw StateError('Local recording choice was not confirmed.');
      }
      final value = LocalStatisticsWire.parse(response.payload);
      _current = value;
      _generation = generation;
      return value;
    } on Object {
      if (epoch == _epoch) {
        _invalidate();
      }
      rethrow;
    }
  }
}

abstract final class LocalStatisticsWire {
  static LocalStatisticsSnapshot parse(Map<String, Object?> raw) {
    const fields = {
      'schemaVersion',
      'state',
      'choiceKey',
      'consent',
      'savedSeconds',
      'recording',
    };
    if (raw.length != fields.length ||
        raw.keys.toSet().difference(fields).isNotEmpty ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        raw['recording'] is! bool) {
      _bad();
    }
    final state = LocalStatisticsState.values
        .where((s) => s.name == raw['state'])
        .singleOrNull;
    final consent = LocalStatisticsConsent.values
        .where((s) => s.name == raw['consent'])
        .singleOrNull;
    final key = raw['choiceKey'];
    final seconds = raw['savedSeconds'];
    final recording = raw['recording'] as bool;
    if (state == null ||
        consent == null ||
        key != null &&
            (key is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(key)) ||
        seconds != null &&
            (seconds is! int || seconds < 0 || seconds > 9223372036854775807)) {
      _bad();
    }
    final actionable = const {
      LocalStatisticsState.choiceRequired,
      LocalStatisticsState.retryRequired,
      LocalStatisticsState.saved,
    }.contains(state);
    if (actionable != (key != null) ||
        actionable != (seconds != null) ||
        state == LocalStatisticsState.choiceRequired &&
            (consent != LocalStatisticsConsent.unknown || seconds != 0) ||
        state == LocalStatisticsState.saved &&
            consent == LocalStatisticsConsent.unknown ||
        !actionable && consent != LocalStatisticsConsent.unknown ||
        recording &&
            (state != LocalStatisticsState.saved ||
                consent != LocalStatisticsConsent.allowed)) {
      _bad();
    }
    return LocalStatisticsSnapshot(
      state: state,
      choiceKey: key as String?,
      consent: consent,
      savedSeconds: seconds as int?,
      recording: recording,
    );
  }

  static Never _bad() =>
      throw const FormatException('Invalid local recording projection.');
}
