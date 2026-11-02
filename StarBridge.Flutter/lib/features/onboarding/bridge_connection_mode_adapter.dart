import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/bounded_inline_avatar.dart';
import 'connection_mode_port.dart';

final class BridgeConnectionModeAdapter
    implements ConnectionModePort, ConnectionModeDisplayContinuitySource {
  BridgeConnectionModeAdapter(this.session);
  static const capability = 'onboarding.mode.v1';
  final BridgeClientSession session;
  ConnectionModeSnapshot? _observed;
  OnlineModeDisplayContinuity? _displayContinuity;
  @override
  OnlineModeDisplayContinuity? get displayContinuity =>
      supported && _displayContinuity?.generation == session.activeGeneration
      ? _displayContinuity
      : null;
  int _epoch = 0;
  @override
  bool get supported => session.hostCapabilities.contains(capability);
  void _invalidate() {
    _epoch++;
    _observed = null;
    _displayContinuity = null;
  }

  @override
  Stream<void> get invalidations => session.events
      .where(
        (e) => const {
          'account.changed',
          'bootstrap.invalidated',
          'onboarding.changed',
        }.contains(e.name),
      )
      .map((event) {
        final previous = _observed;
        _invalidate();
        final scope = previous?.scope;
        if (event.name == 'account.changed' &&
            event.payload['schemaVersion'] is int &&
            event.payload['schemaVersion'] == 1 &&
            scope is int &&
            previous!.state == ConnectionModeState.online &&
            previous.revision != null &&
            event.sessionGeneration == scope + 1 &&
            session.activeGeneration == event.sessionGeneration) {
          _displayContinuity = OnlineModeDisplayContinuity(
            sourceGeneration: scope,
            generation: event.sessionGeneration,
            revision: previous.revision!,
          );
        }
      });
  @override
  Future<ConnectionModeSnapshot> read() async {
    if (!supported) {
      _invalidate();
      return const ConnectionModeSnapshot();
    }
    return _request('read', const {});
  }

  @override
  Future<ConnectionModeSnapshot> enterOffline(int revision) {
    final old = _observed;
    if (!supported ||
        old == null ||
        old.scope != session.activeGeneration ||
        old.revision != revision ||
        old.state != ConnectionModeState.online ||
        !old.canEnterOffline) {
      throw StateError('Mode observation is no longer current.');
    }
    _observed = null; // One write per original observation; no implicit retry.
    _displayContinuity = null;
    final epoch = _epoch;
    return session.runConnectionModeChange(() {
      if (!supported || epoch != _epoch) {
        throw StateError('Mode observation changed while draining.');
      }
      return _request('offline', {'revision': revision});
    });
  }

  Future<ConnectionModeSnapshot> _request(
    String action,
    Map<String, Object?> payload,
  ) async {
    final epoch = ++_epoch, generation = session.activeGeneration;
    try {
      final response = await session.request(
        'onboarding.mode.$action',
        payload: {'schemaVersion': 1, ...payload},
        timeout: const Duration(seconds: 45),
      );
      if (epoch != _epoch ||
          !supported ||
          generation != session.activeGeneration ||
          response.sessionGeneration != generation ||
          response.accountContext != null) {
        throw StateError('Mode context changed.');
      }
      final result = ConnectionModeWire.parse(response.payload, generation);
      _observed = result;
      _displayContinuity = null;
      return result;
    } on Object {
      if (epoch == _epoch) _invalidate();
      rethrow;
    }
  }
}

abstract final class ConnectionModeWire {
  static ConnectionModeSnapshot parse(Map<String, Object?> raw, Object scope) {
    const fields = {
      'schemaVersion',
      'revision',
      'state',
      'activeMode',
      'publicationSuspended',
      'canEnterOffline',
    };
    final revision = raw['revision'],
        active = raw['activeMode'],
        suspended = raw['publicationSuspended'],
        can = raw['canEnterOffline'];
    final state = ConnectionModeState.values
        .where(
          (s) => s.name == raw['state'] && s != ConnectionModeState.unsupported,
        )
        .singleOrNull;
    if (raw.keys.any(
          (key) => !fields.contains(key) && key != 'offlineAccount',
        ) ||
        !fields.every(raw.containsKey) ||
        raw['schemaVersion'] is! int ||
        raw['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        revision > 9223372036854775807 ||
        state == null ||
        suspended is! bool ||
        can is! bool ||
        (active != null && active != 'online' && active != 'local') ||
        (state == ConnectionModeState.online
            ? active != 'online' || suspended
            : const {
                ConnectionModeState.local,
                ConnectionModeState.offline,
                ConnectionModeState.signInRequired,
              }.contains(state)
            ? active != 'local' || !suspended
            : active != null || suspended) ||
        can && state != ConnectionModeState.online) {
      throw const FormatException('Invalid mode observation.');
    }
    return ConnectionModeSnapshot(
      scope: scope,
      revision: revision,
      state: state,
      canEnterOffline: can,
      offlineAccount: _offlineAccount(raw['offlineAccount'], state),
    );
  }

  static OfflineAccountDisplay? _offlineAccount(
    Object? raw,
    ConnectionModeState state,
  ) {
    if (raw == null) return null;
    if (state != ConnectionModeState.offline ||
        raw is! Map ||
        raw.keys.any(
          (key) => !const {
            'displayName',
            'cachedAtUtc',
            'avatarImageData',
            'avatarCachedAtUtc',
          }.contains(key),
        ) ||
        raw['displayName'] is! String ||
        raw['cachedAtUtc'] is! String) {
      throw const FormatException('Invalid offline display.');
    }
    final name = raw['displayName'] as String;
    final at = DateTime.tryParse(raw['cachedAtUtc'] as String);
    if (name.trim().isEmpty || name.length > 256 || at == null || !at.isUtc) {
      throw const FormatException('Invalid offline display.');
    }
    final avatarAt = inlineAvatarObservedAt(raw['avatarCachedAtUtc']);
    final image = avatarAt == null
        ? null
        : boundedInlineAvatar(raw['avatarImageData']);
    return OfflineAccountDisplay(
      name,
      at,
      avatarImageData: image,
      avatarCachedAtUtc: image == null ? null : avatarAt,
    );
  }
}
