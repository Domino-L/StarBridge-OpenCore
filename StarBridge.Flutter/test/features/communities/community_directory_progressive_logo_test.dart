// 2026-10-20 report: on 寻找组织 every card kept the default shield. Logo
// reads are optional background work; a slow tail or a same-query refresh
// must not discard the logos that already arrived.
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_directory_logo_test.dart' as fixture;

/// The 17-card fixture with the Host's stable per-organization reference.
Map<String, Object?> page({String prefix = '0'}) => {
  ...fixture.directory,
  'items': [
    for (final row in fixture.directory['items'] as List)
      {
        ...Map<String, Object?>.from(row as Map),
        'targetRef': prefix + (row['targetRef'] as String).substring(1),
        'organizationRef': 'a${(row['targetRef'] as String).substring(1)}',
      },
  ],
};

class _Reads {
  _Reads() {
    bridge = CommunityHarness(
      legacy: true,
      capabilities: ['communities.read', 'communities.media'],
      holdNames: {'communities.media'},
      responses: {
        'communities.read': page(),
        'communities.media': fixture.media,
      },
    );
    module = CommunitiesModule(bridge.adapter);
  }
  late final CommunityHarness bridge;
  late final CommunitiesModule module;
  final replied = <BridgeEnvelope>{};

  Iterable<BridgeEnvelope> get media =>
      bridge.requests.where((r) => r.name == 'communities.media');
  int get logos =>
      module.directory?.items.where((r) => r.logo != null).length ?? 0;

  Future<void> until(bool Function() ready, String reason) async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (!ready() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(ready(), isTrue, reason: reason);
  }

  /// Answer only the logo reads already sent; later ones stay held.
  Future<int> answerSent() async {
    final pending = media.where((r) => !replied.contains(r)).toList();
    for (final request in pending) {
      replied.add(request);
      await bridge.reply(request);
    }
    await Future<void>.delayed(Duration.zero);
    return pending.length;
  }

  Future<void> close() async {
    bridge.holdNames.remove('communities.media');
    await answerSent();
    module.dispose();
    await Future<void>.delayed(Duration.zero);
    await bridge.close();
  }
}

void main() {
  test(
    'each arrived logo is shown without waiting for the slowest one',
    () async {
      final f = _Reads();
      addTearDown(f.close);
      await f.module.refresh(newView: 'discover');
      await f.until(() => f.media.length >= 3, 'three logo workers started');
      final answered = await f.answerSent();
      expect(answered, 3);
      await f.until(
        () => f.logos >= 3,
        'logos that arrived are published while 14 are still pending',
      );
      expect(f.module.directory!.items, hasLength(17));
    },
  );

  test('a same-query refresh keeps logos that already arrived', () async {
    final f = _Reads();
    addTearDown(f.close);
    await f.module.refresh(newView: 'discover');
    await f.until(() => f.media.length >= 3, 'three logo workers started');
    await f.answerSent();
    await f.until(() => f.logos >= 3, 'first logos published');
    final shown = f.logos;
    // Same discovery page reopened / revalidated while the tail still loads.
    // Like the real Host, the new read re-issues every targetRef while the
    // organizationRef of each organization stays the same.
    f.bridge.responses['communities.read'] = page(prefix: 'f');
    await f.module.refresh(force: true);
    expect(f.module.directory!.items.first.targetRef, startsWith('f'));
    expect(f.module.directory!.items, hasLength(17));
    expect(f.logos, greaterThanOrEqualTo(shown));
    // The refreshed read finishes the rest.
    f.bridge.holdNames.remove('communities.media');
    await f.answerSent();
    await f.until(() => f.logos == 17, 'all logos after the refresh');
  });
}
