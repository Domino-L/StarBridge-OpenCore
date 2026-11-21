import 'package:flutter/foundation.dart';

import 'catalog_port.dart';
import 'key_bindings_port.dart';

/// Observes existing reads. The landing page never calls a catalogue/key port.
final class ToolsSnapshotCache extends ChangeNotifier {
  bool _disposed = false;
  KeyBindingsSnapshot? keys;
  DateTime? keysReadAt;
  int? blueprintTotal;
  final blueprintRows = <String, CatalogRow>{};
  final missionRows = <String, CatalogRow>{};
  bool get completeBlueprints =>
      blueprintTotal != null && blueprintRows.length == blueprintTotal;
  int? get rewarded =>
      completeBlueprints &&
          blueprintRows.values.every((r) => r['rewardMissionCount'] is num)
      ? blueprintRows.values
            .where((r) => (r['rewardMissionCount'] as num? ?? 0) > 0)
            .length
      : null;
  Map<String, int>? get categories {
    if (!completeBlueprints) return null;
    final counts = <String, int>{};
    for (final row in blueprintRows.values) {
      final name = row['categoryName']?.toString() ?? '—';
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  void accept(
    String operation,
    CatalogRow parameters,
    CatalogRow data,
    bool refresh,
  ) {
    if (_disposed) return;
    if (operation.startsWith('missions.')) {
      for (final row
          in operation == 'missions.detail'
              ? [data]
              : catalogRows(data['rows'])) {
        if (row['missionGuid'] != null) {
          missionRows['${row['missionGuid']}'] = row;
        }
      }
    }
    if (operation == 'blueprints.page' &&
        parameters.entries.every(
          (e) =>
              e.key == 'pageNo' ||
              e.key == 'sortField' ||
              e.key == 'sortOrder' ||
              e.value == '' ||
              e.value == null,
        )) {
      final total = data['total'];
      if (total is int && total >= 0) {
        if (refresh || blueprintTotal != total) blueprintRows.clear();
        blueprintTotal = total;
        for (final row in catalogRows(data['rows'])) {
          if (row['id'] != null) blueprintRows['${row['id']}'] = row;
        }
      }
    }
    notifyListeners();
  }

  void acceptKeys(KeyBindingsSnapshot value) {
    if (_disposed) return;
    keys = value;
    keysReadAt = DateTime.now();
    notifyListeners();
  }

  void retire() {
    if (_disposed) return;
    blueprintTotal = null;
    blueprintRows.clear();
    missionRows.clear();
    // Device bindings are local data and survive account changes.
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class ObservedCatalogPort implements CatalogPort {
  ObservedCatalogPort(this.source, this.cache);
  final CatalogPort source;
  final ToolsSnapshotCache cache;
  int _epoch = 0;
  void retire() {
    _epoch++;
    cache.retire();
  }

  @override
  bool get canOpenWebsite => source.canOpenWebsite;
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) async {
    final epoch = _epoch;
    final data = await source.read(operation, parameters, refresh: refresh);
    if (epoch != _epoch) throw const CatalogFailure();
    cache.accept(operation, parameters, data, refresh);
    return data;
  }

  @override
  Future<void> openWebsite(CatalogKind kind, CatalogRow detail) =>
      source.openWebsite(kind, detail);
  @override
  void dispose() {
    _epoch++;
    source.dispose();
  }
}

final class ObservedKeyBindingsPort implements KeyBindingsPort {
  ObservedKeyBindingsPort(this.source, this.cache);
  final KeyBindingsPort source;
  final ToolsSnapshotCache cache;
  @override
  Future<KeyBindingsSnapshot> read(
    String channel,
    String language, {
    String? localization,
  }) async {
    final value = await source.read(
      channel,
      language,
      localization: localization,
    );
    cache.acceptKeys(value);
    return value;
  }

  @override
  Future<void> saveView(KeyBindingsView view) => source.saveView(view);
}
