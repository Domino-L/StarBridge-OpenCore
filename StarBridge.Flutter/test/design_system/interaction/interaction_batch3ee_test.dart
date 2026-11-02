import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_appearance_center_entry_test.dart'
    show EntryPort;
import '../../features/overlay_settings/overlay_appearance_configuration_test.dart'
    as config;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> _frames(WidgetTester tester, [int count = 2]) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FocusNode _entryFocus(WidgetTester tester, Finder finder) {
  final focus = switch (tester.widget(finder)) {
    MenuItemButton(:final focusNode) => focusNode,
    SuitePressable(:final focusNode) => focusNode,
    _ => null,
  };
  expect(focus, isNotNull);
  expect(focus!.canRequestFocus, isTrue);
  return focus;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite real Tab Enter backdrop selection stays in protected panel and saves the choice',
      (tester) async {
        size(tester, const Size(1280, 900));
        final configuration = OverlayAppearanceConfiguration.fromMap(
          config.withGlobalField(),
        );
        final port = EntryPort(configurations: [configuration]);
        final module = OverlayWorkspaceModule(port);
        const fieldKey = Key('appearance-config-global-backdrop');
        try {
          await module.initialize();
          final confirmed = module.projection.value.snapshot;
          final settings = module.projection.value.settings!.toMap();
          final before = module.projection.value.appearanceOptions;
          final runtime = List.of(port.storage.runtimeActions);
          await tester.pumpWidget(
            scopedApp(
              OverlayAppearancePreviewPage(
                module: module,
                port: port,
                appearanceId: 'Default',
              ),
              suite,
            ),
          );
          await _frames(tester, 12);
          final field = find.byKey(fieldKey);
          await tester.ensureVisible(field);
          await _frames(tester, 6);
          final row = find.descendant(
            of: field,
            matching: find.byType(StarBridgeActionRow),
          );
          expect(row, findsOneWidget);
          final reference = tester.widget<StarBridgeActionRow>(row).focusNode;
          expect(reference, isNotNull);
          expect(reference!.canRequestFocus, isTrue);
          final raw = find.descendant(
            of: field,
            matching: find.byType(RawMenuAnchor),
          );
          expect(raw, findsOneWidget);
          final controller = tester.widget<RawMenuAnchor>(raw).controller;
          expect(controller.isOpen, isFalse);
          var reached = false;
          for (var step = 0; step < 96; step++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await _frames(tester);
            if (identical(FocusManager.instance.primaryFocus, reference)) {
              reached = true;
              break;
            }
          }
          expect(reached, isTrue, reason: 'Real Tab must reach the menu.');
          expect(module.projection.value.appearanceOptions, same(before));
          expect(port.storage.mutations, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _frames(tester);
          expect(controller.isOpen, isTrue);
          final surface = find.byWidgetPredicate(
            (widget) =>
                widget is SuiteSurfaceTransition &&
                widget.kind == SurfaceKind.menu,
          );
          expect(surface, findsOneWidget);
          expect(
            tester.widget<SuiteSurfaceTransition>(surface).animation.value,
            1,
          );
          final original = find.byKey(const ValueKey<Object>((fieldKey, 0)));
          final black = find.byKey(const ValueKey<Object>((fieldKey, 1)));
          expect(original, findsOneWidget);
          expect(black, findsOneWidget);
          expect(
            FocusManager.instance.primaryFocus,
            same(_entryFocus(tester, original)),
          );
          final area = port.live.protections.last.firstWhere(
            (a) => a.height == 1,
          );
          final rect = tester.getRect(black);
          expect(rect.left, greaterThanOrEqualTo(area.x * 1280));
          expect(rect.right, lessThanOrEqualTo((area.x + area.width) * 1280));
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await _frames(tester);
          expect(
            FocusManager.instance.primaryFocus,
            same(_entryFocus(tester, black)),
          );
          expect(
            configuration.readFields(module.projection.value.appearanceOptions),
            {'backdrop': false},
          );
          expect(port.storage.mutations, isEmpty);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _frames(tester, 6);
          expect(controller.isOpen, isFalse);
          expect(surface, findsNothing);
          expect(FocusManager.instance.primaryFocus, same(reference));
          expect(
            configuration.readFields(module.projection.value.appearanceOptions),
            {'backdrop': true},
          );
          expect(configuration.readFields(before), {'backdrop': false});
          // The choice saved on its own, settings untouched.
          expect(module.projection.value.dirty, isFalse);
          expect(module.projection.value.snapshot, isNot(same(confirmed)));
          expect(module.projection.value.settings!.toMap(), settings);
          expect(
            configuration.readFields(
              port.storage.mutations.single.appearanceOptions!,
            ),
            {'backdrop': true},
          );
          expect(port.storage.runtimeActions, runtime);
          expect(
            tester
                .widget<StarBridgeSelectField<int>>(
                  find.descendant(
                    of: field,
                    matching: find.byType(StarBridgeSelectField<int>),
                  ),
                )
                .value,
            1,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester, 6);
          module.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
