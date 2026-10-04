import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/settings/community_join_hangar_choice.dart';

import 'community_sharing_test.dart' show target;

class JoinHangarFixture implements CommunityHangarSharingPort {
  int reads = 0, writes = 0;
  bool available = true;
  bool explicit = true;
  final selected = <String>{'A'};
  final events = StreamController<void>.broadcast();
  CommunityHangarSharingOutcome outcome = const CommunityHangarSharingOutcome(
    'accepted',
  );
  List<String>? savedRefs;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  bool get hangarSharingAvailable => available;
  @override
  Future<CommunityHangarSharing> readHangarSharing() async {
    reads++;
    return CommunityHangarSharing.parse({
      'schemaVersion': 1,
      'editRef': reads.toRadixString(16).padLeft(32, '0'),
      'usesExplicitTargets': explicit,
      'maximumTargets': 64,
      'options': [
        for (final code in ['A', 'B', 'C'])
          {
            'targetRef': (code.codeUnitAt(0) - 64)
                .toRadixString(16)
                .padLeft(32, '0'),
            'name': 'Same display name',
            'communityCode': code,
            'selected': selected.contains(code),
          },
      ],
    });
  }

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> refs,
  ) async {
    writes++;
    savedRefs = List.of(refs);
    if (outcome.status == 'accepted') {
      selected.clear();
      for (final code in ['A', 'B', 'C']) {
        if (refs.contains(
          (code.codeUnitAt(0) - 64).toRadixString(16).padLeft(32, '0'),
        )) {
          selected.add(code);
        }
      }
      explicit = true;
    }
    return outcome;
  }
}

void main() {
  test(
    'confirming changes exactly this code and preserves other audiences',
    () async {
      final p = JoinHangarFixture();
      addTearDown(p.events.close);
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isTrue,
      );
      expect(p.selected, {'A', 'B'});
      expect(p.writes, 1);
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: false,
          membershipCurrent: () async => true,
        ),
        isTrue,
      );
      expect(p.selected, {'A'});
    },
  );
  test(
    'fresh accepted read never republishes an already saved choice',
    () async {
      final p = JoinHangarFixture()..selected.add('B');
      addTearDown(p.events.close);
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isTrue,
      );
      expect(p.reads, 1);
      expect(p.writes, 0);
    },
  );
  test(
    'changed membership, missing code and unsupported read cannot grant',
    () async {
      final p = JoinHangarFixture();
      addTearDown(p.events.close);
      var checks = 0;
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => ++checks == 1,
        ),
        isFalse,
      );
      expect(p.writes, 0);
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('D'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isFalse,
      );
      p.available = false;
      final before = p.reads;
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isFalse,
      );
      expect(p.reads, before);
      expect(p.writes, 0);
    },
  );
  test(
    'unknown write is not replayed; explicit retry starts with a fresh read',
    () async {
      final p = JoinHangarFixture()
        ..outcome = const CommunityHangarSharingOutcome('unknown');
      addTearDown(p.events.close);
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isFalse,
      );
      expect(p.writes, 1);
      // Model a lost acknowledgement: the server actually accepted the choice.
      p.selected.add('B');
      expect(
        await saveJoinedCommunityHangarChoice(
          port: p,
          target: target('B'),
          share: true,
          membershipCurrent: () async => true,
        ),
        isTrue,
      );
      expect(p.reads, 2);
      expect(p.writes, 1);
    },
  );
}
