import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/tools/catalog_controller.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_recent.dart';
import 'package:starbridge_flutter/features/tools/tools_snapshot_cache.dart';

import 'catalog_samples.dart';

class HeldCatalog extends SampleCatalogPort {
  final held = Completer<CatalogRow>();
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) => held.future;
}

void main() {
  test(
    'partial or filtered pages never masquerade as complete blueprint counts',
    () {
      final cache = ToolsSnapshotCache();
      cache.accept(
        'blueprints.page',
        {'keyword': 'helmet', 'pageNo': 1},
        {
          'total': 1,
          'rows': [blueprintSample],
        },
        false,
      );
      expect(cache.blueprintTotal, isNull);
      cache.accept(
        'blueprints.page',
        {'keyword': '', 'pageNo': 1},
        {
          'total': 2,
          'rows': [blueprintSample],
        },
        false,
      );
      expect(cache.blueprintTotal, 2);
      expect(cache.rewarded, isNull);
      expect(cache.categories, isNull);
      cache.accept(
        'blueprints.page',
        {'pageNo': 2},
        {
          'total': 2,
          'rows': [
            {...blueprintSample, 'id': 74, 'rewardMissionCount': 0},
          ],
        },
        false,
      );
      expect(cache.rewarded, 1);
      expect(cache.categories, {'FPSArmours': 2});
      cache.retire();
      expect(cache.blueprintTotal, isNull);
      expect(cache.blueprintRows, isEmpty);
      cache.dispose();
    },
  );
  test('retired catalogue response does not repopulate landing data', () async {
    final source = HeldCatalog(), cache = ToolsSnapshotCache();
    final observed = ObservedCatalogPort(source, cache);
    final pending = observed.read('blueprints.page', {});
    final rejection = expectLater(pending, throwsA(isA<CatalogFailure>()));
    observed.retire();
    source.held.complete({
      'total': 1,
      'rows': [blueprintSample],
    });
    await rejection;
    expect(cache.blueprintTotal, isNull);
    observed.dispose();
    cache.dispose();
  });
  test('only successful selected details enter recent history', () async {
    final recent = CatalogRecent(MemoryCatalogRecentStore());
    await recent.switchOwner('synthetic');
    final source = SampleCatalogPort();
    final c = CatalogController(
      CatalogKind.missions,
      source,
      onViewed: (row) {
        recent.view(CatalogKind.missions, row);
      },
    );
    source.failures['missions.detail'] = const CatalogFailure();
    await c.select(missionGuid);
    await Future<void>.delayed(Duration.zero);
    expect(recent.entries, isEmpty);
    source.failures.clear();
    await c.select(missionGuid);
    await Future<void>.delayed(Duration.zero);
    await recent.idle;
    expect(recent.entries.single.id, missionGuid);
    c.dispose();
    recent.dispose();
  });
}
