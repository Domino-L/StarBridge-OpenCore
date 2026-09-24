import 'package:flutter/foundation.dart';

import 'local_hangar_port.dart';

/// Confirmation and uncertain-result recovery for one immutable Host scan.
final class LocalHangarSaveModule extends ChangeNotifier {
  LocalHangarSaveModule(this.port, this.operationId, this.shipCount);
  final LocalHangarPort port;
  final String operationId;
  final int shipCount;
  LocalHangarSnapshot? current;
  String phase = 'loading';
  String? error;
  bool _disposed = false;
  int _epoch = 0;
  bool get busy => phase == 'loading' || phase == 'saving';
  bool get canSave => phase == 'ready' && current != null;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || phase == 'saving') return;
    final epoch = ++_epoch;
    phase = 'loading';
    error = null;
    _publish();
    try {
      final result = await port.read();
      if (_disposed || epoch != _epoch) return;
      current = result;
      phase = result.operationId == operationId ? 'saved' : 'ready';
    } on Object catch (failure) {
      if (_disposed || epoch != _epoch) return;
      error = failure is LocalHangarFailure
          ? failure.code
          : 'hangar.storage_read_failed';
      phase = 'error';
    }
    _publish();
  }

  Future<void> save({bool confirmEmpty = false}) async {
    if (!canSave || (shipCount == 0 && !confirmEmpty)) return;
    final epoch = ++_epoch, revision = current!.revision;
    phase = 'saving';
    error = null;
    _publish();
    try {
      final result = await port.save(
        operationId,
        revision,
        confirmEmpty: confirmEmpty,
      );
      if (_disposed || epoch != _epoch) return;
      current = result;
      phase = result.operationId == operationId ? 'saved' : 'uncertain';
    } on LocalHangarFailure catch (failure) {
      if (_disposed || epoch != _epoch) return;
      // An explicit Host rejection did not commit. A transport failure has
      // unknown outcome and must be read back before any further confirmation.
      error = failure.code;
      phase = 'error';
    } on Object {
      if (_disposed || epoch != _epoch) return;
      phase = 'uncertain';
    }
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
