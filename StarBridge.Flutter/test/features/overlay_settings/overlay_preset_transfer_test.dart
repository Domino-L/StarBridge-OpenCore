import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import '../friends/social_layout_test.dart' show app, size;

final layout = [
  for (final key in ['Notice', 'Squads', 'Members', 'Chat'])
    OverlayWorkspaceLayoutItem(
      key: key,
      x: 0,
      y: 0,
      width: 0.2,
      height: 0.2,
      horizontalAnchor: 'Left',
      verticalAnchor: 'Top',
      isLocked: false,
      textOpacity: 1,
      backgroundOpacity: 0.5,
    ),
];

void main() {
  final privateSources = OverlayPresetSources(
    binding: OverlaySourceBinding.community('private-org', 'private-owner'),
    autoSwitch: true,
    modules: {
      OverlaySourceModule.chat: OverlaySourceBinding.community(
        'private-chat',
        'private-owner',
      ),
      OverlaySourceModule.members: const OverlaySourceBinding.room(),
    },
  );
  test(
    'clipboard export and hostile import remove identities and auto switch',
    () {
      final original = OverlayPresetTransfer(
        name: 'Fixture',
        settings: settings(),
        layout: layout,
        sources: privateSources,
      );
      final serialized = original.serialize();
      expect(serialized, isNot(contains('private-')));
      final restored = OverlayPresetTransfer.parse(serialized);
      expect(restored.removedOrganizationBindings, isTrue);
      expect(restored.sources!.autoSwitch, isFalse);
      expect(restored.sources!.binding.mode, OverlaySourceMode.auto);
      expect(
        restored.sources!.forModule(OverlaySourceModule.members).mode,
        OverlaySourceMode.room,
      );
      final hostile = jsonDecode(serialized) as Map<String, dynamic>;
      hostile['sources'] = privateSources.toMap();
      hostile['removedOrganizationBindings'] = false;
      expect(
        OverlayPresetTransfer.parse(jsonEncode(hostile)).serialize(),
        isNot(contains('private-')),
      );
      expect(
        OverlayPresetTransfer.parse(jsonEncode(hostile))
            .removedOrganizationBindings,
        isTrue,
      );
      final room = OverlayPresetSources(
        binding: const OverlaySourceBinding.room(),
        autoSwitch: true,
      ).forTransfer();
      expect(room.binding.mode, OverlaySourceMode.room);
      expect(room.autoSwitch, isFalse);
      expect(room.hasOrganizationBindings, isFalse);
    },
  );
  test('legacy clipboard stays four fields; malformed policy is rejected', () {
    final legacy = OverlayPresetTransfer(
      name: 'Fixture',
      settings: settings(),
      layout: layout,
    ).serialize();
    expect((jsonDecode(legacy) as Map).length, 4);
    expect(OverlayPresetTransfer.parse(legacy).sources, isNull);
    final v2 = jsonDecode(
      OverlayPresetTransfer(
        name: 'Fixture',
        settings: settings(),
        layout: layout,
        sources: privateSources,
      ).serialize(),
    ) as Map<String, dynamic>;
    for (final value in [
      {...v2, 'sources': {}},
      {...v2, 'removedOrganizationBindings': 'true'},
      {...v2, 'schemaVersion': 3},
      {...v2, 'extra': true},
    ]) {
      expect(
        () => OverlayPresetTransfer.parse(jsonEncode(value)),
        throwsFormatException,
      );
    }
  });
  test('chat v2 parsing sanitizes sources while preserving room and removal notice', () {
    final detail = CommunityChatDetail.parse({
      'attachment': {
        'kind': 'overlay_preset',
        'title': 'Fixture',
        'summary': 'Fixture',
        'overlayPresetPackage': jsonEncode({
          'Version': 2,
          'Name': 'Fixture',
          'Settings': 'settings',
          'Layout': 'layout',
          'Sources': privateSources.toMap(),
          'RemovedOrganizationBindings': false,
        }),
      },
    });
    final package = detail.attachment!['overlayPresetPackage'] as String;
    expect(package, isNot(contains('private-')));
    final body = jsonDecode(package) as Map;
    expect(body['RemovedOrganizationBindings'], isTrue);
    expect(body['Sources']['autoSwitch'], isFalse);
  });
  testWidgets(
    'v2 preview describes sanitized module sources and removal before confirmation',
    (tester) async {
      size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        app(
          OverlayPresetImportPreview(
            name: 'Fixture',
            settings: settings(),
            layout: layout,
            currentSettings: settings(),
            sources: privateSources,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('overlay-import-removed-bindings')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已移除组织绑定，可在预设设置中重新选择。'), findsOneWidget);
      expect(find.text('当前房间'), findsOneWidget);
      expect(find.textContaining('private-'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
