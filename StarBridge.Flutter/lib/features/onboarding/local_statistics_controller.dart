import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_statistics_port.dart';

@immutable
final class LocalStatisticsView {
  const LocalStatisticsView({
    this.snapshot = const LocalStatisticsSnapshot(),
    this.selected,
    this.busy = false,
    this.error = false,
  });
  final LocalStatisticsSnapshot snapshot;
  final bool? selected;
  final bool busy, error;
  bool get canConfirm =>
      !busy && !error && snapshot.canChoose && selected != null;
}

// Selection is a UI draft. Only the actual Host's durable returned choice is
// usable; saving this draft cannot grant aggregate onboarding readiness.
final class LocalStatisticsController
    extends ValueNotifier<LocalStatisticsView> {
  LocalStatisticsController(this.port) : super(const LocalStatisticsView()) {
    _events = port.invalidations.listen((_) {
      if (_disposed) {
        return;
      }
      _epoch++;
      value = LocalStatisticsView(busy: _inFlight);
      if (_inFlight) {
        _pending = true;
      } else {
        unawaited(refresh());
      }
    });
  }
  final LocalStatisticsPort port;
  late final StreamSubscription<void> _events;
  int _epoch = 0;
  bool _disposed = false, _inFlight = false, _pending = false;
  void select(bool allowed) {
    if (_disposed || value.busy || value.error || !value.snapshot.canChoose) {
      return;
    }
    value = LocalStatisticsView(snapshot: value.snapshot, selected: allowed);
  }

  Future<void> refresh() => _request(port.read);
  Future<void> confirm() async {
    if (_disposed || !value.canConfirm) {
      return;
    }
    final allowed = value.selected!;
    final key = value.snapshot.choiceKey!;
    await _request(() => port.confirm(key, allowed), expected: allowed);
  }

  Future<void> _request(
    Future<LocalStatisticsSnapshot> Function() run, {
    bool? expected,
  }) async {
    if (_disposed || _inFlight) {
      return;
    }
    _inFlight = true;
    final epoch = ++_epoch;
    value = LocalStatisticsView(snapshot: value.snapshot, busy: true);
    try {
      final result = await run();
      if (!_disposed && epoch == _epoch) {
        final confirmed =
            result.choiceSaved &&
            result.consent ==
                (expected == true
                    ? LocalStatisticsConsent.allowed
                    : LocalStatisticsConsent.declined);
        value = LocalStatisticsView(
          snapshot: result,
          error: expected != null && !confirmed,
        );
      }
    } on Object {
      if (!_disposed && epoch == _epoch) {
        value = const LocalStatisticsView(error: true);
      }
    } finally {
      _inFlight = false;
      if (!_disposed && _pending) {
        _pending = false;
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_events.cancel());
    super.dispose();
  }
}
