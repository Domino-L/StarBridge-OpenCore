import 'dart:async';

import '../../platform/window/menu_feature_lease.dart';

/// Owns current-window command references, freshness, invalidation and reads.
/// Only explicitly built presentation rows/buttons leave the primary engine.
abstract class MenuFeatureSession implements MenuFeatureLease {
  MenuFeatureSession(this.publish, Stream<void> invalidations) {
    _subscription = invalidations.listen((_) {
      generation++;
      accountEpoch++;
      changeScope();
      _busy = false;
      _writing = false;
      _actions.clear();
      _silentKeys.clear();
      reset();
      if (visible) unawaited(refresh());
    });
  }
  final void Function(Map<String, Object?>) publish;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  bool visible = false, disposed = false, _busy = false, _writing = false;
  int accountEpoch = 0;
  int generation = 0, _serial = 0;
  int _scope = 0;
  final _silentKeys = <String>{};
  bool silentRead = false;
  void changeScope() => _scope++;
  final _actions =
      <
        String,
        ({DateTime expires, Future<void> Function(String) run, bool silent})
      >{};
  Map<String, Object?> _view = const {'state': 'loading'};
  void reset();
  Future<Map<String, Object?>> read();
  Future<void> closePort();
  void cancelRead() {}
  // Chat windows keep reading/searching/navigation usable during network reads.
  // Opt-in only: other feature sessions retain their existing write gates.
  bool get backgroundReads => false;
  Duration get refreshInterval => const Duration(seconds: 15);
  Map<String, Object?>? get readingView => null;
  Map<String, Object?>? failedRead(Object error) => null;
  Map<String, Object?> button(
    String label,
    Future<void> Function(String) run, {
    String? confirm,
    String? input,
    int limit = 128,
    bool silent = false,
  }) {
    final key = 'a${++_serial}';
    if (silent) {
      if (_silentKeys.length >= 1024) _silentKeys.remove(_silentKeys.first);
      _silentKeys.add(key);
    }
    _actions[key] = (
      expires: DateTime.now().add(const Duration(seconds: 30)),
      run: run,
      silent: silent,
    );
    return {
      'key': key,
      'label': label,
      'confirm': ?confirm,
      'input': ?input,
      'limit': limit,
    };
  }

  bool current(int epoch) => !disposed && visible && epoch == generation;
  bool currentAccount(int epoch) => !disposed && epoch == accountEpoch;
  void emit(Map<String, Object?> view) {
    _view = {...view, 'scope': 's$_scope'};
    if (visible && !disposed) publish(_view);
  }

  @override
  void show(bool value) {
    if (disposed || visible == value) return;
    visible = value;
    generation++;
    _actions.clear();
    _busy = false;
    cancelRead();
    _timer?.cancel();
    if (value) {
      if (_writing) {
        emit({'state': 'loading', 'notice': '正在确认上次操作，请稍候。'});
      } else {
        unawaited(refresh());
      }
      _timer = Timer.periodic(refreshInterval, (_) {
        if (!_busy) unawaited(refresh(silent: true));
      });
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (disposed || !visible || _busy || _writing) return;
    _busy = true;
    silentRead = silent;
    final epoch = ++generation;
    if (!backgroundReads) _actions.clear();
    _actions.removeWhere(
      (_, action) => !DateTime.now().isBefore(action.expires),
    );
    final retained = backgroundReads ? readingView : null;
    if (retained != null && !silent) {
      emit({...retained, 'refreshing': true});
    } else if (!silent) {
      emit({'state': 'loading'});
    }
    try {
      final view = await read().timeout(const Duration(seconds: 12));
      if (current(epoch)) emit({'state': 'ready', ...view});
    } on Object catch (error) {
      if (current(epoch)) {
        generation++;
        _busy = false;
        _actions.clear();
        cancelRead();
        emit(failedRead(error) ?? {'state': 'unavailable'});
      }
    } finally {
      if (current(epoch)) _busy = false;
    }
  }

  @override
  void act(String key, String value) {
    if (disposed ||
        !visible ||
        (_busy && !backgroundReads) ||
        _writing ||
        value.length > 2048) {
      return;
    }
    if (key == 'refresh') {
      unawaited(refresh());
      return;
    }
    final action = _actions[key];
    if (action == null || !DateTime.now().isBefore(action.expires)) {
      if (_silentKeys.contains(key)) return;
      emit({..._view, 'notice': '内容已更新，请刷新后重试。'});
      return;
    }
    if (action.silent) {
      _actions.remove(key);
      // Visibility receipts are housekeeping, not a foreground transaction.
      // They neither retire reads nor lock the composer nor trigger a refresh.
      unawaited(
        action
            .run(value)
            .timeout(const Duration(seconds: 10))
            .catchError((Object _) {}),
      );
      return;
    }
    if (_busy) {
      generation++;
      _busy = false;
      cancelRead();
    }
    _actions.clear();
    unawaited(_run(action.run, value));
  }

  Future<void> _run(Future<void> Function(String) task, String value) async {
    _writing = true;
    final account = accountEpoch;
    emit({..._view, 'busy': true});
    var failed = false;
    try {
      await task(value).timeout(const Duration(seconds: 15));
    } on Object {
      failed = true;
      if (currentAccount(account)) {
        generation++;
        _actions.clear();
        emit({'state': 'unavailable', 'notice': '操作结果未确认，请刷新核对，不要重复提交。'});
      }
    } finally {
      if (currentAccount(account)) _writing = false;
    }
    if (!failed && currentAccount(account) && visible) await refresh();
  }

  @override
  void dispose() {
    if (disposed) return;
    show(false);
    disposed = true;
    generation++;
    _timer?.cancel();
    _actions.clear();
    unawaited(_subscription.cancel());
    _silentKeys.clear();
    unawaited(closePort());
  }
}
