import 'dart:async';

import 'bridge_connection.dart';
import 'bridge_envelope.dart';

typedef BridgeCorrelationIdFactory = String Function();

final class BridgeRequestOperation {
  BridgeRequestOperation._(this.future, this._cancel, {this.correlationId});

  final Future<BridgeEnvelope> future;
  final String? correlationId;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

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
  _SharedAccountRead? _accountRead;
  final StreamController<BridgeEnvelope> _events =
      StreamController<BridgeEnvelope>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;

  int _activeGeneration;
  int _highestEventSequence = -1;
  bool _closed = false;

  int get activeGeneration => _activeGeneration;
  Set<String> _hostCapabilities = const {};
  Set<String> get hostCapabilities => _hostCapabilities;

  void acceptHostCapabilities(Iterable<String> capabilities) {
    _hostCapabilities = Set.unmodifiable(capabilities);
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
  }) {
    if (_closed) throw const BridgeDisconnectedException();
    // Only coalesce identical in-flight snapshots. Do not cache credentials,
    // completed results, writes or custom deadlines.
    // Subscribers below own cancellation independently of the shared transport.
    if (name == 'account.getCurrent' &&
        accountContext == null &&
        timeout == null &&
        payload.length == 1 &&
        payload['schemaVersion'] is int &&
        payload['schemaVersion'] == 1) {
      var shared = _accountRead;
      if (shared == null) {
        late final _SharedAccountRead created;
        created = _SharedAccountRead(
          _beginUnsharedRequest(name, payload: payload),
          () {
            if (identical(_accountRead, created)) _accountRead = null;
          },
        );
        _accountRead = shared = created;
      }
      return shared.subscribe();
    }
    // An account operation is an ordering boundary, even before its generation
    // change arrives. A later reader must not join the earlier snapshot.
    if (name.startsWith('account.')) _accountRead = null;
    return _beginUnsharedRequest(
      name,
      payload: payload,
      accountContext: accountContext,
      timeout: timeout,
    );
  }

  BridgeRequestOperation _beginUnsharedRequest(
    String name, {
    Map<String, Object?> payload = const {},
    BridgeAccountContext? accountContext,
    Duration? timeout,
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
    final timer = Timer(timeout ?? _requestTimeout, () {
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
    unawaited(_send(envelope, correlationId));
    return BridgeRequestOperation._(
      completion.future,
      () => _cancel(correlationId),
      correlationId: correlationId,
    );
  }

  void advanceGeneration(int nextGeneration) {
    if (nextGeneration <= _activeGeneration) {
      throw ArgumentError.value(
        nextGeneration,
        'nextGeneration',
        'must increase monotonically',
      );
    }
    final previous = _activeGeneration;
    _accountRead = null;
    _activeGeneration = nextGeneration;
    _highestEventSequence = -1;
    final stale = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final entry in stale) {
      entry.value.timer.cancel();
      entry.value.completion.completeError(
        BridgeStaleGenerationException(previous, nextGeneration),
        StackTrace.current,
      );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _failPending(const BridgeDisconnectedException());
    await _subscription.cancel();
    await _connection.close();
    await _events.close();
  }

  Future<void> _send(BridgeEnvelope envelope, String correlationId) async {
    try {
      await _connection.send(envelope);
    } catch (error, stackTrace) {
      final pending = _pending.remove(correlationId);
      if (pending == null) {
        return;
      }
      pending.timer.cancel();
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
    pending.timer.cancel();
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
    pending.timer.cancel();
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
      advanceGeneration(envelope.sessionGeneration);
    }
    if (envelope.sessionGeneration != _activeGeneration) {
      return;
    }
    final sequence = envelope.sequence ?? -1;
    if (sequence <= _highestEventSequence) {
      return;
    }
    _highestEventSequence = sequence;
    if (envelope.name == 'account.changed' ||
        envelope.name == 'bootstrap.invalidated') {
      _accountRead = null;
    }
    _events.add(envelope);
  }

  void _handleTerminalError(Object error, [StackTrace? stackTrace]) {
    if (_closed) {
      return;
    }
    _closed = true;
    _failPending(
      error is BridgeClientException
          ? error
          : const BridgeDisconnectedException(),
      stackTrace,
    );
    unawaited(_events.close());
  }

  void _handleDone() => _handleTerminalError(
    const BridgeDisconnectedException(),
    StackTrace.current,
  );

  void _failPending(Object error, [StackTrace? stackTrace]) {
    _accountRead = null;
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    for (final pending in entries) {
      pending.timer.cancel();
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

/// One transport read with independently cancellable consumers. Never survives
/// completion, invalidation or the last consumer leaving.
final class _SharedAccountRead {
  _SharedAccountRead(this.operation, this.retire) {
    operation.future.then(
      (_) {
        settled = true;
        retire();
      },
      onError: (Object _, StackTrace _) {
        settled = true;
        retire();
      },
    );
  }
  final BridgeRequestOperation operation;
  final void Function() retire;
  int consumers = 0;
  bool settled = false;

  BridgeRequestOperation subscribe() {
    final completion = Completer<BridgeEnvelope>();
    consumers++;
    operation.future.then(
      (value) {
        if (!completion.isCompleted) completion.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      },
    );
    return BridgeRequestOperation._(completion.future, () async {
      if (completion.isCompleted) return;
      completion.completeError(
        const BridgeCancelledException('account.getCurrent'),
        StackTrace.current,
      );
      consumers--;
      if (!settled && consumers == 0) {
        retire();
        await operation.cancel();
      }
    });
  }
}

abstract final class BridgeRequestPolicy {
  static const _accountAgnosticRequests = <String>{
    'host.hello',
    'host.ready',
    'host.getGamePresence',
    'host.shutdown',
    'account.getCurrent',
    'account.sendPasswordResetCode',
    'account.confirmPasswordReset',
    'account.loginLegacy',
    'account.login',
    'account.cancelLogin',
    'applicationPreferences.get',
    'applicationPreferences.update',
    'notificationAudio.read',
    'playerActivity.read',
    'playerActivity.save',
    'playerActivity.test',
    'playReminder.read',
    'playReminder.save',
    'notificationSettings.read',
    'notificationSettings.save',
    'notificationSettings.presentDesktop',
    'notificationSettings.testDesktop',
    'notificationSettings.clearDesktop',
    'notificationSettings.consumeActivation',
    'notificationAudio.save',
    'notificationAudio.preview',
    'notificationAudio.stop',
    'runtime.getSnapshot',
    'overlay.getState',
    'overlay.getWorkspace',
    'overlay.updateWorkspace',
    'overlay.runtime.getState',
    'overlay.runtime.open',
    'overlay.runtime.close',
    'overlay.runtime.retry',
    'overlay.preview',
    'overlay.update',
    'diagnostics.getSafeSummary',
    'diagnostics.openDataDirectory',
    'diagnostics.getDataLocation',
    'diagnostics.clearImageCache',
    'diagnostics.openInstalledApps',
    'diagnostics.flutterInstallation',
    'diagnostics.flutterInstallationExecute',
    'dataLocation.chooseMigration',
    'dataLocation.confirmMigration',
    'dataLocation.getMigrationResult',
    'dataLocation.acknowledgeMigrationResult',
    'legal.getClientLicense',
    'legal.readTestBuildNotice',
    'legal.acceptTestBuildNotice',
    'applicationUpdates.check',
    // Installation/startup belongs to this device, not a signed-in account.
    // Host still validates the receipt nonce and each installation request.
    'applicationUpdates.firstFrameReady',
    'applicationUpdates.prepare',
    'applicationUpdates.handoff',
    'helpSupport.history',
    'helpSupport.stats',
    'helpSupport.feedback',
    'helpSupport.openScm',
    'diagnostics.getRuntimeFacts',
    'diagnostics.getOverlayRuntimeStatus',
    'diagnostics.getLocalEvents',
    'diagnostics.exportLocalEvents',
    'diagnostics.clearLocalEvents',
    'bridge.cancel',
  };

  static void requireAccountContext(
    String requestName,
    BridgeAccountContext? context,
  ) {
    if (!_accountAgnosticRequests.contains(requestName) && context == null) {
      throw BridgeAccountContextRequiredException(requestName);
    }
  }
}

class BridgeClientException implements Exception {
  const BridgeClientException(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  String toString() => 'BridgeClientException($code)';
}

final class BridgeRemoteException extends BridgeClientException {
  const BridgeRemoteException(super.code, {super.retryable});
}

final class BridgeAccountContextRequiredException
    extends BridgeClientException {
  const BridgeAccountContextRequiredException(this.requestName)
    : super('bridge.account_context_required');

  final String requestName;
}

final class BridgeTimeoutException extends BridgeClientException {
  const BridgeTimeoutException(this.requestName)
    : super('bridge.timeout', retryable: true);

  final String requestName;
}

final class BridgeCancelledException extends BridgeClientException {
  const BridgeCancelledException(this.requestName) : super('bridge.cancelled');

  final String requestName;
}

final class BridgeDisconnectedException extends BridgeClientException {
  const BridgeDisconnectedException()
    : super('bridge.disconnected', retryable: true);
}

final class BridgeStaleGenerationException extends BridgeClientException {
  const BridgeStaleGenerationException(
    this.requestGeneration,
    this.activeGeneration,
  ) : super('bridge.stale_generation');

  final int requestGeneration;
  final int activeGeneration;
}

final class _PendingRequest {
  const _PendingRequest({
    required this.name,
    required this.generation,
    required this.completion,
    required this.timer,
  });

  final String name;
  final int generation;
  final Completer<BridgeEnvelope> completion;
  final Timer timer;
}
