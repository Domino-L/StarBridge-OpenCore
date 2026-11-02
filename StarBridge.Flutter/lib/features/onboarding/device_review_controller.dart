import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_review_port.dart';

@immutable
final class DeviceReviewView {
  const DeviceReviewView({
    this.snapshot = const DeviceReviewSnapshot(),
    this.checked = const {},
    this.busy = false,
    this.error = false,
  });
  final DeviceReviewSnapshot snapshot;
  final Set<DeviceReviewSection> checked;
  final bool busy, error;
  bool get canConfirm =>
      !busy &&
      !error &&
      snapshot.state == DeviceReviewState.reviewRequired &&
      snapshot.canReview &&
      checked.length == DeviceReviewSection.values.length;
}

/// UI acknowledgement is ephemeral and cannot set OnboardingFacts readiness.
final class DeviceReviewController extends ValueNotifier<DeviceReviewView> {
  DeviceReviewController(this.port) : super(const DeviceReviewView()) {
    _events = port.invalidations.listen((_) {
      if (_disposed) return;
      _epoch++;
      value = DeviceReviewView(busy: _inFlight);
      if (_inFlight) {
        _pending = true;
      } else {
        unawaited(refresh());
      }
    });
  }
  final DeviceReviewPort port;
  late final StreamSubscription<void> _events;
  int _epoch = 0;
  bool _disposed = false, _inFlight = false, _pending = false;
  void check(DeviceReviewSection section, bool checked) {
    if (_disposed ||
        value.busy ||
        value.error ||
        !value.snapshot.canReview ||
        value.snapshot.state == DeviceReviewState.reviewed) {
      return;
    }
    final next = {...value.checked};
    if (checked) {
      next.add(section);
    } else {
      next.remove(section);
    }
    value = DeviceReviewView(
      snapshot: value.snapshot,
      checked: Set.unmodifiable(next),
    );
  }

  Future<void> refresh() => _request(port.read);
  Future<void> confirm() async {
    if (_disposed || !value.canConfirm) return;
    final key = value.snapshot.reviewKey!;
    final sections = value.checked;
    await _request(() => port.confirm(key, sections), requiresReview: true);
  }

  Future<void> edit(
    DeviceReviewSection section,
    Future<void> Function(DeviceReviewSection) open,
  ) => _request(() async {
    await open(section);
    return port.read();
  });
  Future<void> _request(
    Future<DeviceReviewSnapshot> Function() run, {
    bool requiresReview = false,
  }) async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    final epoch = ++_epoch;
    value = DeviceReviewView(snapshot: value.snapshot, busy: true);
    try {
      final result = await run();
      if (!_disposed && epoch == _epoch) {
        value = DeviceReviewView(
          snapshot: result,
          error: requiresReview && result.state != DeviceReviewState.reviewed,
        );
      }
    } on Object {
      if (!_disposed && epoch == _epoch) {
        value = const DeviceReviewView(error: true);
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
