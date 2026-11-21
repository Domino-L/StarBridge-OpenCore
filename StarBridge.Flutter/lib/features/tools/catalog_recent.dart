import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'catalog_port.dart';
import 'catalog_names.dart';

abstract interface class CatalogRecentStore {
  Future<CatalogRow> read(String owner);
  Future<void> write(String owner, CatalogRow value);
}

/// UI history only: no profiles, account files, network state or catalogue data.
class MemoryCatalogRecentStore implements CatalogRecentStore {
  final _values = <String, CatalogRow>{};
  @override
  Future<CatalogRow> read(String owner) async => _values[owner] ?? {};
  @override
  Future<void> write(String owner, CatalogRow value) async {
    _values[owner] = value;
  }
}

final class CatalogRecentEntry {
  const CatalogRecentEntry(this.kind, this.id, this.name, this.nameCn);
  final CatalogKind kind;
  final Object id;
  final String name, nameCn;
  String get key => '${kind.name}:$id';
  String label(String locale) =>
      locale == 'en' || nameCn.isEmpty ? name : nameCn;
  CatalogRow toMap() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    'nameCn': nameCn,
  };
  static CatalogRecentEntry? parse(CatalogRow row) {
    final kind = CatalogKind.values
        .where((v) => v.name == row['kind'])
        .firstOrNull;
    final id = switch (row['id']) {
      final String value => value,
      final int value => value,
      _ => null,
    };
    final name = row['name'], cn = row['nameCn'];
    if (kind == null ||
        id == null ||
        name is! String ||
        cn is! String ||
        name.length > 500 ||
        cn.length > 500 ||
        id.toString().length > 128) {
      return null;
    }
    return CatalogRecentEntry(kind, id, name, cn);
  }
}

final class CatalogRecent extends ChangeNotifier {
  CatalogRecent(this.store);
  final CatalogRecentStore store;
  List<CatalogRecentEntry> entries = [];
  DateTime? lastImportAt;
  bool saveFailed = false, _disposed = false;
  String? _owner;
  int _epoch = 0;
  Future<void> _queue = Future.value();
  Future<void> Function()? prepare;
  Future<void>? _loading;
  int scopeRevision = 0;
  Future<void> get idle => _queue;

  /// Caller passes an opaque, environment-qualified owner key, never a token.
  Future<void> switchOwner(String? owner, {bool retireScope = false}) {
    if (_disposed || owner == _owner && !retireScope) {
      return _loading ?? Future.value();
    }
    final epoch = ++_epoch;
    // The first binding identifies existing reads; only a real owner leaving
    // invalidates them (including logout before another owner binds).
    if (retireScope || _owner != null) scopeRevision++;
    _owner = owner;
    entries = [];
    lastImportAt = null;
    saveFailed = false;
    notifyListeners();
    if (owner == null) return _loading = Future.value();
    return _loading = _load(owner, epoch);
  }

  Future<void> _load(String owner, int epoch) async {
    try {
      await _queue;
      final value = await store.read(owner);
      if (_disposed || epoch != _epoch) return;
      final seen = <String>{};
      entries = catalogRows(value['entries'])
          .map(CatalogRecentEntry.parse)
          .whereType<CatalogRecentEntry>()
          .where((e) => seen.add(e.key))
          .take(6)
          .toList();
      lastImportAt = DateTime.tryParse('${value['lastImportAt'] ?? ''}');
      notifyListeners();
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        saveFailed = true;
        notifyListeners();
      }
    }
  }

  Future<void> view(CatalogKind kind, CatalogRow row) async {
    final scope = scopeRevision;
    try {
      await prepare?.call();
    } catch (_) {
      return;
    }
    if (_disposed || scope != scopeRevision) return;
    final owner = _owner;
    await _loading;
    if (scope != scopeRevision || owner != _owner) return;
    if (_disposed || _owner == null) return;
    final mission = kind == CatalogKind.missions;
    final name = mission ? 'title' : 'blueprintName';
    final entry = CatalogRecentEntry.parse({
      'kind': kind.name,
      'id': row[mission ? 'missionGuid' : 'id'],
      'name': row[name] ?? '—',
      // Blueprints without an SCM Chinese name keep the tidied title for
      // Chinese UIs (no repeated kind word, size as "· S1").
      'nameCn': mission
          ? row['${name}Cn'] ?? ''
          : catalogBlueprintTitleLine(row, const Locale('zh', 'CN')),
    });
    if (entry == null) return;
    _epoch++;
    entries = [
      entry,
      ...entries.where((e) => e.key != entry.key),
    ].take(6).toList();
    _save();
  }

  Future<void> imported(DateTime time) async {
    final owner = _owner;
    await _loading;
    if (!_disposed && owner != null && owner == _owner) {
      lastImportAt = time;
      _save();
    }
  }

  void clear() {
    _epoch++;
    entries = [];
    _save();
  }

  void _save() {
    final owner = _owner, epoch = _epoch;
    if (_disposed || owner == null) return;
    final value = <String, Object?>{
      'entries': entries.map((e) => e.toMap()).toList(),
      'lastImportAt': lastImportAt?.toUtc().toIso8601String(),
    };
    _queue = _queue.then((_) async {
      try {
        await store.write(owner, value);
        if (!_disposed && epoch == _epoch) saveFailed = false;
      } catch (_) {
        if (!_disposed && epoch == _epoch) saveFailed = true;
      }
      if (!_disposed && epoch == _epoch) notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
