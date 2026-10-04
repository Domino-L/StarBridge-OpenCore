import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preview_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preview_content.dart';

import '../friends/social_layout_test.dart' show app;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  const scene = OverlaySceneState(
    available: true,
    sourceOwnerKey: 'fixture',
    mode: 'community',
    code: 'A',
    targets: [OverlaySceneTarget('A', '组织 A')],
    resolvedSourceIds: {'auto': 'room', 'room': 'room', 'org:A': 'org:A'},
  );
  test('preview follows Host resolution with temporary > preset > account and per-module overrides', () {
    var policy = OverlayPresetSources();
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, scene, 'Squads')!.id,
      'org:A',
    );
    policy = OverlayPresetSources(
      binding: const OverlaySourceBinding.automatic(),
      modules: {
        OverlaySourceModule.chat: OverlaySourceBinding.community(
          'A',
          'fixture',
        ),
      },
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, scene, 'Squads')!.id,
      'room',
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(
        policy,
        scene,
        'Squads',
      )!.labelId,
      isNull,
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, scene, 'Chat')!.labelId,
      'org:A',
    );
    const temporary = OverlaySceneState(
      available: true,
      sourceOwnerKey: 'fixture',
      temporarySourceId: 'org:A',
      targets: [OverlaySceneTarget('A', '组织 A')],
      resolvedSourceIds: {'auto': 'room', 'room': 'room', 'org:A': 'org:A'},
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, temporary, 'Squads')!.id,
      'org:A',
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(
        policy,
        temporary,
        'Chat',
      )!.labelId,
      isNull,
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, scene, 'Crosshair'),
      isNull,
    );
  });
  test('only preset-level unavailable organization falls back; module remains empty and foreign name is hidden', () {
    final foreign = OverlaySourceBinding.community('A', 'old-account');
    final policy = OverlayPresetSources(
      binding: foreign,
      modules: {OverlaySourceModule.chat: foreign},
    );
    expect(
      OverlayPreviewSourcePresentation.resolve(policy, scene, 'Squads')!.id,
      'room',
    );
    final chat = OverlayPreviewSourcePresentation.resolve(
      policy,
      scene,
      'Chat',
    )!;
    expect(chat.unavailable, isTrue);
    expect(chat.labelId, 'missing');
  });
  test('automatic preview trusts Host result even when room also exists', () {
    const state = OverlaySceneState(
      resolvedSourceIds: {'auto': 'local', 'room': 'room'},
    );
    final result = OverlayPreviewSourcePresentation.resolve(
      OverlayPresetSources(binding: const OverlaySourceBinding.automatic()),
      state,
      'Squads',
    )!;
    expect(result.id, 'local');
  });
  testWidgets(
    'v2 room preview ignores removed legacy scene field and updates source badges live',
    (tester) async {
      final scenes = ValueNotifier(scene);
      addTearDown(scenes.dispose);
      final policy = OverlayPresetSources(
        modules: {
          OverlaySourceModule.overview: const OverlaySourceBinding.room(),
        },
      );
      await tester.pumpWidget(
        app(
          OverlayPreviewSourceScope(
            sources: policy,
            scenes: scenes,
            child: SizedBox(
              width: 400,
              height: 200,
              child: OverlayPreviewContent(
                moduleKey: 'Squads',
                settings: settings({'scenePreference': 'Fleet'}),
                referenceSize: const Size(400, 200),
                simulate: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('overlay-preview-source-Squads')),
        findsOneWidget,
      );
      expect(find.text('当前房间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      scenes.value = const OverlaySceneState(
        sourceOwnerKey: 'fixture',
        mode: 'room',
        resolvedSourceIds: {'auto': 'room', 'room': 'room'},
      );
      await tester.pump();
      expect(
        find.byKey(const Key('overlay-preview-source-Squads')),
        findsNothing,
      );
    },
  );
}
