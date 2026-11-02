import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_scenes.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_projection.dart';

void main() {
  test('a plan can fix, auto-switch to and chat from the main fleet', () {
    final policy = OverlayPresetSources(
      binding: const OverlaySourceBinding.fleet(),
      autoSwitch: true,
      modules: const {
        OverlaySourceModule.members: OverlaySourceBinding.fleet(),
      },
      chatSources: const [
        OverlaySourceBinding.fleet(),
        OverlaySourceBinding.room(),
      ],
    );
    final wire = policy.toMap();
    expect((wire['sourceBinding']! as Map)['mode'], 'fleet');
    expect((wire['sourceBinding']! as Map)['communityCode'], isNull);
    expect((wire['sourceBinding']! as Map)['ownerKey'], isNull);
    expect(OverlayPresetSources.fromMap(wire), policy);
    expect(
      () => OverlaySourceBinding.fromMap({
        'mode': 'fleet',
        'communityCode': 'A',
        'ownerKey': null,
      }),
      throwsFormatException,
    );
    // Each account's own main fleet carries no identity, so a shared plan
    // keeps it as it is.
    final shared = policy.forTransfer();
    expect(shared.binding, const OverlaySourceBinding.fleet());
    expect(shared.autoSwitch, isFalse, reason: 'sharing never installs it');
    expect(shared.chatSources, const [
      OverlaySourceBinding.room(),
      OverlaySourceBinding.fleet(),
    ]);
    final organization = OverlayPresetSources(
      chatSources: [
        const OverlaySourceBinding.fleet(),
        OverlaySourceBinding.community('A', 'owner'),
      ],
    ).forTransfer();
    expect(organization.chatSources, const [OverlaySourceBinding.fleet()]);
    expect(
      OverlayPresetSources(
        chatSources: [
          const OverlaySourceBinding.room(),
          OverlaySourceBinding.community('A', 'owner'),
        ],
      ).forTransfer().chatSources,
      isEmpty,
      reason: 'without the main fleet the room override is enough',
    );
  });

  test('a fixed main fleet the viewer has left reads like an unavailable organization', () {
    final state = BridgeOverlayScenes.parse({
      'schemaVersion': 1,
      'revision': 3,
      'mode': 'fleet',
      'status': 'notMember',
      'fleet': {'status': 'notMember'},
      'organizations': const [],
    });
    expect(state.status, 'notMember');
    expect(
      projectOverlayScene(state).fallbackReasonKey,
      'overlay.source.unavailable',
    );
    final followed = BridgeOverlayScenes.parse({
      'schemaVersion': 1,
      'revision': 3,
      'mode': 'auto',
      'status': 'notMember',
      'fleet': {'status': 'notMember'},
      'organizations': const [],
    });
    expect(
      projectOverlayScene(followed).fallbackReasonKey,
      'overlay.source.unavailable',
      reason: 'the main fleet page is followed in automatic mode',
    );
    expect(
      BridgeOverlayScenes.parse({
        'schemaVersion': 1,
        'revision': 3,
        'mode': 'auto',
        'status': 'ready',
        'fleet': {'status': 'ready', 'name': 'Domino Pizza'},
        'organizations': const [],
      }).fleetName,
      'Domino Pizza',
    );
  });
}
