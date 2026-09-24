import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'continuous_play_controller.dart';

final class BridgeContinuousPlay implements ContinuousPlayPort {
  BridgeContinuousPlay(this._session);
  final BridgeClientSession _session;
  @override
  Future<ContinuousPlayValue> read() async => _parse(
    (await _session.request(
      'playReminder.read',
      payload: const {'schemaVersion': 1},
    )).payload,
  );
  @override
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired) async => _parse(
    (await _session.request(
      'playReminder.save',
      payload: {
        'schemaVersion': 1,
        'expectedRevision': desired.revision,
        'enabled': desired.enabled,
        'firstReminderMinutes': desired.firstMinutes,
        'repeatReminderMinutes': desired.repeatMinutes,
      },
    )).payload,
  );
  static ContinuousPlayValue _parse(Map<String, Object?> body) {
    final enabled = body['enabled'];
    final first = body['firstReminderMinutes'];
    final repeat = body['repeatReminderMinutes'];
    final revision = body['revision'];
    if (body['schemaVersion'] != 1 ||
        body.length != 5 ||
        enabled is! bool ||
        first is! int ||
        ![60, 90, 120, 180].contains(first) ||
        repeat is! int ||
        ![60, 120].contains(repeat) ||
        revision is! int ||
        revision < 0) {
      throw const BridgeFormatException('Invalid play reminder settings.');
    }
    return ContinuousPlayValue(
      enabled: enabled,
      firstMinutes: first,
      repeatMinutes: repeat,
      revision: revision,
    );
  }
}
