import 'package:flutter/foundation.dart';

import 'exec_hangar_port.dart';

final class ExecHangarView {
  const ExecHangarView({this.snapshot, this.busy = false, this.failed = false});
  final ExecHangarSnapshot? snapshot;
  final bool busy, failed;
}

final class ExecHangarController extends ValueNotifier<ExecHangarView> {
  ExecHangarController(this.port, {ExecHangarSnapshot? initialSnapshot})
    : super(ExecHangarView(snapshot: initialSnapshot));
  final ExecHangarPort port;
  bool _disposed = false;
  Future<bool> read({bool refresh = false}) =>
      _run(() => port.read(refresh: refresh));
  Future<bool> save(ExecHangarReminders reminders, {int? expectedRevision}) {
    final revision = expectedRevision ?? value.snapshot?.revision;
    return revision == null
        ? Future.value(false)
        : _run(() => port.save(reminders, revision));
  }

  Future<bool> _run(Future<ExecHangarSnapshot> Function() action) async {
    if (_disposed || value.busy) return false;
    final previous = value.snapshot;
    value = ExecHangarView(snapshot: previous, busy: true);
    try {
      final snapshot = await action();
      if (_disposed) return false;
      value = ExecHangarView(snapshot: snapshot);
      return true;
    } catch (_) {
      if (!_disposed) value = ExecHangarView(snapshot: previous, failed: true);
      return false;
    }
  }

  Future<bool> monitor(
    ExecHangarAction action, {
    int durationMinutes = 60,
    bool onlyNext = false,
  }) {
    final revision = value.snapshot?.revision;
    return revision == null
        ? Future.value(false)
        : _run(
            () => port.monitor(
              action,
              revision,
              durationMinutes: durationMinutes,
              onlyNext: onlyNext,
            ),
          );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
