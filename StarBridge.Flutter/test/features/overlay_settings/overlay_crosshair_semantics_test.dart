import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fixed_previews.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_settings_ux_a_test.dart' show settings;

void main() {
  testWidgets('crosshair preview is a named actionable node after enabling', (
    tester,
  ) async {
    size(tester, const Size(1000, 700));
    final enabled = ValueNotifier(false);
    addTearDown(enabled.dispose);
    String? selection;
    await tester.pumpWidget(
      app(
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, value, _) => OverlayWorkspaceFixedPreviews(
            settings: settings({'showCrosshair': value}),
            onSelected: (value) => selection = value,
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      expect(find.bySemanticsLabel('准星'), findsNothing);
      enabled.value = true;
      await tester.pump();
      final target = find.bySemanticsLabel('准星');
      expect(target, findsOneWidget);
      final node = tester.getSemantics(target);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      expect(selection, 'crosshair');
      selection = null;
      enabled.value = false;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
