import '../../platform/bridge/bridge_client_session.dart';
import 'recognition_check_port.dart';

final class BridgeRecognitionCheckAdapter implements RecognitionCheckPort {
  BridgeRecognitionCheckAdapter(this.session);
  static const capability = 'onboarding.recognition.v1';
  final BridgeClientSession session;

  @override
  bool get supported => session.hostCapabilities.contains(capability);

  @override
  Future<RecognitionCheckSnapshot> read() async {
    if (!supported) throw StateError('Recognition check is unavailable.');
    final generation = session.activeGeneration;
    final response = await session.request(
      'onboarding.recognition.read',
      payload: const {'schemaVersion': 1},
    );
    if (response.accountContext != null ||
        response.sessionGeneration != generation) {
      throw StateError('Recognition context changed.');
    }
    return parseRecognitionCheck(response.payload);
  }
}

/// Fail-closed decoder; the bridge omits null fields.
RecognitionCheckSnapshot parseRecognitionCheck(Map<String, Object?> raw) {
  Map<String, Object?> part(String key) {
    final value = raw[key];
    if (value is! Map) throw const FormatException();
    return value.cast<String, Object?>();
  }

  String? text(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String || value.length > 256) throw const FormatException();
    return value;
  }

  const states = {'unknown', 'confirmed', 'likely', 'possible'};
  final state = raw['state'];
  if (raw['schemaVersion'] != 1 || state is! String || state.length > 32) {
    throw const FormatException();
  }
  final server = part('server'),
      location = part('location'),
      ship = part('ship');
  final serverState = server['state'];
  final locationState = location['state'];
  final shipState = ship['state'];
  if (!const {'unknown', 'connected', 'notConnected'}.contains(serverState) ||
      !states.contains(locationState) ||
      !states.contains(shipState)) {
    throw const FormatException();
  }
  return RecognitionCheckSnapshot(
    state: state,
    version: text(raw, 'version'),
    handle: text(raw, 'handle'),
    serverState: serverState as String,
    serverRegion: text(server, 'region'),
    locationState: locationState as String,
    locationEnglish: text(location, 'englishName'),
    locationZhHans: text(location, 'zhHans'),
    shipState: shipState as String,
    shipEnglish: text(ship, 'englishName'),
    shipZhHans: text(ship, 'zhHans'),
    shipZhHant: text(ship, 'zhHant'),
  );
}
