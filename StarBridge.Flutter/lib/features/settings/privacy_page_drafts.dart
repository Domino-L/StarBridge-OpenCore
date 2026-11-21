import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

enum PrivacyDraftConflict {
  savedElsewhere('settings.privacy.suggestion.savedElsewhere'),
  membershipsChanged('settings.privacy.suggestion.membershipsChanged');

  const PrivacyDraftConflict(this.messageKey);
  final String messageKey;
}

/// One editor transaction; domain writes remain independently acknowledged.
class PrivacyPageDrafts extends ChangeNotifier {
  final _entries = <String, _Draft>{};
  final _conflicts = <String, PrivacyDraftConflict>{};
  bool saving = false;
  bool failed = false;
  bool saveConflicted = false;
  int _epoch = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get dirty => _entries.isNotEmpty;
  int get epoch => _epoch;

  T value<T>(String key, T saved) =>
      _entries.containsKey(key) ? _entries[key]!.value as T : saved;

  /// Facts captured by an edit, retained only while its entry is pending.
  T? basis<T>(String key) => _entries[key]?.basis as T?;

  PrivacyDraftConflict? conflict(String key) => _conflicts[key];

  void edit<T>(
    String key,
    T saved,
    T next,
    Future<bool> Function(T) commit, {
    Object? basis,
    PrivacyDraftConflict? Function(T)? checkConflict,
  }) {
    if (saving || _disposed) return;
    if (next == saved ||
        next is Map && saved is Map && mapEquals(next, saved)) {
      _entries.remove(key);
    } else {
      _entries[key] = _Draft(
        next,
        () => commit(next),
        basis,
        checkConflict == null ? null : () => checkConflict(next),
      );
    }
    _conflicts.remove(key);
    failed = false;
    saveConflicted = false;
    _notify();
  }

  void discard() {
    _epoch++;
    _entries.clear();
    _conflicts.clear();
    failed = false;
    saveConflicted = false;
    _notify();
  }

  void rejectEdit(String key, PrivacyDraftConflict conflict) {
    if (saving || _disposed) return;
    _entries.remove(key);
    _conflicts[key] = conflict;
    if (!dirty) failed = false;
    _notify();
  }

  /// Drops one invalid draft as soon as its card can verify the conflict.
  void reconcileConflict(String key) {
    final entry = _entries[key];
    if (entry != null && _dropConflictingDraft(MapEntry(key, entry))) {
      _notify();
    }
  }

  bool _dropConflictingDraft(MapEntry<String, _Draft> item) {
    final conflict = item.value.checkConflict?.call();
    if (conflict == null) return false;
    _entries.remove(item.key);
    _conflicts[item.key] = conflict;
    if (saving) saveConflicted = true;
    if (!dirty) failed = false;
    return true;
  }

  Future<bool> save() async {
    if (saving || _disposed) return false;
    final epoch = _epoch;
    saving = true;
    failed = false;
    saveConflicted = false;
    _notify();
    try {
      if (_epoch != epoch) return false;
      final pending = _entries.entries.toList();
      // Leave other cards pending if a conflict is already known at save time.
      for (final item in pending) {
        _dropConflictingDraft(item);
      }
      if (saveConflicted) return false;
      for (final item in pending) {
        if (_epoch != epoch || saveConflicted || _dropConflictingDraft(item)) {
          return false;
        }
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
          if (_dropConflictingDraft(item)) return false;
          failed = true;
        }
      }
      return !saveConflicted && !dirty;
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
    _conflicts.clear();
    super.dispose();
  }
}

class _Draft {
  const _Draft(this.value, this.commit, this.basis, this.checkConflict);
  final Object? value;
  final Future<bool> Function() commit;
  final PrivacyDraftConflict? Function()? checkConflict;
  final Object? basis;
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
