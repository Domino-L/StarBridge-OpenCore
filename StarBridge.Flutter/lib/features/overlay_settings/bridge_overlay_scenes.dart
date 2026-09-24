import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'overlay_scene_controller.dart';

final class BridgeOverlayScenes implements OverlayScenePort {
  BridgeOverlayScenes(this._session) {
    _events = _session.events.listen(
      (event) {
        if (event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated') {
          _epoch++;
          _pending?.cancel();
          _invalidations.add(null);
        }
      },
      onDone: () {
        if (!_closed) {
          _epoch++;
          _invalidations.add(null);
        }
      },
    );
  }
  final BridgeClientSession _session;
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _events;
  BridgeRequestOperation? _pending;
  bool _closed = false;
  int _epoch = 0;
  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  Future<OverlaySceneState> read() => _request('overlayScenes.read');
  @override
  Future<OverlaySceneState> focusCommunity(String code) =>
      _request('overlayScenes.focusCommunity', {'code': code});
  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) =>
      _request('overlayScenes.select', {
        'revision': revision,
        'mode': mode,
        'code': code,
      });
  Future<OverlaySceneState> _request(
    String name, [
    Map<String, Object?> fields = const {},
  ]) async {
    if (_closed || !_session.hostCapabilities.contains(name)) {
      return const OverlaySceneState(status: 'unavailable');
    }
    final epoch = _epoch;
    _pending = _session.beginRequest(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    final account = await _pending!.future;
    if (_closed || epoch != _epoch) throw StateError('Account changed');
    if (!hasRelayAccount(account) || account.accountContext == null) {
      return const OverlaySceneState(status: 'signedOut');
    }
    _pending = _session.beginRequest(
      name,
      accountContext: account.accountContext,
      payload: {'schemaVersion': 1, ...fields},
      timeout: const Duration(seconds: 25),
    );
    final response = await _pending!.future;
    if (_closed ||
        epoch != _epoch ||
        response.accountContext?.environment !=
            account.accountContext!.environment ||
        response.accountContext?.authority !=
            account.accountContext!.authority ||
        response.accountContext?.subject != account.accountContext!.subject) {
      throw StateError('Account changed');
    }
    return parse(response.payload);
  }

  static OverlaySceneState parse(Map<String, Object?> p) {
    if (p['schemaVersion'] != 1 ||
        p['revision'] is! int ||
        (p['revision']! as int) < 0 ||
        !['auto', 'room', 'community'].contains(p['mode']) ||
        ![
          'ready',
          'local',
          'unavailable',
          'loading',
          'standby',
        ].contains(p['status']) ||
        p['organizations'] is! List) {
      throw const FormatException('Invalid scene snapshot');
    }
    String? optional(Object? value) {
      if (value == null) return null;
      if (value is! String ||
          value.length > 512 ||
          value.contains(RegExp(r'[\x00-\x1f]'))) {
        throw const FormatException();
      }
      return value;
    }

    final code = optional(p['code']);
    if (p['mode'] == 'community'
        ? code == null || code.isEmpty
        : code != null) {
      throw const FormatException();
    }
    final targets = <OverlaySceneTarget>[];
    final seen = <String>{};
    for (final row in p['organizations']! as List) {
      if (row is! Map) throw const FormatException();
      final id = optional(row['code']);
      final name = optional(row['name']);
      if (id == null ||
          id.isEmpty ||
          name == null ||
          !seen.add(id) ||
          targets.length >= 2560) {
        throw const FormatException();
      }
      targets.add(OverlaySceneTarget(id, name));
    }
    final actual = optional(p['actualId']);
    if (actual != null &&
        actual != 'room' &&
        !targets.any((x) => actual == 'org:${x.code}')) {
      throw const FormatException();
    }
    return OverlaySceneState(
      revision: p['revision']! as int,
      mode: p['mode']! as String,
      code: code,
      actualId: actual,
      status: p['status']! as String,
      targets: List.unmodifiable(targets),
      available: true,
    );
  }

  @override
  void close() {
    _closed = true;
    _epoch++;
    _pending?.cancel();
    unawaited(_events.cancel());
    unawaited(_invalidations.close());
  }
}
