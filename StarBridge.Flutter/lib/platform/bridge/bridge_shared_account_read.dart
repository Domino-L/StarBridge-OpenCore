import 'dart:async';

import 'bridge_envelope.dart';
import 'bridge_request_operation.dart';

/// One transport read with independently cancellable consumers. Never survives
/// completion, invalidation or the last consumer leaving.
final class SharedAccountRead {
  SharedAccountRead(
    this.operation,
    this.retire,
    this._displayEnabled, {
    this.requestName = 'account.getCurrent',
    this.displayCorrelationKey = 'rootCorrelationId',
  }) {
    operation.future.then(
      (_) {
        settled = true;
        retire();
        clearDisplay();
      },
      onError: (Object _, StackTrace _) {
        settled = true;
        retire();
        clearDisplay();
      },
    );
  }
  final BridgeRequestOperation operation;
  final void Function() retire;
  final String requestName, displayCorrelationKey;
  int consumers = 0;
  bool settled = false;
  BridgeEnvelope? _display;
  bool _displayEnabled;
  final _displayObservers = <_DisplayObserver>{};

  void publishDisplay(BridgeEnvelope frame) {
    if (!_displayEnabled ||
        settled ||
        frame.payload[displayCorrelationKey] != operation.correlationId) {
      return;
    }
    _display = frame;
    for (final observer in _displayObservers.toList()) {
      if (_displayEnabled && !settled && _displayObservers.contains(observer)) {
        observer.progress(frame);
      }
    }
  }

  void clearDisplay() {
    _displayEnabled = false;
    _display = null;
    final observers = _displayObservers.toList();
    _displayObservers.clear();
    for (final observer in observers) {
      observer.progress(null);
    }
  }

  /// Delivered synchronously while handling the response, before the queued
  /// generation event. Never stored as a completed root result.
  void completeDisplay(BridgeEnvelope response) {
    if (!_displayEnabled ||
        settled ||
        response.correlationId != operation.correlationId) {
      return;
    }
    for (final observer in _displayObservers.toList()) {
      if (_displayObservers.contains(observer)) {
        observer.response?.call(response);
      }
    }
  }

  BridgeRequestOperation subscribe(
    Duration timeout,
    void Function(BridgeEnvelope?)? observer,
    void Function(BridgeEnvelope)? responseObserver,
  ) {
    // Every subscription owns its lease, even if callers reuse one callback.
    final displayObserver = observer == null
        ? null
        : _DisplayObserver(observer, responseObserver);
    final completion = Completer<BridgeEnvelope>();
    consumers++;
    if (displayObserver != null) {
      _displayObservers.add(displayObserver);
      if (_display != null) displayObserver.progress(_display);
    }
    late final Timer timer;
    Future<void> leave(BridgeClientException error) async {
      if (completion.isCompleted) return;
      timer.cancel();
      completion.completeError(error, StackTrace.current);
      consumers--;
      final abandoned = !settled && consumers == 0;
      if (abandoned) {
        // Retire before the async cancel so a new caller cannot join an
        // abandoned transport. The producer still receives best-effort cancel.
        settled = true;
        retire();
      }
      if (displayObserver != null &&
          _displayObservers.remove(displayObserver)) {
        displayObserver.progress(null);
      }
      if (abandoned) {
        await operation.cancel();
      }
    }

    timer = Timer(timeout, () {
      unawaited(leave(BridgeTimeoutException(requestName)));
    });
    operation.future.then(
      (value) {
        if (!completion.isCompleted) {
          timer.cancel();
          consumers--;
          completion.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completion.isCompleted) {
          timer.cancel();
          consumers--;
          completion.completeError(error, stack);
        }
      },
    );
    return BridgeRequestOperation(
      completion.future,
      () => leave(BridgeCancelledException(requestName)),
      correlationId: operation.correlationId,
    );
  }
}

final class _DisplayObserver {
  _DisplayObserver(this.progress, this.response);
  final void Function(BridgeEnvelope?) progress;
  final void Function(BridgeEnvelope)? response;
}
