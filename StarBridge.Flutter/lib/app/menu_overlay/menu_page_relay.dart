import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/account/account_models.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_connection.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/window/menu_bridge_relay.dart';
import '../../shared/bounded_inline_avatar.dart';

/// The menu engine's side of the page relay: one real [BridgeClientSession]
/// whose frames travel through the primary engine. Hiding the menu closes
/// traffic the way offline mode does, so a hidden hall sends nothing.
final class MenuPageRelay extends ChangeNotifier
    implements ConnectionModeControl {
  MenuPageRelay(this._channel);
  final MethodChannel _channel;
  int _opening = -1;
  bool _enabled = false, _wanted = false, _disposed = false;

  /// The primary's online fact, kept while the menu is hidden: hiding is not
  /// going offline (see [hostMode]).
  bool _hostOnline = false;
  _RelayConnection? _connection;
  BridgeClientSession? _session;
  Future<BridgeClientSession?>? _connecting;
  int _connectingOpening = -1, _contextRevision = 0;
  Object? _relay, _epoch;
  Completer<void>? _paused;
  final _exits = <Future<void> Function()>{};
  final _clientOnly = StreamController<String>.broadcast(sync: true);

  /// A page asked for something that is done in the client only (the name of
  /// the request). It was answered here and never left the menu.
  Stream<String> get clientOnlyAsked => _clientOnly.stream;

  /// The relayed page the user touched last (pages share one session).
  Object? lastTouched;

  bool get enabled => _enabled;
  bool get active => _enabled && _wanted;

  /// The connection mode for pages that must keep their writes when the menu
  /// hides (organizations, main fleet): it follows the primary's online fact,
  /// not visibility. Images and the hall use this relay itself, which closes
  /// with the menu. A hidden menu sends nothing either way: the primary and
  /// native refuse it, and reads in flight are cancelled there.
  ConnectionModeControl get hostMode => _hostMode;
  late final _hostMode = _HostMode(this);

  /// Pages using the shared session. They outlive a session replaced after a
  /// revocation (they connect again), so only switching the relay off or
  /// disposing it forgets them.
  final _holders = <Object>{};

  /// The user's own name and avatar while this opening is shown; gone when the
  /// menu hides or the session is released.
  AccountProfile? get ownProfile => _ownProfile;
  AccountProfile? _ownProfile;

  /// Whether the user counts as online for a rally, as the client decides it.
  bool get countedOnline => _countedOnline;
  bool _countedOnline = true;

  /// Whether the account is SCM-only, as the client decides it.
  bool get scmOnly => _scmOnly;
  bool _scmOnly = false;

  /// Moves when the account behind the session changes.
  int get contextRevision => _contextRevision;

  /// A page whose network work must have exited before the primary may switch
  /// the connection mode of a hidden menu. Returns the removal.
  void Function() registerExit(Future<void> Function() exited) {
    _exits.add(exited);
    return () => _exits.remove(exited);
  }

  /// From the surface's snapshot, on every opening and hide.
  void update({
    required int opening,
    required bool wanted,
    required bool enabled,
  }) {
    final wasActive = active, previous = _opening;
    _opening = opening;
    _wanted = wanted;
    _enabled = enabled;
    if (!enabled) _holders.clear();
    if (!enabled && _session != null) unawaited(release());
    if (!active) _ownProfile = null;
    if (wasActive != active) notifyListeners();
    if (wasActive && !active) unawaited(_confirmExit(previous));
  }

  /// Hiding cancelled this engine's work (its mode closed with [active]). Once
  /// that work has really exited, the primary hears so for the hidden opening.
  Future<void> _confirmExit(int opening) async {
    await Future.wait([
      for (final exited in _exits.toList())
        exited().then<void>((_) {}, onError: (Object _) {}),
    ]);
    await _channel
        .invokeMethod<void>('bridgeRelay', {
          'opening': opening,
          'action': 'exited',
        })
        .then<void>((_) {}, onError: (Object _) {});
  }

  /// The surface's snapshot. A new native tools epoch means the account or
  /// session detached, so nothing of the old session may be reused.
  void fromSnapshot(int opening, bool wanted, Map<Object?, Object?> value) {
    final epoch = value['localToolsEpoch'];
    if (epoch != null && epoch != _epoch) {
      if (_epoch != null) _revoke();
      _epoch = epoch;
    }
    update(
      opening: opening,
      wanted: wanted,
      enabled: wanted ? value['pageRelay'] == true : _enabled,
    );
  }

  void _revoke() {
    _contextRevision++;
    unawaited(release());
  }

  /// The session, greeted for this opening. Null when the menu closed first.
  /// An older opening's unfinished greeting never answers for this one.
  Future<BridgeClientSession?> connect({Object? holder}) {
    if (holder != null) _holders.add(holder);
    final pending = _connecting;
    if (pending != null && _connectingOpening == _opening) return pending;
    _connectingOpening = _opening;
    late final Future<BridgeClientSession?> work;
    work = _connect(_opening).whenComplete(() {
      if (identical(_connecting, work)) _connecting = null;
    });
    return _connecting = work;
  }

  Future<BridgeClientSession?> _connect(int opening) async {
    if (!active) return null;
    try {
      final reply = await _channel.invokeMethod<String>('bridgeRelay', {
        'opening': opening,
        'action': 'hello',
      });
      if (reply == null || _disposed || !active || opening != _opening) {
        return null;
      }
      final state = jsonDecode(reply) as Map;
      // Another primary composition: its session is not this one.
      if (_session != null && state['relay'] != _relay) _revoke();
      _relay = state['relay'];
      final session = _session ??= _open(state['generation'] as int);
      _applyState(state);
      return session;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  BridgeClientSession _open(int generation) {
    final session = BridgeClientSession(
      connection: _connection = _RelayConnection(_send, (name) {
        if (!_clientOnly.isClosed) _clientOnly.add(name);
      }),
      sessionGeneration: generation,
    );
    session.observeGenerationChanges((_, _) {
      _contextRevision++;
      // The session is still retiring the old generation's requests.
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
    });
    return session;
  }

  void _applyState(Map<dynamic, dynamic> state) {
    final session = _session, generation = state['generation'];
    if (session == null || session.isClosed || generation is! int) return;
    _resume();
    if (generation > session.activeGeneration) {
      session.advanceGeneration(generation);
    }
    final names = state['capabilities'];
    if (names is List) {
      session.acceptHostCapabilities(names.whereType<String>());
    }
    if (state['countedOnline'] case final bool counted) {
      _countedOnline = counted;
    }
    // An older primary sends no value: that is not SCM-only.
    final scmOnly = state['scmOnly'] == true;
    if (scmOnly != _scmOnly) {
      _scmOnly = scmOnly;
      notifyListeners();
    }
    final self = state['self'];
    final profile = !active || self is! Map
        ? null
        : AccountProfile(
            displayName: self['displayName'] is String
                ? self['displayName'] as String
                : null,
            avatarImageData: boundedInlineAvatar(self['avatarImageData']),
          );
    if (profile?.displayName != _ownProfile?.displayName ||
        profile?.avatarImageData != _ownProfile?.avatarImageData) {
      _ownProfile = profile;
      notifyListeners();
    }
    final online = state['online'] == true;
    if (online != _hostOnline) {
      _hostOnline = online;
      notifyListeners();
      _hostMode._changed();
    }
  }

  /// A `bridgeEvent` from the primary engine, for this opening only.
  void accept(Object? arguments) {
    if (arguments is! Map ||
        !active ||
        arguments['opening'] != _opening ||
        arguments['payload'] is! String) {
      return;
    }
    final Map<dynamic, dynamic> message;
    try {
      message = jsonDecode(arguments['payload'] as String) as Map;
    } on FormatException {
      return;
    }
    if (message['kind'] == 'state') {
      _applyState(message);
    } else if (message['kind'] == 'pause' && message['id'] is int) {
      _pause(message['id'] as int);
    } else if (message['kind'] == 'resume') {
      _resume();
    } else if (message['kind'] == 'event' && message['envelope'] is Map) {
      _connection?.push(
        BridgeEnvelope.fromJson(
          (message['envelope'] as Map).cast<String, Object?>(),
        ),
      );
    }
  }

  /// Stops this engine's network work through the session's own mode change,
  /// answers once it has stopped, and holds until the primary's change is over.
  void _pause(int id) {
    final session = _session;
    Future<void> answer() =>
        _send('paused', '$id').then<void>((_) {}, onError: (Object _) {});
    if (session == null || session.isClosed || _paused != null) {
      unawaited(answer());
      return;
    }
    final resume = _paused = Completer<void>();
    unawaited(
      session
          .runConnectionModeChange(() async {
            await answer();
            await resume.future;
          })
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  void _resume() {
    final resume = _paused;
    _paused = null;
    if (resume != null && !resume.isCompleted) resume.complete();
  }

  Future<String?> _send(String action, String payload) =>
      _channel.invokeMethod<String>('bridgeRelay', {
        'opening': _opening,
        'action': action,
        'payload': payload,
      });

  /// One page let go. The shared session goes only when no page holds it.
  Future<void> releaseFor(Object holder) async {
    _holders.remove(holder);
    if (_holders.isEmpty) await release();
  }

  /// The panel closed or stayed hidden: nothing of the session stays behind.
  Future<void> release() async {
    final session = _session;
    _session = null;
    _connection = null;
    if (_hostOnline) {
      _hostOnline = false;
      _hostMode._changed();
    }
    _ownProfile = null;
    _scmOnly = false;
    _resume();
    await session?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_clientOnly.close());
    unawaited(release());
    super.dispose();
  }

  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    scope: _session?.activeGeneration ?? 0,
    revision: 0,
    state: _hostOnline && active
        ? ConnectionModeState.online
        : ConnectionModeState.switching,
  );
  @override
  bool get allowsOnlineTraffic =>
      _hostOnline && active && _session?.connectionModeChanging != true;
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

final class _RelayConnection implements BridgeConnection {
  _RelayConnection(this._send, this._clientOnly);
  final void Function(String name) _clientOnly;
  final Future<String?> Function(String action, String payload) _send;
  final _incoming = StreamController<BridgeEnvelope>.broadcast();
  bool _closed = false;

  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;

  void push(BridgeEnvelope envelope) {
    if (!_closed) _incoming.add(envelope);
  }

  @override
  Future<void> send(BridgeEnvelope envelope) async {
    if (_closed) throw const BridgeDisconnectedException();
    if (MenuBridgeRelay.clientOnly.contains(envelope.name) ||
        MenuBridgeRelay.changesImages(envelope.name, envelope.payload)) {
      _clientOnly(envelope.name);
      scheduleMicrotask(
        () => push(
          BridgeEnvelope(
            protocolVersion: envelope.protocolVersion,
            messageType: 'response',
            name: envelope.name,
            correlationId: envelope.correlationId,
            sessionGeneration: envelope.sessionGeneration,
            payload: const {},
            status: 'error',
            error: const BridgeErrorBody(
              code: 'menu.client_only',
              message: 'menu.client_only',
              retryable: false,
            ),
          ),
        ),
      );
      return;
    }
    if (envelope.name == 'bridge.cancel') {
      await _send('cancel', envelope.payload['targetCorrelationId'] as String);
      return;
    }
    final reply = await _send('request', jsonEncode(envelope.toJson()));
    if (reply == null) throw const BridgeDisconnectedException();
    push(
      BridgeEnvelope.fromJson(
        (jsonDecode(reply) as Map).cast<String, Object?>(),
      ),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _incoming.close();
  }
}

final class _HostMode extends ChangeNotifier implements ConnectionModeControl {
  _HostMode(this._relay);
  final MenuPageRelay _relay;

  void _changed() => notifyListeners();

  bool get _online =>
      _relay._hostOnline && _relay._session?.connectionModeChanging != true;

  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    scope: _relay._session?.activeGeneration ?? 0,
    revision: 0,
    state: _relay._hostOnline
        ? ConnectionModeState.online
        : ConnectionModeState.switching,
  );
  @override
  bool get allowsOnlineTraffic => _online;
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}
