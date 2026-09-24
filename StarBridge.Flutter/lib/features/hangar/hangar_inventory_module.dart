import 'dart:math';

import 'package:flutter/foundation.dart';

import 'hangar_inventory_port.dart';

/// Saved facts and an unconfirmed operation are separate; account changes invalidate late results.
class HangarInventoryModule extends ChangeNotifier {
  HangarInventoryModule(this.port);
  final HangarInventoryPort port;
  String account = 'A', phase = 'idle';
  String? error;
  HangarInventorySnapshot? saved;
  HangarInventoryImport? pending;
  int _epoch = 0;
  bool _disposed = false;
  String? _commitKey, _previewKey, _scenario;
  bool get busy =>
      const {'loading', 'previewing', 'saving', 'checking'}.contains(phase);
  bool get uncertain => phase == 'uncertain';
  String _key() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> selectAccount(String value) async {
    if (busy ||
        uncertain ||
        value == account ||
        !const ['A', 'B'].contains(value)) {
      return;
    }
    _epoch++;
    account = value;
    saved = null;
    pending = null;
    _commitKey = null;
    _previewKey = null;
    _scenario = null;
    await refresh();
  }

  Future<void> refresh() async {
    if (busy || uncertain) return;
    final epoch = _epoch;
    phase = 'loading';
    error = null;
    _emit();
    try {
      final value = await port.read(account);
      if (_current(epoch)) {
        saved = value;
        phase = 'idle';
      }
    } catch (e) {
      if (_current(epoch)) {
        error = _code(e);
        phase = 'failed';
      }
    }
    if (_current(epoch)) _emit();
  }

  Future<void> preview(String scenario) async {
    if (busy || uncertain || saved == null) return;
    final epoch = _epoch;
    phase = 'previewing';
    error = null;
    pending = null;
    if (_scenario != scenario || _previewKey == null) {
      _scenario = scenario;
      _previewKey = _key();
    }
    _emit();
    try {
      final value = await port.preview(
        account,
        scenario,
        _previewKey!,
        saved!.revision,
      );
      if (_current(epoch)) {
        pending = value;
        _commitKey = _key();
        phase = 'preview';
        _previewKey = null;
      }
    } catch (e) {
      if (_current(epoch)) {
        error = _code(e);
        phase = 'failed';
      }
    }
    if (_current(epoch)) _emit();
  }

  void discard() {
    if (busy || uncertain) return;
    pending = null;
    _previewKey = null;
    _commitKey = null;
    phase = 'idle';
    error = null;
    _emit();
  }

  Future<void> save({bool confirmClear = false}) async {
    final preview = pending;
    if (busy || uncertain || preview == null || preview.ambiguous) return;
    if (preview.ships.isEmpty &&
        (saved?.ships.isNotEmpty ?? false) &&
        !confirmClear) {
      error = 'empty_confirmation';
      _emit();
      return;
    }
    final epoch = _epoch;
    phase = 'saving';
    error = null;
    _emit();
    try {
      final value = await port.commit(
        account,
        preview,
        _commitKey!,
        confirmClear,
      );
      if (_current(epoch)) _saved(value);
    } catch (e) {
      if (_current(epoch)) {
        error = _code(e);
        phase =
            const {
              'conflict',
              'expired',
              'ambiguous',
              'empty_confirmation',
              'invalid',
            }.contains(error)
            ? 'failed'
            : 'uncertain';
      }
    }
    if (_current(epoch)) _emit();
  }

  Future<void> checkResult() async {
    if (!uncertain || pending == null) return;
    final epoch = _epoch;
    phase = 'checking';
    error = null;
    _emit();
    try {
      final value = await port.result(account, pending!.id);
      if (_current(epoch)) {
        if (value != null) {
          _saved(value);
        } else {
          phase = 'preview';
        }
      }
    } catch (e) {
      if (_current(epoch)) {
        phase = 'uncertain';
        error = _code(e);
      }
    }
    if (_current(epoch)) _emit();
  }

  void _saved(HangarInventorySnapshot value) {
    saved = value;
    pending = null;
    _commitKey = null;
    phase = 'saved';
    error = null;
  }

  String _code(Object error) =>
      error is HangarInventoryFailure ? error.code : 'unavailable';
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
