import 'package:flutter/foundation.dart';

final class ContinuousPlayValue {
  const ContinuousPlayValue({
    required this.enabled,
    required this.firstMinutes,
    required this.repeatMinutes,
    required this.revision,
  });
  final bool enabled;
  final int firstMinutes;
  final int repeatMinutes;
  final int revision;
}

abstract interface class ContinuousPlayPort {
  Future<ContinuousPlayValue> read();
  Future<ContinuousPlayValue> save(ContinuousPlayValue desired);
}

final class ContinuousPlayView {
  const ContinuousPlayView({
    this.settings,
    this.busy = false,
    this.failed = false,
  });
  final ContinuousPlayValue? settings;
  final bool busy;
  final bool failed;
}

/// Independent local reminder settings, not a second cumulative-playtime controller.
final class ContinuousPlayController extends ValueNotifier<ContinuousPlayView> {
  ContinuousPlayController(this._port) : super(const ContinuousPlayView());
  final ContinuousPlayPort _port;
  bool _disposed = false;
  Future<bool> refresh() => _run(null);
  Future<bool> save({
    required bool enabled,
    required int firstMinutes,
    required int repeatMinutes,
  }) {
    final current = value.settings;
    if (current == null) return Future.value(false);
    return _run(
      ContinuousPlayValue(
        enabled: enabled,
        firstMinutes: firstMinutes,
        repeatMinutes: repeatMinutes,
        revision: current.revision,
      ),
    );
  }

  Future<bool> _run(ContinuousPlayValue? desired) async {
    if (_disposed || value.busy) return false;
    final previous = value.settings;
    value = ContinuousPlayView(settings: previous, busy: true);
    try {
      final settings = desired == null
          ? await _port.read()
          : await _port.save(desired);
      if (_disposed) return false;
      value = ContinuousPlayView(settings: settings);
      return true;
    } on Object {
      if (!_disposed) {
        value = ContinuousPlayView(settings: previous, failed: true);
      }
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
