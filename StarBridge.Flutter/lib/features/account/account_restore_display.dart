import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_payload_decoder.dart';

/// Optional presentation during an unfinished root read. Never an auth snapshot.
abstract interface class AccountRestoreDisplayPort {
  ValueListenable<AccountProjection?> get restoreDisplay;
}

final class AccountRestoreDisplay extends ValueNotifier<AccountProjection?> {
  AccountRestoreDisplay(this._session) : super(null) {
    try {
      _unobserveGeneration = _session.observeGenerationChanges((
        generation,
        accountEvent,
      ) {
        if (!accountEvent ||
            _handoff?.generation != generation ||
            _transitionAccepted) {
          withdraw();
        }
      });
      _unregister = _session.registerConnectionModeNetworkWork(
        ConnectionModeNetworkWork(
          pause: () async => withdraw(),
          reconcile: () async {},
        ),
      );
    } on BridgeDisconnectedException {
      _unobserveGeneration();
    }
  }
  final BridgeClientSession _session;
  void Function() _unregister = () {};
  void Function() _unobserveGeneration = () {};
  final _operations = <BridgeRequestOperation>{};
  AccountDisplayHandoff? _handoff;
  Completer<bool>? _generationReady;
  bool _transitionAccepted = false;
  int _epoch = 0;
  bool _disposed = false;

  void withdraw() {
    if (_disposed) return;
    ++_epoch;
    _finishGenerationWait(false);
    _handoff = null;
    _transitionAccepted = false;
    value = null;
  }

  void _finishGenerationWait(bool accepted) {
    final ready = _generationReady;
    if (ready != null && !ready.isCompleted) ready.complete(accepted);
  }

  AccountProjection _presentation(
    AccountProjection display,
    int generation,
    AccountDisplayHandoff handoff,
  ) => AccountProjection(
    sessionState: AccountSessionState.loading,
    operation: AccountOperation.refreshing,
    generation: generation,
    profile: display.profile,
    profileFreshness: AccountProfileFreshness.cached,
    cachedAt: display.cachedAt,
    preparingDisplay: true,
    displayHandoff: handoff,
    identity: const AccountIdentityProjection.unavailable(),
    compatibility: const AccountCompatibilityProjection.unavailable(),
    localeOptions: const [],
    timeZoneOptions: const [],
  );

  void observeEvent(BridgeEnvelope event) {
    final handoff = _handoff, display = value;
    if (handoff == null || display == null) return;
    if (event.name == 'bootstrap.invalidated') {
      withdraw();
    } else if (event.name == 'account.changed') {
      if (!_transitionAccepted &&
          event.sessionGeneration == handoff.generation &&
          _session.activeGeneration == handoff.generation &&
          event.payload['schemaVersion'] is int &&
          event.payload['schemaVersion'] == 1) {
        _transitionAccepted = true;
        _finishGenerationWait(true);
        value = _presentation(display, handoff.generation, handoff);
      } else {
        withdraw();
      }
    }
  }

  void confirmSnapshot(AccountHostSnapshot snapshot) {
    if (_handoff != null && !_handoff!.matches(snapshot)) withdraw();
  }

  void _observeResponse(BridgeEnvelope response, int generation, int epoch) {
    if (_disposed || epoch != _epoch) return;
    final display = value;
    if (display == null) return;
    final owner = response.accountContext;
    if (response.status != 'ok' ||
        response.payload['schemaVersion'] is! int ||
        response.payload['schemaVersion'] != 1 ||
        response.payload['state'] != 'signedIn' ||
        owner == null) {
      withdraw();
      return;
    }
    final route = AccountRoute(
      environment: owner.environment,
      authority: owner.authority,
      subject: owner.subject,
    );
    if (!route.isComplete) {
      withdraw();
      return;
    }
    final existing = _handoff;
    if (existing != null) {
      if (generation != existing.generation || !existing.matchesRoute(route)) {
        withdraw();
      }
      return;
    }
    final id = display.retainedReadId;
    if (id == null ||
        response.payload['restoreDisplayReadId'] != id ||
        response.sessionGeneration != generation ||
        generation != display.generation) {
      return;
    }
    final handoff = AccountDisplayHandoff(
      displayKey: id,
      sourceGeneration: generation,
      route: route,
    );
    _handoff = handoff;
    _generationReady = Completer<bool>();
    value = _presentation(display, generation, handoff);
  }

  Future<BridgeEnvelope> read(
    Duration timeout, {
    void Function(BridgeEnvelope)? onResponse,
  }) {
    if (_disposed) throw const BridgeDisconnectedException();
    _finishGenerationWait(false);
    final epoch = ++_epoch;
    final generation = _session.activeGeneration;
    Future<bool>? generationReady;
    final operation = _session.beginRequest(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: timeout,
      onAccountRestoreDisplay: (frame) {
        if (_disposed || epoch != _epoch) return;
        if (frame == null) {
          if (_handoff == null) value = null;
          return;
        }
        try {
          if (frame.messageType != 'event' ||
              frame.name != 'account.restoreDisplay' ||
              frame.sessionGeneration != generation ||
              generation != _session.activeGeneration ||
              frame.payload['schemaVersion'] is! int ||
              frame.payload['schemaVersion'] != 1 ||
              frame.payload.keys.any(
                (key) => !const {
                  'schemaVersion',
                  'rootCorrelationId',
                  'retainedDisplay',
                }.contains(key),
              )) {
            return;
          }
          final display = AccountPayloadDecoder.retainedDisplay(
            frame,
            AccountSessionState.credentialTemporarilyUnavailable,
          );
          if (display?.readId == null) return;
          value = AccountProjection(
            sessionState: AccountSessionState.loading,
            operation: AccountOperation.refreshing,
            generation: generation,
            profile: display!.profile,
            profileFreshness: AccountProfileFreshness.cached,
            cachedAt: display.cachedAt,
            retainedReadId: display.readId,
            retainedPreviousReadId: display.previousReadId,
            preparingDisplay: true,
            identity: const AccountIdentityProjection.unavailable(),
            compatibility: const AccountCompatibilityProjection.unavailable(),
            localeOptions: const [],
            timeZoneOptions: const [],
          );
        } on BridgeFormatException {
          // Malformed progress must never complete or fail authentication.
        }
      },
      onAccountRestoreResponse: (response) {
        if (!_disposed && epoch == _epoch) onResponse?.call(response);
        _observeResponse(response, generation, epoch);
        if (_handoff?.sourceGeneration == generation) {
          generationReady = _generationReady?.future;
        }
      },
    );
    _operations.add(operation);
    return operation.future
        .then((response) async {
          final ready = generationReady;
          if (ready != null) {
            // The transport may deliver the queued event in a later batch. The
            // response proves continuity, not that its old context is usable now.
            final accepted = await ready.timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                if (epoch == _epoch) withdraw();
                throw const BridgeTimeoutException('account.changed');
              },
            );
            if (!accepted || _disposed || epoch != _epoch) {
              throw const BridgeCancelledException('account.getCurrent');
            }
          }
          return response;
        })
        .whenComplete(() {
          _operations.remove(operation);
        });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finishGenerationWait(false);
    _unregister();
    _unobserveGeneration();
    ++_epoch;
    for (final operation in _operations.toList()) {
      operation.cancel();
    }
    _operations.clear();
    super.dispose();
  }
}
