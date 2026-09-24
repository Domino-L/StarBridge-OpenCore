import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

/// One editor transaction; domain writes remain independently acknowledged.
class PrivacyPageDrafts extends ChangeNotifier {
  final _entries = <String, _Draft>{};
  bool saving = false;
  bool failed = false;
  int _epoch = 0;
  bool _disposed = false;
  void _notify() { if (!_disposed) notifyListeners(); }
  bool get dirty => _entries.isNotEmpty;
  int get epoch => _epoch;

  T value<T>(String key, T saved) =>
      _entries.containsKey(key) ? _entries[key]!.value as T : saved;

  void edit<T>(String key, T saved, T next, Future<bool> Function(T) commit) {
    if (saving || _disposed) return;
    if (next == saved ||
        next is Map && saved is Map && mapEquals(next, saved)) {
      _entries.remove(key);
    } else {
      _entries[key] = _Draft(next, () => commit(next));
    }
    failed = false;
    _notify();
  }

  void discard() {
    _epoch++;
    _entries.clear();
    failed = false;
    _notify();
  }

  Future<bool> save() async {
    if (saving || _disposed) return false;
    final epoch = _epoch;
    saving = true;
    failed = false;
    _notify();
    try {
      for (final item in _entries.entries.toList()) {
        if (_epoch != epoch) return false;
        bool ok;
        try {
          ok = await item.value.commit();
        } catch (_) {
          ok = false;
        }
        if (_epoch != epoch) return false;
        if (ok) {
          _entries.remove(item.key);
        } else {
          failed = true;
        }
      }
      return !dirty;
    } finally {
      saving = false;
      _notify();
    }
  }
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _entries.clear();
    super.dispose();
  }
}

class _Draft {
  const _Draft(this.value, this.commit);
  final Object? value;
  final Future<bool> Function() commit;
}

class PrivacyDraftScope extends InheritedNotifier<PrivacyPageDrafts> {
  const PrivacyDraftScope({
    required PrivacyPageDrafts drafts,
    required super.child,
    super.key,
  }) : super(notifier: drafts);
  static PrivacyPageDrafts? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrivacyDraftScope>()?.notifier;
}
