import 'dart:async';

import 'package:flutter/foundation.dart';

import 'recognition_check_port.dart';

/// Summary outcome. Only an observed ready read counts as passed; leaving the
/// step any other way is an honest skip, never a pass.
enum RecognitionCheckOutcome { passed, skipped, unavailable }

@immutable
final class RecognitionCheckView {
  const RecognitionCheckView({
    this.snapshot,
    this.loading = false,
    this.error = false,
    this.passed = false,
    this.supported = true,
  });
  final RecognitionCheckSnapshot? snapshot;
  final bool loading, error, passed, supported;

  RecognitionCheckOutcome get outcome => passed
      ? RecognitionCheckOutcome.passed
      : supported
      ? RecognitionCheckOutcome.skipped
      : RecognitionCheckOutcome.unavailable;
}

/// Polls the read-only Host check only while the step is on screen.
final class RecognitionCheckController
    extends ValueNotifier<RecognitionCheckView> {
  RecognitionCheckController(
    this.port, {
    this.interval = const Duration(seconds: 2),
  }) : super(RecognitionCheckView(supported: port.supported));
  final RecognitionCheckPort port;
  final Duration interval;
  Timer? _timer;
  bool _disposed = false, _reading = false;

  bool get polling => _timer != null;

  void start() {
    if (_disposed || _timer != null || !port.supported) return;
    unawaited(_read());
    _timer = Timer.periodic(interval, (_) => unawaited(_read()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _read() async {
    if (_disposed || _reading) return;
    _reading = true;
    if (value.snapshot == null) {
      value = RecognitionCheckView(
        loading: true,
        passed: value.passed,
        supported: value.supported,
      );
    }
    try {
      final snapshot = await port.read();
      if (_disposed) return;
      value = RecognitionCheckView(
        snapshot: snapshot,
        passed: value.passed || snapshot.ready,
        supported: value.supported,
      );
    } on Object {
      if (_disposed) return;
      value = RecognitionCheckView(
        snapshot: value.snapshot,
        error: true,
        passed: value.passed,
        supported: value.supported,
      );
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
