import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  testWidgets(
    'crosshair activation does not reparent retained slider portal nodes',
    (tester) async {
      size(tester, const Size(1280, 900));
      final enabled = ValueNotifier(false);
      addTearDown(enabled.dispose);
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (context, value, _) => OverlayWorkspaceSettingsGroup(
                  group: 'crosshair',
                  fields: overlayWorkspaceFieldSpecs
                      .where((f) => f.group == 'crosshair')
                      .toList(),
                  settings: settings({'showCrosshair': value}),
                  onChanged: (_, next) => enabled.value = next == true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Cover both directions repeatedly. The Windows engine used to retain
      // empty portal children while replacing their traversal parent, leaving
      // the native AX update incomplete (and later crashing in ChildAtIndex).
      for (var i = 0; i < 6; i++) {
        final before = portalParents(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        expect(before.length, 6);
        await tester.tap(find.byKey(const Key('overlay-field-showCrosshair')));
        await tester.pumpAndSettle();
        final after = portalParents(
          tester
              .binding
              .renderViews
              .single
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        expect(after.length, 6);
        for (final entry in before.entries) {
          if (after.containsKey(entry.key)) {
            expect(
              after[entry.key],
              entry.value,
              reason: 'A retained portal child must not move to a replacement AX parent.',
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Map<int, int> portalParents(SemanticsNode root) {
  final parents = <Object, int>{};
  final children = <int, Object>{};
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.traversalParentIdentifier != null) {
      parents[data.traversalParentIdentifier!] = node.id;
    }
    if (data.traversalChildIdentifier != null) {
      children[node.id] = data.traversalChildIdentifier!;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return {
    for (final entry in children.entries) entry.key: parents[entry.value]!,
  };
}
