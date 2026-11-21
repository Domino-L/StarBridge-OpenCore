import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_calm_display_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_global_group.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module_style_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_visor_layout_test.dart' show defaults, visor;

/// 11-11 user: "浮层设置应该加入全局设置，包含3d类、安静显示等等"; the plan he
/// chose ("按预览改"): a global group on top with five sections, the old places
/// only point at it, the same settings saved as before.
void main() {
  const moved = {
    'visorSize',
    'visorTilt',
    // 11-11: next to the depth
    'visorViewingDistance',
    'theme',
    'autoThemeByShip',
    'animationFrameRate',
    'calmDisplay',
    'calmWaitSeconds',
    'calmIdleOpacity',
    'calmLitOpacity',
    'calmLightWhen',
    'calmPeekHotkey',
    'enableStartupTransition',
    'startupTransitionFrameRate',
    'skipStartupTransitionWhenGameForeground',
    'autoFocusGameWindowOnOpen',
  };

  test(
    'the global group comes first and holds exactly the whole-visor settings',
    () {
      expect(overlayWorkspaceGroupOrder.first, 'global');
      expect(overlayWorkspaceNavigationGroupOrder.first, 'global');
      final global = {
        for (final spec in overlayWorkspaceFieldSpecs)
          if (spec.group == 'global') spec.field,
      };
      // the retired overall opacity (11-12) stays in the group, hidden
      expect(global, {...moved, 'opacity'});
      expect(
        overlayWorkspaceFieldSpecs
            .singleWhere((spec) => spec.field == 'opacity')
            .userVisible,
        isFalse,
      );
      // every setting is in one section, in the order the user chose
      expect(OverlayWorkspaceGlobalGroup.sections.keys, [
        'shape',
        'color',
        'calm',
        'animation',
        'openClose',
      ]);
      final listed = OverlayWorkspaceGlobalGroup.sections.values
          .expand((keys) => keys)
          .toList();
      expect(listed.toSet(), moved);
      expect(listed, hasLength(moved.length), reason: 'none twice');
    },
  );

  test('the saved settings keep their names and values', () {
    final saved = visor()
        .withValue('calmDisplay', 'On')
        .withValue('visorTilt', 28.0)
        .withValue('opacity', 0.7);
    final map = saved.toMap();
    for (final key in moved) {
      expect(map.containsKey(key), isTrue, reason: key);
    }
    expect(map['calmDisplay'], 'On');
    expect(map['visorTilt'], 28.0);
    expect(map['opacity'], 0.7);
  });

  testWidgets(
    'the global group shows its five sections and edits the same settings',
    (tester) async {
      size(tester, const Size(1280, 1600));
      final changes = <(String, Object?)>[];
      String? preset;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OverlayWorkspaceGlobalGroup(
              settings: visor(),
              onChanged: (field, value) => changes.add((field, value)),
              onExperiencePreset: (value) => preset = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('全局'), findsOneWidget);
      var last = -1.0;
      for (final section in OverlayWorkspaceGlobalGroup.sections.keys) {
        final title = find.byKey(Key('overlay-global-$section'));
        expect(title, findsOneWidget, reason: section);
        final y = tester.getTopLeft(title).dy;
        expect(y, greaterThan(last), reason: '$section in order');
        last = y;
      }
      for (final key in ['visorSize', 'visorTilt', 'theme']) {
        expect(
          find.byKey(Key('overlay-field-$key')),
          findsOneWidget,
          reason: key,
        );
      }
      // retired 11-12: no overall opacity control
      expect(find.byKey(const Key('overlay-field-opacity')), findsNothing);
      expect(find.byType(OverlayCalmDisplayControls), findsOneWidget);
      await tester.tap(find.byKey(const Key('overlay-calm-enabled')));
      await tester.pump();
      expect(changes.last, ('calmDisplay', 'On'));
      await tester.tap(find.byKey(const Key('overlay-experience-Smooth')));
      await tester.pump();
      expect(preset, 'Smooth');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (group, key) in [
    ('members', 'Members'),
    ('fleetOverview', 'Squads'),
    ('chat', 'Chat'),
  ]) {
    testWidgets(
      '$group keeps one line for calm display, which opens the global group',
      (tester) async {
        size(tester, const Size(900, 1200));
        var opened = 0;
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OverlayWorkspaceModuleStyleControls(
                group: group,
                layout: defaults(),
                settings: visor().withValue('calmDisplay', 'On'),
                onLayoutChanged: (_, _) {},
                onSettingChanged: (_, _) {},
                onOpenGlobal: () => opened++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OverlayCalmDisplayControls), findsNothing);
        expect(
          find.byKey(const Key('overlay-calm-global-link')),
          findsOneWidget,
        );
        expect(find.text('安静显示：开'), findsOneWidget);
        await tester.tap(find.byKey(const Key('overlay-open-global')));
        await tester.pump();
        expect(opened, 1, reason: key);
      },
    );
  }

  // 11-11 user: "各块宽高应该在各块位置调", a "外观" section under each block;
  // he chose: all of it in the block's own group, none left in the centre
  test(
    'each block owns its size and look; the appearance centre keeps none',
    () {
      for (final MapEntry(key: module, value: keys)
          in OverlayWorkspaceBlockLook.fields.entries) {
        for (final key in keys) {
          final spec = overlayWorkspaceFieldSpecs.singleWhere(
            (s) => s.field == key,
          );
          expect(spec.group, startsWith('look.'), reason: '$module $key');
          expect(overlayWorkspaceTriedOn(spec), key.startsWith('visor'));
        }
      }
      final centre = {
        for (final spec in overlayWorkspaceFieldSpecs)
          if (spec.group == 'appearance' && spec.userVisible) spec.field,
      };
      for (final keys in OverlayWorkspaceBlockLook.fields.values) {
        expect(centre.intersection(keys.toSet()), isEmpty);
      }
      // the behaviour groups do not list them either
      for (final group in ['members', 'chat', 'events']) {
        final listed = {
          for (final spec in overlayWorkspaceFieldSpecs)
            if (spec.group == group) spec.field,
        };
        expect(listed, isNot(contains('chatTextEdgeStrength')));
        expect(listed.where((f) => f.startsWith('visor')), isEmpty);
      }
    },
  );

  for (final (group, key, fields) in [
    // the height's adaptive switch is not offered (hidden on its own)
    ('members', 'Members', ['visorMembersAutoWidth', 'visorMembersHeight']),
    (
      'chat',
      'Chat',
      ['visorChatAutoWidth', 'visorChatPlate', 'chatTextEdgeStrength'],
    ),
    ('events', 'Events', ['visorEventsAutoWidth']),
  ]) {
    testWidgets('$group shows its size and look under its own look title', (
      tester,
    ) async {
      size(tester, const Size(900, 1600));
      final changes = <(String, Object?)>[];
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OverlayWorkspaceModuleStyleControls(
              group: group,
              layout: defaults(),
              settings: visor()
                  .withValue('showChat', true)
                  .withValue('showEventNotifications', true),
              onLayoutChanged: (_, _) {},
              onSettingChanged: (field, value) => changes.add((field, value)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.byKey(Key('overlay-module-look-$key'));
      expect(title, findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      final look = find.byKey(Key('overlay-block-look-$key'));
      for (final field in fields) {
        final control = find.descendant(
          of: look,
          matching: find.byKey(Key('overlay-field-$field')),
        );
        expect(control, findsOneWidget, reason: field);
        expect(
          tester.getTopLeft(control).dy,
          greaterThan(tester.getTopLeft(title).dy),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
