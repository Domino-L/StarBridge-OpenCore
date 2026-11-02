import 'menu_overlay_text.dart';
import '../localization/app_strings.dart';

import 'package:flutter/widgets.dart' show Locale;

import 'dart:async';

import '../../platform/window/menu_feature_lease.dart';
import '../../platform/window/menu_read_feedback.dart';

/// Owns current-window command references, freshness, invalidation and reads.
/// Only explicitly built presentation rows/buttons leave the primary engine.
abstract class MenuFeatureSession implements MenuFeatureLease {
  MenuFeatureSession(
    this.publish,
    Stream<void> invalidations, {
    Locale Function()? locale,
  }) : locale = locale ?? _defaultLocale {
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
  static Locale _defaultLocale() => const Locale('zh', 'CN');
  final Locale Function() locale;
  AppStrings get strings => AppStrings.resolve(locale());
  final void Function(Map<String, Object?>) publish;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  bool visible = false, disposed = false, _busy = false, _writing = false;
  int accountEpoch = 0;
  int generation = 0, _serial = 0;
  int _scope = 0;
  String? _rejectedAction;
  final _silentKeys = <String>{};
  bool silentRead = false;
  int _readSerial = 0;
  MenuReadFeedback? _readFeedback;
  void changeScope() {
    _readFeedback = null;
    _scope++;
    _rejectedAction = null;
  }

  final _actions =
      <
        String,
        ({DateTime expires, Future<void> Function(String) run, bool silent})
      >{};
  Map<String, Object?> _view = const {'state': 'loading'};
  /// Owned phrases kept as templates, for re-publication in the current
  /// language. Never hand this to a reader or encoder.
  Map<String, Object?> get templateView => _view;

  /// The published shape: owned phrases resolved, JSON-encodable only.
  Map<String, Object?> get currentView =>
      resolveMenuOverlayValue(_view, strings) as Map<String, Object?>;
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
  Map<String, Object?>? failedWrite() => null;
  Map<String, Object?>? get writingView => null;
  Map<String, Object?> button(
    Object label,
    Future<void> Function(String) run, {
    String? role,
    bool secret = false,
    Object? confirm,
    Object? input,
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
      'role': ?role,
      'secret': secret,
      'confirm': ?confirm,
      'input': ?input,
      'limit': limit,
    };
  }

  bool current(int epoch) => !disposed && visible && epoch == generation;
  bool currentAccount(int epoch) => !disposed && epoch == accountEpoch;
  void emit(Map<String, Object?> view) {
    if (view['rejectedAction'] case final String key) {
      _rejectedAction = key;
    }
    // Cross-window updates may be coalesced. Keep the most recent rejection
    // just like local acceptance, until the editor's scope is retired.
    _view = {
      ...view,
      'readFeedback': _readFeedback?.wire,
      if (_rejectedAction != null) 'rejectedAction': _rejectedAction,
      'scope': 's$_scope',
    };
    if (visible && !disposed) {
      publish(resolveMenuOverlayValue(_view, strings) as Map<String, Object?>);
    }
  }

  @override
  void show(bool value) {
    if (disposed || visible == value) return;
    visible = value;
    _readFeedback = null;
    _view = {..._view, 'readFeedback': null};
    generation++;
    _actions.clear();
    _busy = false;
    cancelRead();
    _timer?.cancel();
    if (value) {
      if (_writing) {
        emit(
          writingView ??
              {
                'state': 'loading',
                'notice': MenuOverlayText('menu.overlay.errors.confirming'),
              },
        );
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
    _readFeedback = silent
        ? null
        : MenuReadFeedback(++_readSerial, currentMenuReadOrigin);
    final epoch = ++generation;
    if (!backgroundReads) _actions.clear();
    _actions.removeWhere(
      (_, action) => !DateTime.now().isBefore(action.expires),
    );
    final retained = readingView;
    if (retained != null && !silent) {
      emit({...retained, 'refreshing': true});
    } else if (!silent) {
      emit({'state': 'loading'});
    }
    try {
      final view = await read().timeout(const Duration(seconds: 12));
      if (current(epoch)) {
        _readFeedback = null;
        emit({'state': 'ready', ...view});
      }
    } on Object catch (error) {
      if (current(epoch)) {
        _readFeedback = null;
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
    if (disposed) return;
    if (!visible) {
      if (_view['chat'] is Map &&
          (_view['chat'] as Map)['outboxVersion'] == 1 &&
          RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key)) {
        _rejectedAction = key;
      }
      return;
    }
    if ((_busy && !backgroundReads) || _writing || value.length > 2048) {
      // A renderer can still be handling the previous frame's enabled button.
      // Reject the handoff explicitly; it must not leave an editor waiting.
      if (!_silentKeys.contains(key) &&
          RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key)) {
        emit({..._view, 'rejectedAction': key});
      }
      return;
    }
    if (key == 'refresh') {
      unawaited(refresh());
      return;
    }
    final action = _actions[key];
    if (action == null || !DateTime.now().isBefore(action.expires)) {
      if (_silentKeys.contains(key)) return;
      emit({
        ..._view,
        if (RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key)) 'rejectedAction': key,
        'notice': MenuOverlayText('menu.overlay.errors.stale'),
      });
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
      _readFeedback = null;
      generation++;
      _busy = false;
      cancelRead();
    }
    _actions.clear();
    unawaited(_run(action.run, value));
  }

  Future<void> _run(Future<void> Function(String) task, String value) async {
    _readFeedback = null;
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
        emit(
          failedWrite() ??
              {
                'state': 'unavailable',
                'notice': MenuOverlayText('menu.overlay.errors.unconfirmed'),
              },
        );
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
