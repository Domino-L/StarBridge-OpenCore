import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';

import 'personal_profile_module_test.dart' show editOf;

void main() {
  test('editing defers ordinary updates and explicit refresh into one read after closing', () async {
    final port = HeldRefreshProfile();
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    final editing = module as PersonalProfileEditingSession;
    expect(editing.beginEditing(), isTrue);
    expect(editing.beginEditing(), isFalse);
    for (var i = 0; i < 10; i++) {
      port.soft.add(null);
    }
    await module.refresh();
    expect(port.reads, 1);
    expect(
      module.projection.value.availability,
      PersonalProfileAvailability.available,
    );
    port.readGate = Completer<PersonalProfileSnapshot>();
    editing.endEditing();
    editing.endEditing();
    expect(port.reads, 2);
    port.readGate!.complete(await port.delegate.read());
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 2);
  });

  test(
    'hard invalidation ends editing and clears content immediately',
    () async {
      final port = HeldRefreshProfile();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final editing = module as PersonalProfileEditingSession;
      expect(editing.beginEditing(), isTrue);
      port.soft.add(null);
      port.readGate = Completer<PersonalProfileSnapshot>();
      port.hard.add(null);
      expect(
        module.projection.value.availability,
        PersonalProfileAvailability.loading,
      );
      expect(module.projection.value.callSign, isEmpty);
      expect(editing.beginEditing(), isFalse);
      editing.endEditing();
      expect(port.reads, 2);
      port.readGate!.complete(await port.delegate.read());
      await Future<void>.delayed(Duration.zero);
      expect(
        port.reads,
        2,
        reason: 'Hard invalidation consumes deferred soft changes.',
      );
    },
  );

  test('an old timeout after hard invalidation cannot restore the previous profile', () async {
    final port = HeldRefreshProfile();
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    final old = port.readGate = Completer<PersonalProfileSnapshot>();
    final reading = module.refresh();
    port.hard.add(null);
    port.readGate = Completer<PersonalProfileSnapshot>();
    old.completeError(TimeoutException('old owner'));
    await reading;
    expect(module.projection.value.callSign, isEmpty);
    expect(
      module.projection.value.availability,
      PersonalProfileAvailability.loading,
    );
    expect(port.reads, 3);
    port.readGate!.complete(await port.delegate.read());
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'unclassified read failure clears data and cannot enable editing',
    () async {
      final port = HeldRefreshProfile();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      port.readGate = Completer<PersonalProfileSnapshot>();
      final reading = module.refresh();
      port.readGate!.completeError(StateError('unknown synthetic failure'));
      await reading;
      expect(
        module.projection.value.availability,
        PersonalProfileAvailability.unavailable,
      );
      expect(module.projection.value.callSign, isEmpty);
      expect(module.projection.value.canEdit, isFalse);
    },
  );

  test(
    'loaded profile remains visible while a same-context refresh is pending',
    () async {
      final port = HeldRefreshProfile();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value;
      port.readGate = Completer<PersonalProfileSnapshot>();
      final reading = module.refresh();
      expect(
        module.projection.value.availability,
        PersonalProfileAvailability.available,
      );
      expect(module.projection.value.callSign, before.callSign);
      expect(module.projection.value.favoriteShips, same(before.favoriteShips));
      expect(
        module.projection.value.operation,
        PersonalProfileOperation.refreshing,
      );
      expect(module.projection.value.canEdit, isFalse);
      port.readGate!.complete(await port.delegate.read());
      await reading;
      expect(module.projection.value.canEdit, isTrue);
    },
  );

  test('read timeout keeps confirmed content with editing disabled until revalidated', () async {
    final port = HeldRefreshProfile();
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    final before = module.projection.value;
    port.readGate = Completer<PersonalProfileSnapshot>();
    final reading = module.refresh();
    port.readGate!.completeError(TimeoutException('synthetic read outage'));
    await reading;
    expect(
      module.projection.value.availability,
      PersonalProfileAvailability.available,
    );
    expect(module.projection.value.callSign, before.callSign);
    expect(module.projection.value.canEdit, isFalse);
    expect(module.projection.value.failureKey, isNotNull);
    port.readGate = null;
    await module.refresh();
    expect(module.projection.value.canEdit, isTrue);
  });

  test('manual refresh cannot replace the lease of a pending write', () async {
    final port = HeldRefreshProfile();
    final module = createPersonalProfileModule(port);
    addTearDown(module.dispose);
    await module.initialize();
    port.saveGate = Completer<PersonalProfileActionResult>();
    final saving = module.save(editOf(module));
    await module.refresh();
    expect(port.reads, 1);
    expect(module.projection.value.operation, PersonalProfileOperation.saving);
    port.saveGate!.complete(
      const PersonalProfileActionResult(PersonalProfileActionOutcome.completed),
    );
    await saving;
    expect(port.reads, 2);
    expect(port.saves, 1);
  });
}

class HeldRefreshProfile
    implements PersonalProfilePort, PersonalProfileContentChanges {
  final delegate = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  final hard = StreamController<void>.broadcast(sync: true);
  final soft = StreamController<void>.broadcast(sync: true);
  Completer<PersonalProfileSnapshot>? readGate;
  Completer<PersonalProfileActionResult>? saveGate;
  int reads = 0, saves = 0;
  @override
  Stream<void> get invalidations => hard.stream;
  @override
  Stream<void> get changes => soft.stream;
  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    return readGate?.future ?? delegate.read();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) {
    saves++;
    return saveGate?.future ?? delegate.save(edit);
  }

  @override
  Future<void> close() async {
    await hard.close();
    await soft.close();
    await delegate.close();
  }
}
