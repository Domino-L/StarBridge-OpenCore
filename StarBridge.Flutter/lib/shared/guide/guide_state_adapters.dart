import '../../platform/bridge/bridge_client_session.dart';
import 'guide_state.dart';

final class BridgeGuideState implements GuideStatePort {
  BridgeGuideState(this.session);
  static const capability = 'guide.state.v1';
  final BridgeClientSession session;

  @override
  bool get supported => session.hostCapabilities.contains(capability);

  @override
  Future<GuideState> read() => _call('guide.state.read', const {});

  @override
  Future<GuideState> update(List<GuideOp> ops) => _call('guide.state.update', {
    'ops': [for (final op in ops) op.toWire()],
  });

  Future<GuideState> _call(String name, Map<String, Object?> payload) async {
    if (!supported) return GuideState.unavailable;
    final generation = session.activeGeneration;
    final response = await session.request(name, payload: payload);
    if (response.sessionGeneration != generation) {
      throw StateError('Guide context changed.');
    }
    return parseGuideState(response.payload);
  }
}

/// Tests, examples and review shells.
final class InMemoryGuideState implements GuideStatePort {
  InMemoryGuideState([GuideState initial = const GuideState(available: true)])
    : _state = initial;
  GuideState _state;
  int writes = 0;

  @override
  bool get supported => true;

  @override
  Future<GuideState> read() async => _state;

  @override
  Future<GuideState> update(List<GuideOp> ops) async {
    writes++;
    if (!_state.available) return _state;
    for (final op in ops) {
      _state = _state.apply(op);
    }
    return _state;
  }
}
