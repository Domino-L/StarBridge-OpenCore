import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';

void main() {
  test('unavailable or incomplete hangar preserves remote favorites', () async {
    final remote = await InMemoryPersonalProfileAdapter.forReview(signedIn: true).read();
    expect(remote.favoriteShips, isNotEmpty);
    for (final hangar in <LocalHangarSnapshot?>[
      null,
      const LocalHangarSnapshot(revision: 0, ships: []),
      const LocalHangarSnapshot(revision: 1, ships: [], partial: true),
      const LocalHangarSnapshot(revision: 1, ships: [], fromLegacyProfile: true),
    ]) {
      final result = projectLocalProfile(remote, null, hangar, null);
      expect(result.favoriteShips, orderedEquals(remote.favoriteShips));
    }
    final empty = projectLocalProfile(remote, null,
        const LocalHangarSnapshot(revision: 1, ships: []), null);
    expect(empty.favoriteShips, hasLength(remote.favoriteShips.length));
    expect(empty.favoriteShips.every((ship) => ship.formerlyOwned), isTrue);
    final owned = projectLocalProfile(remote, null, LocalHangarSnapshot(
      revision: 2,
      ships: [
        for (final ship in remote.favoriteShips)
          LocalHangarShip(
            id: ship.identity.runtimeId,
            title: ship.identity.englishName,
            catalogId: ship.identity.catalogId,
          ),
      ],
    ), null);
    expect(owned.favoriteShips.every((ship) => !ship.formerlyOwned), isTrue);
  });
}
