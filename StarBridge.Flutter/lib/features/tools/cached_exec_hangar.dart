import 'exec_hangar_port.dart';

/// Device-local tool state lives with the feature, rather than each page visit.
final class CachedExecHangar
    implements ExecHangarPort, ExecHangarExperiencePort {
  CachedExecHangar(
    this._source, {
    Duration Function()? elapsed,
    DateTime Function()? wallNow,
  }) {
    final clock = Stopwatch()..start();
    _elapsed = elapsed ?? (() => clock.elapsed);
    _wallNow = wallNow ?? DateTime.now;
  }
  final ExecHangarPort _source;
  @override
  Future<ExecHangarSnapshot> preview(
    ExecHangarReminders reminders,
    int minutes,
    bool onlyNext,
  ) => (_source as ExecHangarExperiencePort).preview(
    reminders,
    minutes,
    onlyNext,
  );
  @override
  Future<ExecHangarSnapshot> testReminder() =>
      (_source as ExecHangarExperiencePort).testReminder();
  late final Duration Function() _elapsed;
  late final DateTime Function() _wallNow;
  ExecHangarSnapshot? _snapshot;
  Duration _acceptedElapsed = Duration.zero;
  DateTime? _acceptedWall;
  Future<ExecHangarSnapshot>? _pending;
  bool _pendingRefresh = false;
  int _epoch = 0;

  ExecHangarSnapshot? get snapshot => _snapshot;
  Duration get age => _elapsed() - _acceptedElapsed;
  bool get fresh =>
      _snapshot != null &&
      age < const Duration(minutes: 1) &&
      (_wallNow().difference(_acceptedWall!).inSeconds - age.inSeconds).abs() <=
          2;

  void _accept(ExecHangarSnapshot value) {
    _snapshot = value;
    _acceptedElapsed = _elapsed();
    _acceptedWall = _wallNow();
  }

  @override
  Future<ExecHangarSnapshot> read({bool refresh = false}) {
    if (_pending case final pending?) {
      if (refresh && !_pendingRefresh) {
        return pending.then((_) => read(refresh: true));
      }
      return pending;
    }
    _pendingRefresh = refresh;
    return _pending = _read(_epoch, refresh);
  }

  Future<ExecHangarSnapshot> _read(int epoch, bool refresh) async {
    try {
      final value = await _source.read(refresh: refresh);
      if (epoch == _epoch) _accept(value);
      return _snapshot ?? value;
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  Future<ExecHangarSnapshot> save(
    ExecHangarReminders reminders,
    int revision,
  ) async {
    return _mutate(() => _source.save(reminders, revision));
  }

  @override
  Future<ExecHangarSnapshot> monitor(
    ExecHangarAction action,
    int revision, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) => _mutate(
    () => _source.monitor(
      action,
      revision,
      durationMinutes: durationMinutes,
      onlyNext: onlyNext,
    ),
  );

  Future<ExecHangarSnapshot> _mutate(
    Future<ExecHangarSnapshot> Function() action,
  ) async {
    final epoch = ++_epoch;
    _pending = null;
    final value = await action();
    if (epoch == _epoch) {
      ++_epoch;
      _pending = null;
      _accept(value);
    }
    return value;
  }
}
