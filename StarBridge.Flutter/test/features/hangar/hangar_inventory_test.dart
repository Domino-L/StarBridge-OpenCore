import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/hangar_inventory_module.dart';
import 'package:starbridge_flutter/features/hangar/hangar_inventory_port.dart';

void main() {
  test(
    'lost save response is resolved without creating another save',
    () async {
      final port = TestInventory()..failCommit = true;
      final module = HangarInventoryModule(port);
      await module.refresh();
      await module.preview('basic');
      await module.save();
      expect(module.uncertain, isTrue);
      expect(module.saved!.revision, 0);
      await module.checkResult();
      expect(module.saved!.revision, 1);
      expect(module.pending, isNull);
      module.dispose();
    },
  );
  test(
    'switching account clears old data before a delayed read completes',
    () async {
      final port = TestInventory();
      final module = HangarInventoryModule(port);
      await module.refresh();
      port.delayed = Completer<HangarInventorySnapshot>();
      final switching = module.selectAccount('B');
      expect(module.account, 'B');
      expect(module.saved, isNull);
      port.delayed!.complete(const HangarInventorySnapshot(0, null, []));
      await switching;
      module.dispose();
    },
  );
  test('disposed module ignores a delayed response', () async {
    final port = TestInventory()
      ..delayed = Completer<HangarInventorySnapshot>();
    final module = HangarInventoryModule(port);
    final loading = module.refresh();
    module.dispose();
    port.delayed!.complete(const HangarInventorySnapshot(4, null, []));
    await loading;
    expect(module.saved, isNull);
  });
  test('failed refresh preserves previously saved facts', () async {
    final port = TestInventory();
    final module = HangarInventoryModule(port);
    await module.refresh();
    port.delayed = Completer<HangarInventorySnapshot>();
    final loading = module.refresh();
    port.delayed!.completeError(const HangarInventoryFailure('unavailable'));
    await loading;
    expect(module.saved!.revision, 0);
    expect(module.error, 'unavailable');
    module.dispose();
  });
  test('preview leaves saved inventory unchanged until confirmed', () async {
    final port = TestInventory();
    final module = HangarInventoryModule(port);
    await module.refresh();
    await module.preview('basic');
    expect(module.saved!.revision, 0);
    expect(module.pending, isNotNull);
    await module.save();
    expect(module.saved!.revision, 1);
    expect(module.pending, isNull);
    module.dispose();
  });
}

class TestInventory implements HangarInventoryPort {
  HangarInventorySnapshot stored = const HangarInventorySnapshot(0, null, []);
  Completer<HangarInventorySnapshot>? delayed;
  bool failCommit = false;
  @override
  Future<bool> available() async => true;
  @override
  Future<HangarInventorySnapshot> read(String account) async =>
      delayed == null ? stored : delayed!.future;
  @override
  Future<HangarInventoryImport> preview(
    String account,
    String scenario,
    String key,
    int revision,
  ) async => const HangarInventoryImport('op', 0, 'digest', [], 1, 0, 0, false);
  @override
  Future<HangarInventorySnapshot> commit(
    String account,
    HangarInventoryImport preview,
    String key,
    bool clear,
  ) async {
    stored = const HangarInventorySnapshot(1, null, []);
    if (failCommit) throw const HangarInventoryFailure('unavailable');
    return stored;
  }

  @override
  Future<HangarInventorySnapshot?> result(String account, String id) async =>
      stored.revision > 0 ? stored : null;
}
