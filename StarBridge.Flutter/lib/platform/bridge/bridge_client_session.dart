import 'dart:async';

import 'bridge_connection.dart';
import 'connection_mode_network_work.dart';
export 'connection_mode_network_work.dart';
import 'bridge_envelope.dart';
import 'bridge_account_agnostic_requests.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import 'bridge_shared_account_read.dart';
import 'bridge_shared_friends_read.dart';
import 'bridge_request_operation.dart';
export 'bridge_request_operation.dart';

typedef BridgeCorrelationIdFactory = String Function();

final class BridgeClientSession {
  factory BridgeClientSession({
    required BridgeConnection connection,
    required int sessionGeneration,
    Duration requestTimeout = const Duration(seconds: 15),
    BridgeCorrelationIdFactory? correlationIdFactory,
  }) => BridgeClientSession._(
    connection,
    sessionGeneration,
    requestTimeout,
    correlationIdFactory ?? _createDefaultCorrelationIdFactory(),
  );

  BridgeClientSession._(
    this._connection,
    this._activeGeneration,
    this._requestTimeout,
    this._correlationIdFactory,
  ) {
    if (_activeGeneration < 0) {
      throw ArgumentError.value(
        _activeGeneration,
        'sessionGeneration',
        'must be non-negative',
      );
    }
    _subscription = _connection.incoming.listen(
      _handleIncoming,
      onError: _handleTerminalError,
      onDone: _handleDone,
      cancelOnError: false,
    );
  }

  final BridgeConnection _connection;
  final Duration _requestTimeout;
  final BridgeCorrelationIdFactory _correlationIdFactory;
  final Map<String, _PendingRequest> _pending = {};
  final _generationObservers = <void Function(int, bool)>{};
  void Function() observeGenerationChanges(void Function(int, bool) observer) {
    if (_closed) throw const BridgeDisconnectedException();
    _generationObservers.add(observer);
    return () => _generationObservers.remove(observer);
  }

  SharedAccountRead? _accountRead;
  late final _friendsReads = SharedFriendsReads(
    (name, payload, owner, progress) => _beginUnsharedRequest(
      name,
      payload: payload,
      accountContext: owner,
      displayProgress: progress,
      consumerTimed: true,
    ),
    _pending.containsKey,
  );
  final StreamController<BridgeEnvelope> _events =
      StreamController<BridgeEnvelope>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;

  int _activeGeneration;
  int _highestEventSequence = -1;
  bool _closed = false;
  Future<void>? _closing, _networkExit;

  int get activeGeneration => _activeGeneration;
  bool get isClosed => _closed;
  Set<String> _hostCapabilities = const {};
  Set<String> get hostCapabilities => _hostCapabilities;
  final _capabilitiesChanged = StreamController<void>.broadcast();
  Stream<void> get capabilitiesChanged => _capabilitiesChanged.stream;
  Future<void> Function()? _refreshCapabilities;
  void Function()? _retireCapabilities;
  void Function() registerHostCapabilityRefresh({
    required Future<void> Function() refresh,
    required void Function() retire,
  }) {
    if (_closed || _refreshCapabilities != null) {
      throw StateError('Host refresh already bound');
    }
    _refreshCapabilities = refresh;
    _retireCapabilities = retire;
    return () {
      if (identical(_refreshCapabilities, refresh)) {
        _refreshCapabilities = null;
        _retireCapabilities = null;
      }
    };
  }

  final _connectionModeNetwork = <ConnectionModeNetworkWork>{};
  int _modeChanges = 0;
  int _modeRevision = 0;
  int get connectionModeRevision => _modeRevision;
  bool get connectionModeChanging => _closed || _modeChanges != 0;
  void Function() registerConnectionModeNetworkWork(
    ConnectionModeNetworkWork work,
  ) {
    if (_closed) throw const BridgeDisconnectedException();
    _connectionModeNetwork.add(work);
    return () => _connectionModeNetwork.remove(work);
  }

  Future<T> runConnectionModeChange<T>(Future<T> Function() change) async {
    if (_closed) throw const BridgeDisconnectedException();
    _modeChanges++;
    _modeRevision++;
    _friendsReads.retire();
    _retireCapabilities?.call();
    _accountRead?.clearDisplay();
    final generation = _activeGeneration,
        work = _connectionModeNetwork.toList();
    try {
      await Future.wait(work.map((w) => w.pause()));
      if (_closed) throw const BridgeDisconnectedException();
      if (generation != _activeGeneration) {
        throw BridgeStaleGenerationException(generation, _activeGeneration);
      }
      return await change();
    } finally {
      _modeChanges--;
      try {
        await _refreshCapabilities?.call();
      } on Object {
        // A committed mode change is not rolled back by a failed capability
        // read. Retired optional capabilities remain closed until verified.
      }
      // A window opened while draining is denied admission by the session.
      // Include it in reconciliation too; it must not remain paused forever.
      await Future.wait(
        {...work, ..._connectionModeNetwork}.map((participant) async {
          try {
            await participant.reconcile();
          } on Object {
            /* Failed reads cannot grant media admission. */
          }
        }),
      );
    }
  }

  void acceptHostCapabilities(Iterable<String> capabilities) {
    final next = Set<String>.unmodifiable(capabilities);
    final changed =
        next.length != _hostCapabilities.length ||
        !next.containsAll(_hostCapabilities);
    _hostCapabilities = next;
    if (!_hostCapabilities.contains('account.restoreDisplay')) {
      _accountRead?.clearDisplay();
    }
    if (!_closed && changed) _capabilitiesChanged.add(null);
  }

  Stream<BridgeEnvelope> get events => _events.stream;

  Future<BridgeEnvelope> request(
    String name, {
    Map<String, Object?> payload = const {},
    BridgeAccountContext? accountContext,
    Duration? timeout,
  }) {
    return beginRequest(
      name,
      payload: payload,
      accountContext: accountContext,
      timeout: timeout,
    ).future;
  }

  BridgeRequestOperation beginRequest(
    String name, {
    Map<String, Object?> payload = const {},
    BridgeAccountContext? accountContext,
    Duration? timeout,
    void Function(BridgeEnvelope?)? onAccountRestoreDisplay,
    void Function(BridgeEnvelope)? onAccountRestoreResponse,
    BridgeDisplayProgress? displayProgress,
  }) {
    if (_closed) throw const BridgeDisconnectedException();
    if (name == 'account.getCurrent' && displayProgress != null) {
      throw ArgumentError(
        'Account restoration uses its own scoped display observer.',
      );
    }
    if (_friendsReads.boundary(name)) _friendsReads.retire();
    final friendsRead = connectionModeChanging
        ? null
        : _friendsReads.begin(
            name,
            payload,
            accountContext,
            timeout ?? _requestTimeout,
            displayProgress,
          );
    if (friendsRead != null) {
      LoadingMetrics.current?.observe(
        name,
        friendsRead.future,
        transport: false,
      );
      return friendsRead;
    }
    // Only coalesce identical in-flight snapshots. Do not cache credentials,
    // completed results or writes. Each consumer owns its full deadline;
    // a short-lived caller must not cancel a longer-lived caller's snapshot.
    // Subscribers below own cancellation independently of the shared transport.
    if (name == 'account.getCurrent' &&
        accountContext == null &&
        payload.length == 1 &&
        payload['schemaVersion'] is int &&
        payload['schemaVersion'] == 1) {
      var shared = _accountRead;
      if (shared == null) {
        late final SharedAccountRead created;
        created = SharedAccountRead(
          _beginUnsharedRequest(
            name,
            payload: {
              ...payload,
              if (onAccountRestoreDisplay != null &&
                  _hostCapabilities.contains('account.restoreDisplay'))
                'restoreDisplayProgress': true,
            },
            consumerTimed: true,
          ),
          () {
            if (identical(_accountRead, created)) _accountRead = null;
          },
          onAccountRestoreDisplay != null &&
              _hostCapabilities.contains('account.restoreDisplay'),
        );
        _accountRead = shared = created;
      }
      final operation = shared.subscribe(
        timeout ?? _requestTimeout,
        onAccountRestoreDisplay,
        onAccountRestoreResponse,
      );
      LoadingMetrics.current?.observe(name, operation.future, transport: false);
      return operation;
    }
    // An account operation is an ordering boundary, even before its generation
    // change arrives. A later reader must not join the earlier snapshot.
    // Read-only cached display can run within the same unfinished root read.
    SharedAccountRead? retired;
    if (name.startsWith('account.') &&
        name != 'account.offlineData.read' &&
        name != 'account.scmRouteRead' &&
        name != 'account.scmRouteSave') {
      retired = _accountRead;
      _accountRead = null;
    }
    final BridgeRequestOperation operation;
    try {
      operation = _beginUnsharedRequest(
        name,
        payload: payload,
        accountContext: accountContext,
        timeout: timeout,
        displayProgress: displayProgress,
      );
    } finally {
      retired?.clearDisplay();
    }
    LoadingMetrics.current?.observe(name, operation.future, transport: false);
    return operation;
  }

  BridgeRequestOperation _beginUnsharedRequest(
    String name, {
    Map<String, Object?> payload = const {},
    BridgeAccountContext? accountContext,
    Duration? timeout,
    bool consumerTimed = false,
    BridgeDisplayProgress? displayProgress,
  }) {
    if (_closed) {
      throw const BridgeDisconnectedException();
    }
    BridgeRequestPolicy.requireAccountContext(name, accountContext);

    final correlationId = _correlationIdFactory();
    if (correlationId.isEmpty || _pending.containsKey(correlationId)) {
      throw StateError('Bridge correlation ID must be non-empty and unique.');
    }
    final generation = _activeGeneration;
    final completion = Completer<BridgeEnvelope>();
    final timer = consumerTimed
        ? null
        : Timer(timeout ?? _requestTimeout, () {
            final pending = _pending.remove(correlationId);
            if (pending == null) {
              return;
            }
            pending.completion.completeError(
              BridgeTimeoutException(name),
              StackTrace.current,
            );
            unawaited(_sendCancellation(correlationId, generation));
          });
    _pending[correlationId] = _PendingRequest(
      name: name,
      generation: generation,
      completion: completion,
      timer: timer,
      displayProgress: displayProgress,
    );

    final envelope = BridgeEnvelope(
      protocolVersion: BridgeProtocol.currentVersion,
      messageType: 'request',
      name: name,
      correlationId: correlationId,
      sessionGeneration: generation,
      accountContext: accountContext,
      payload: payload,
    );
    LoadingMetrics.current?.observe(name, completion.future, transport: true);
    unawaited(_send(envelope, correlationId));
    return BridgeRequestOperation(
      completion.future,
      () => _cancel(correlationId),
      correlationId: correlationId,
    );
  }

  void advanceGeneration(int nextGeneration) =>
      _advanceGeneration(nextGeneration);

  void _advanceGeneration(int nextGeneration, {bool fromAccountEvent = false}) {
    if (nextGeneration <= _activeGeneration) {
      throw ArgumentError.value(
        nextGeneration,
        'nextGeneration',
        'must increase monotonically',
      );
    }
    final previous = _activeGeneration;
    _friendsReads.retire();
    final retired = _accountRead;
    _accountRead = null;
    _activeGeneration = nextGeneration;
    _highestEventSequence = -1;
    final stale = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final observer in _generationObservers.toList()) {
      observer(nextGeneration, fromAccountEvent);
    }
    retired?.clearDisplay();
    for (final entry in stale) {
      entry.value.timer?.cancel();
      entry.value.completion.completeError(
        BridgeStaleGenerationException(previous, nextGeneration),
        StackTrace.current,
      );
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _generationObservers.clear();
    _failPending(const BridgeDisconnectedException());
    await (_networkExit ??= _pauseConnectionModeNetwork());
    await _subscription.cancel();
    await _connection.close();
    await _events.close();
    await _capabilitiesChanged.close();
  }

  Future<void> _pauseConnectionModeNetwork() =>
      Future.wait(_connectionModeNetwork.toList().map((work) => work.pause()));

  Future<void> _send(BridgeEnvelope envelope, String correlationId) async {
    try {
      await _connection.send(envelope);
    } catch (error, stackTrace) {
      final pending = _pending.remove(correlationId);
      if (pending == null) {
        return;
      }
      pending.timer?.cancel();
      pending.completion.completeError(
        const BridgeDisconnectedException(),
        stackTrace,
      );
    }
  }

  Future<void> _cancel(String correlationId) async {
    final pending = _pending.remove(correlationId);
    if (pending == null) {
      return;
    }
    if (_accountRead?.operation.correlationId == correlationId) {
      final retired = _accountRead;
      _accountRead = null;
      retired?.clearDisplay();
    }
    pending.timer?.cancel();
    pending.completion.completeError(
      BridgeCancelledException(pending.name),
      StackTrace.current,
    );
    await _sendCancellation(correlationId, pending.generation);
  }

  Future<void> _sendCancellation(
    String targetCorrelationId,
    int generation,
  ) async {
    if (_closed) {
      return;
    }
    try {
      await _connection.send(
        BridgeEnvelope(
          protocolVersion: BridgeProtocol.currentVersion,
          messageType: 'request',
          name: 'bridge.cancel',
          correlationId: _correlationIdFactory(),
          sessionGeneration: generation,
          payload: {'targetCorrelationId': targetCorrelationId},
        ),
      );
    } catch (_) {
      // Cancellation delivery is explicitly best effort.
    }
  }

  void _handleIncoming(BridgeEnvelope envelope) {
    try {
      envelope.requireCurrentVersion();
      if (envelope.messageType == 'response') {
        _handleResponse(envelope);
      } else if (envelope.messageType == 'event') {
        _handleEvent(envelope);
      }
    } on Object catch (error, stackTrace) {
      _handleTerminalError(error, stackTrace);
    }
  }

  void _handleResponse(BridgeEnvelope envelope) {
    if (envelope.sessionGeneration != _activeGeneration) {
      return;
    }
    final correlationId = envelope.correlationId;
    if (correlationId == null) {
      return;
    }
    final pending = _pending.remove(correlationId);
    if (pending == null) {
      return;
    }
    _friendsReads.completed(pending.name, envelope);
    if (_accountRead?.operation.correlationId == correlationId) {
      final retired = _accountRead;
      _accountRead = null;
      if (pending.generation == envelope.sessionGeneration) {
        retired?.completeDisplay(envelope);
      }
      retired?.clearDisplay();
    }
    pending.timer?.cancel();
    if (pending.generation != envelope.sessionGeneration) {
      pending.completion.completeError(
        BridgeStaleGenerationException(pending.generation, _activeGeneration),
        StackTrace.current,
      );
      return;
    }
    switch (envelope.status) {
      case 'ok':
        pending.completion.complete(envelope);
      case 'cancelled':
        pending.completion.completeError(
          BridgeCancelledException(pending.name),
          StackTrace.current,
        );
      case 'error':
        final error = envelope.error;
        pending.completion.completeError(
          BridgeRemoteException(
            error?.code ?? 'bridge.invalid_envelope',
            retryable: error?.retryable ?? false,
          ),
          StackTrace.current,
        );
    }
  }

  void _handleEvent(BridgeEnvelope envelope) {
    if (envelope.name == 'account.changed' &&
        envelope.sessionGeneration > _activeGeneration) {
      _advanceGeneration(envelope.sessionGeneration, fromAccountEvent: true);
    }
    if (envelope.sessionGeneration != _activeGeneration) {
      return;
    }
    final sequence = envelope.sequence ?? -1;
    if (sequence <= _highestEventSequence) {
      return;
    }
    _highestEventSequence = sequence;
    _friendsReads.event(envelope.name);
    if (envelope.name == 'account.changed' ||
        envelope.name == 'bootstrap.invalidated') {
      final retired = _accountRead;
      _accountRead = null;
      retired?.clearDisplay();
    }
    if (envelope.name == 'account.restoreDisplay') {
      final root = _pending[envelope.payload['rootCorrelationId']];
      if (root?.name == 'account.getCurrent' &&
          root?.generation == _activeGeneration) {
        _accountRead?.publishDisplay(envelope);
      }
    }
    final id = envelope.payload['requestCorrelationId'];
    final pending = id is String ? _pending[id] : null;
    final progress = pending?.displayProgress;
    if (progress != null &&
        progress.eventName == envelope.name &&
        pending!.generation == _activeGeneration &&
        envelope.accountContext == null &&
        envelope.payload['schemaVersion'] is int &&
        envelope.payload['schemaVersion'] == 1) {
      try {
        progress.accept(envelope);
      } on Object {
        // Optional presentation must not fail the authoritative request.
      }
    }
    _events.add(envelope);
  }

  void _handleTerminalError(Object error, [StackTrace? stackTrace]) {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_networkExit ??= _pauseConnectionModeNetwork());
    _failPending(
      error is BridgeClientException
          ? error
          : const BridgeDisconnectedException(),
      stackTrace,
    );
    unawaited(_events.close());
    unawaited(_capabilitiesChanged.close());
  }

  void _handleDone() => _handleTerminalError(
    const BridgeDisconnectedException(),
    StackTrace.current,
  );

  void _failPending(Object error, [StackTrace? stackTrace]) {
    _friendsReads.retire();
    final retired = _accountRead;
    _accountRead = null;
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    retired?.clearDisplay();
    for (final pending in entries) {
      pending.timer?.cancel();
      pending.completion.completeError(error, stackTrace ?? StackTrace.current);
    }
  }

  static BridgeCorrelationIdFactory _createDefaultCorrelationIdFactory() {
    var correlationCounter = 0;
    return () {
      correlationCounter++;
      return '${DateTime.now().microsecondsSinceEpoch}-${correlationCounter.toRadixString(16)}';
    };
  }
}

abstract final class BridgeRequestPolicy {

  static void requireAccountContext(
    String requestName,
    BridgeAccountContext? context,
  ) {
    if (!accountAgnosticRequests.contains(requestName) && context == null) {
      throw BridgeAccountContextRequiredException(requestName);
    }
  }
}

final class _PendingRequest {
  const _PendingRequest({
    required this.name,
    required this.generation,
    required this.completion,
    required this.timer,
    this.displayProgress,
  });

  final String name;
  final int generation;
  final Completer<BridgeEnvelope> completion;
  final Timer? timer;
  final BridgeDisplayProgress? displayProgress;
}
