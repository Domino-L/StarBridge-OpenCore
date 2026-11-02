import 'dart:async';

/// A short-lived scheduling hint. It grants no data or action capability.
final class WindowMessageHealth {
  WindowMessageHealth({int Function()? utcNowMilliseconds})
    : _utcNowMilliseconds = utcNowMilliseconds ?? _systemClock;
  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;
  final int Function() _utcNowMilliseconds;
  static const leaseMilliseconds = 3000;
  int _opening = 0, _revision = -1;
  String _scope = '';
  bool _healthy = false, _closed = false;
  Timer? _expiry;
  bool get healthy => !_closed && _healthy;

  void bind(int opening, String scope) {
    if (_closed || (_opening == opening && _scope == scope)) return;
    _expiry?.cancel();
    _healthy = false;
    _revision = -1;
    _opening = opening;
    _scope = scope;
  }

  bool accept(Object? packet) {
    if (_closed ||
        packet is! Map ||
        packet.length != 6 ||
        _opening < 1 ||
        _scope.isEmpty ||
        _scope.length > 128 ||
        packet['opening'] != _opening ||
        packet['scope'] != _scope ||
        packet['healthy'] is! bool ||
        packet['revision'] is! int ||
        (packet['revision'] as int) < 0 ||
        (packet['revision'] as int) <= _revision ||
        packet['leaseMilliseconds'] != leaseMilliseconds ||
        packet['sentAtUtcMilliseconds'] is! int) {
      return false;
    }
    final age =
        _utcNowMilliseconds() - (packet['sentAtUtcMilliseconds'] as int);
    if (age < 0 || age >= leaseMilliseconds) return false;
    _revision = packet['revision'] as int;
    _expiry?.cancel();
    _healthy = packet['healthy'] as bool;
    if (_healthy) {
      _expiry = Timer(Duration(milliseconds: leaseMilliseconds - age), () {
        _healthy = false;
      });
    }
    return true;
  }

  void dispose() {
    _closed = true;
    _healthy = false;
    _expiry?.cancel();
  }
}
