import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';

void main() {
  for (final outcome in [
    PersonalProfileActionOutcome.completed,
    PersonalProfileActionOutcome.failed,
  ]) {
    test('notifies observers only after the full save settles: $outcome', () async {
      final port = HeldSaveProfile();
      var notifications = 0;
      final module = createPersonalProfileModule(port,
        onSaveSettled: () => notifications++);
      addTearDown(module.dispose);
      await module.initialize();
      final saving = module.save(editOf(module));
      expect(notifications, 0);
      expect(port.saves, 1);
      port.saveGate.complete(PersonalProfileActionResult(outcome,
        failureKey: outcome == PersonalProfileActionOutcome.failed
          ? 'profile.error.refreshBeforeSave' : null));
      expect((await saving).outcome, outcome);
      expect(notifications, 1);
      expect(port.saves, 1); // Refresh notification never resubmits a write.
      expect(port.reads, outcome == PersonalProfileActionOutcome.completed ? 2 : 1);
    });
  }
  for (final dispose in [false, true]) {
    test('drops obsolete completion after ${dispose ? 'dispose' : 'invalidation'}', () async {
      final port = HeldSaveProfile();
      var notifications = 0;
      final module = createPersonalProfileModule(port,
        onSaveSettled: () => notifications++);
      addTearDown(module.dispose);
      await module.initialize();
      final saving = module.save(editOf(module));
      if (dispose) {
        module.dispose();
      } else {
        port.changes.add(null);
        await Future<void>.delayed(Duration.zero);
      }
      port.saveGate.complete(const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed));
      expect((await saving).outcome, PersonalProfileActionOutcome.rejected);
      expect(notifications, 0);
    });
  }
  test('observer failure does not reinterpret a confirmed write', () async {
    final port = HeldSaveProfile();
    final module = createPersonalProfileModule(port,
      onSaveSettled: () => throw StateError('observer unavailable'));
    addTearDown(module.dispose);
    await module.initialize();
    final saving = module.save(editOf(module));
    port.saveGate.complete(const PersonalProfileActionResult(
      PersonalProfileActionOutcome.completed));
    expect((await saving).outcome, PersonalProfileActionOutcome.completed);
    expect(port.reads, 2);
  });
  test(
    'pending profile read never publishes the pre-rename affiliation',
    () async {
      final port = HeldProfile();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      final names = <String>[];
      module.projection.addListener(() {
        names.addAll(
          module.projection.value.affiliations
              .where((row) => row.code == 'NORTH')
              .map((row) => row.name),
        );
      });
      final reading = module.initialize();
      module.renameCommunity('NORTH', '新名称');
      port.gate.complete(
        await InMemoryPersonalProfileAdapter.forReview(signedIn: true).read(),
      );
      await reading;
      expect(names, ['新名称']);
    },
  );
  test(
    'confirmed community rename preserves the rest of the loaded profile',
    () async {
      final module = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value;
      module.renameCommunity('NORTH', '新名称');
      final after = module.projection.value;
      expect(after.affiliations.last.name, '新名称');
      expect(after.affiliations.first.name, before.affiliations.first.name);
      expect(after.availability, before.availability);
      expect(after.favoriteShips, same(before.favoriteShips));
      expect(after.local, same(before.local));
    },
  );
  test(
    'pending profile read never publishes the pre-rename affiliation',
    () async {
      final port = HeldProfile();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      final names = <String>[];
      module.projection.addListener(() {
        names.addAll(
          module.projection.value.affiliations
              .where((row) => row.code == 'NORTH')
              .map((row) => row.name),
        );
      });
      final reading = module.initialize();
      module.renameCommunity('NORTH', '新名称');
      port.gate.complete(
        await InMemoryPersonalProfileAdapter.forReview(signedIn: true).read(),
      );
      await reading;
      expect(names, ['新名称']);
    },
  );
  test(
    'confirmed community rename preserves the rest of the loaded profile',
    () async {
      final module = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value;
      module.renameCommunity('NORTH', '新名称');
      final after = module.projection.value;
      expect(after.affiliations.last.name, '新名称');
      expect(after.affiliations.first.name, before.affiliations.first.name);
      expect(after.availability, before.availability);
      expect(after.favoriteShips, same(before.favoriteShips));
      expect(after.local, same(before.local));
    },
  );
  test(
    'rejects an unknown wallpaper id before it reaches the adapter',
    () async {
      final module = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final before = module.projection.value;

      final result = await module.save(
        PersonalProfileEdit(
          callSign: before.callSign,
          about: before.about,
          avatarStyle: before.avatarStyle,
          wallpaperId: 'not-a-catalog-wallpaper',
          visibility: before.visibility,
          moduleLayout: before.moduleLayout,
        ),
      );

      expect(result.outcome, PersonalProfileActionOutcome.rejected);
      expect(module.projection.value.wallpaperId, before.wallpaperId);
      expect(module.projection.value.operation, PersonalProfileOperation.none);
    },
  );
}

PersonalProfileEdit editOf(PersonalProfileModule module) {
  final before = module.projection.value;
  return PersonalProfileEdit(callSign: before.callSign, about: before.about,
    avatarStyle: before.avatarStyle, wallpaperId: before.wallpaperId,
    visibility: before.visibility, moduleLayout: before.moduleLayout);
}

class HeldSaveProfile implements PersonalProfilePort {
  final changes = StreamController<void>.broadcast();
  final saveGate = Completer<PersonalProfileActionResult>();
  int saves = 0;
  int reads = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<PersonalProfileSnapshot> read() {
    reads++;
    return InMemoryPersonalProfileAdapter.forReview(signedIn: true).read();
  }
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) {
    saves++;
    return saveGate.future;
  }
  @override
  Future<void> close() => changes.close();
}

class HeldProfile implements PersonalProfilePort {
  final gate = Completer<PersonalProfileSnapshot>();
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<PersonalProfileSnapshot> read() => gate.future;
  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) =>
      throw UnimplementedError();
  @override
  Future<void> close() async {}
}
