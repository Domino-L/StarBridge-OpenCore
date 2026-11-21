import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_recent.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/platform/catalog_recent_file_store.dart';

import 'catalog_browse_test.dart' show size, settle, disposePage;
import 'catalog_samples.dart';
import 'terminal_fixtures.dart';

class HeldRecentStore extends MemoryCatalogRecentStore {
  final held = Completer<CatalogRow>();
  @override
  Future<CatalogRow> read(String owner) =>
      owner == 'old' ? held.future : super.read(owner);
}

void main() {
  test(
    'recent views deduplicate, retain six, clear and isolate owners',
    () async {
      final store = MemoryCatalogRecentStore(),
          recent = CatalogRecent(MemoryCatalogRecentStore());
      final saved = CatalogRecent(store);
      await saved.switchOwner('account-A');
      for (var id = 0; id < 8; id++) {
        await saved.view(CatalogKind.blueprints, {
          ...blueprintSample,
          'id': id,
        });
      }
      await saved.view(CatalogKind.blueprints, {...blueprintSample, 'id': 4});
      await saved.idle;
      expect(saved.entries.map((e) => e.id), [4, 7, 6, 5, 3, 2]);
      await saved.switchOwner('account-B');
      expect(saved.entries, isEmpty);
      await saved.view(CatalogKind.missions, missionSample);
      await saved.idle;
      await saved.switchOwner('account-A');
      expect(saved.entries.map((e) => e.id), [4, 7, 6, 5, 3, 2]);
      saved.clear();
      await saved.idle;
      final reopened = CatalogRecent(store);
      await reopened.switchOwner('account-A');
      expect(reopened.entries, isEmpty);
      await saved.switchOwner(null);
      await saved.view(CatalogKind.missions, missionSample);
      expect(saved.entries, isEmpty);
      saved.dispose();
      recent.dispose();
      reopened.dispose();
    },
  );
  test('a retired owner cannot restore a late history read', () async {
    final store = HeldRecentStore(), recent = CatalogRecent(HeldRecentStore());
    final active = CatalogRecent(store);
    final pending = active.switchOwner('old');
    await Future<void>.delayed(Duration.zero);
    await active.switchOwner('new');
    store.held.complete({
      'entries': [
        const CatalogRecentEntry(CatalogKind.blueprints, 73, 'Old', '').toMap(),
      ],
    });
    await pending;
    expect(active.entries, isEmpty);
    active.dispose();
    recent.dispose();
  });
  test(
    'local UTF-8 history survives reopen without plaintext owner filenames',
    () async {
      await Directory('_cxbuild').create(recursive: true);
      final root = await Directory('_cxbuild').createTemp('recent-store-test-');
      final store = CatalogRecentFileStore(root),
          recent = CatalogRecent(CatalogRecentFileStore(root));
      await recent.switchOwner('synthetic-owner');
      await recent.view(CatalogKind.missions, missionSample);
      await recent.imported(DateTime.utc(2026, 11, 9));
      await recent.idle;
      final reopened = CatalogRecent(store);
      await reopened.switchOwner('synthetic-owner');
      expect(reopened.entries.single.nameCn, '示意合约');
      expect(reopened.lastImportAt, DateTime.utc(2026, 11, 9));
      expect(
        root.listSync().every((f) => !f.path.contains('synthetic-owner')),
        isTrue,
      );
      recent.clear();
      await recent.idle;
      final cleared = CatalogRecent(store);
      await cleared.switchOwner('synthetic-owner');
      expect(cleared.entries, isEmpty);
      recent.dispose();
      reopened.dispose();
      cleared.dispose();
      for (final file in root.listSync().whereType<File>()) {
        await file.delete();
      }
      await root.delete();
    },
  );
  for (final kind in CatalogKind.values) {
    testWidgets('recent ${kind.name} opens the selected detail and can clear', (
      t,
    ) async {
      size(t, 1440);
      final recent = CatalogRecent(MemoryCatalogRecentStore());
      await recent.switchOwner('synthetic');
      await recent.view(
        kind,
        kind == CatalogKind.missions ? missionSample : blueprintSample,
      );
      final port = SampleCatalogPort();
      final features = createToolsFeatures(
        recent: recent,
        createCatalog: () => port,
      );
      final tools = features.singleWhere((f) => f.id == 'tools');
      await t.pumpWidget(terminalApp(Builder(builder: tools.buildDestination)));
      await settle(t);
      expect(port.calls, isEmpty);
      final entry = recent.entries.single;
      await t.ensureVisible(find.byKey(Key('tools-recent-${entry.key}')));
      await t.tap(find.byKey(Key('tools-recent-${entry.key}')));
      await settle(t);
      expect(find.byKey(const Key('catalog-detail')), findsOneWidget);
      expect(port.calls.first.operation, '${kind.name}.detail');
      await t.tap(find.byKey(const Key('catalog-back')));
      await settle(t);
      await t.ensureVisible(find.byKey(const Key('tools-recent-clear')));
      await t.tap(find.byKey(const Key('tools-recent-clear')));
      await settle(t);
      expect(recent.entries, isEmpty);
      expect(find.byKey(const Key('tools-recent-clear')), findsNothing);
      await disposePage(t);
      tools.onDispose?.call();
      recent.dispose();
    });
  }
}
