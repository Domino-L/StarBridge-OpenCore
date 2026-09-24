import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_models.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_port.dart';

void main() {
  test('refresh retains values but disables editing until confirmed', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final snapshot = InMemorySyncPrivacyAdapter.forReview().current;
    final initial = module.initialize();
    port.reads.single.complete(snapshot);
    await initial;
    final refresh = module.refresh();
    expect(module.projection.value.settings, same(snapshot.settings));
    expect(module.projection.value.canEdit, isFalse);
    port.reads.last.completeError(StateError('offline'));
    await refresh;
    expect(module.projection.value.settings, same(snapshot.settings));
    expect(module.projection.value.canEdit, isFalse);
    final recover = module.refresh();
    port.reads.last.complete(snapshot);
    await recover;
    expect(module.projection.value.canEdit, isTrue);
    expect(module.projection.value.failure, isNull);
  });

  test('uncertain write reads back automatically without replay', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final snapshot = InMemorySyncPrivacyAdapter.forReview().current;
    final initial = module.initialize();
    port.reads.single.complete(snapshot);
    await initial;
    final save = module.save(snapshot.settings!);
    port.write.completeError(StateError('reply lost'));
    expect(await save, isFalse);
    expect(port.reads.length, 2);
    expect(port.writes, 1);
    expect(module.projection.value.canEdit, isFalse);
    port.reads.last.complete(snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.canEdit, isTrue);
    expect(port.writes, 1);
  });

  test('queued refresh is drained after a failed write', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final snapshot = InMemorySyncPrivacyAdapter.forReview().current;
    final initial = module.initialize();
    port.reads.single.complete(snapshot);
    await initial;
    final save = module.save(snapshot.settings!);
    await module.refresh();
    port.write.complete(
      const SyncPrivacyWriteResult.failed(SyncPrivacyFailure.writeConflict),
    );
    expect(await save, isFalse);
    expect(port.reads.length, 2);
    port.reads.last.complete(snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.canEdit, isTrue);
  });

  test('account invalidation discards a pending old-account read', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final initial = module.initialize();
    port.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(port.reads.length, 2);
    port.reads[1].complete(const SyncPrivacySnapshot.signedOut());
    await Future<void>.delayed(Duration.zero);
    port.reads[0].complete(InMemorySyncPrivacyAdapter.forReview().current);
    await initial;
    expect(
      module.projection.value.availability,
      SyncPrivacyAvailability.signedOut,
    );
    expect(module.projection.value.settings, isNull);
  });

  test('account invalidation discards a pending old-account write', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final initial = module.initialize();
    final snapshot = InMemorySyncPrivacyAdapter.forReview().current;
    port.reads.single.complete(snapshot);
    await initial;
    final save = module.save(snapshot.settings!);
    port.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(module.projection.value.settings, isNull);
    expect(port.reads.length, 2);
    port.reads.last.complete(const SyncPrivacySnapshot.signedOut());
    await Future<void>.delayed(Duration.zero);
    port.write.complete(SyncPrivacyWriteResult.completed(snapshot));
    expect(await save, isFalse);
    expect(
      module.projection.value.availability,
      SyncPrivacyAvailability.signedOut,
    );
  });

  test('read exception settles and a later refresh recovers', () async {
    final port = _ControlledPort();
    final module = createSyncPrivacyModule(port);
    addTearDown(module.dispose);
    final initial = module.initialize();
    port.reads.single.completeError(StateError('read failed'));
    await initial;
    expect(
      module.projection.value.availability,
      SyncPrivacyAvailability.unavailable,
    );
    final refresh = module.refresh();
    port.reads.last.complete(const SyncPrivacySnapshot.signedOut());
    await refresh;
    expect(
      module.projection.value.availability,
      SyncPrivacyAvailability.signedOut,
    );
  });

  test('module applies one revisioned semantic settings update', () async {
    final adapter = InMemorySyncPrivacyAdapter.forReview();
    final module = createSyncPrivacyModule(adapter);
    addTearDown(module.dispose);

    await module.initialize();
    final original = module.projection.value;
    expect(original.availability, SyncPrivacyAvailability.available);
    expect(original.revision, 7);

    final saved = await module.save(
      original.settings!.copyWith(
        friendDefaults: original.settings!.friendDefaults.copyWith(ship: true),
      ),
    );

    expect(saved, isTrue);
    expect(module.projection.value.revision, 8);
    expect(module.projection.value.settings!.friendDefaults.ship, isTrue);
    expect(adapter.current.revision, 8);
  });

  test('failed writes preserve the last confirmed values', () async {
    final adapter = InMemorySyncPrivacyAdapter.forReview();
    final module = createSyncPrivacyModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();
    final original = module.projection.value.settings!;
    adapter.failNextUpdate = true;

    final saved = await module.save(
      original.copyWith(realtimeSyncEnabled: false),
    );

    expect(saved, isFalse);
    expect(module.projection.value.settings, same(original));
    expect(module.projection.value.failure, SyncPrivacyFailure.writeFailed);
    expect(module.projection.value.canEdit, isTrue);
  });
}

final class _ControlledPort implements SyncPrivacyPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<SyncPrivacySnapshot>>[];
  final write = Completer<SyncPrivacyWriteResult>();
  int writes = 0;

  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<SyncPrivacySnapshot> read() {
    final result = Completer<SyncPrivacySnapshot>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) {
    writes++;
    return write.future;
  }

  @override
  Future<void> close() => changes.close();
}
