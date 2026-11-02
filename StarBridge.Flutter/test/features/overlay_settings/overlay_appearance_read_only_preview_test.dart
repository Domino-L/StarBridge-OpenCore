import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_appearance_preview_page_test.dart' show Workspace, Preview;

void main() {
  testWidgets(
    'read-only preview reuses native open, protection and close without configuration or saves',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace()..guideSeen = false;
      final native = Preview();
      final module = OverlayWorkspaceModule(storage);
      addTearDown(module.dispose);
      await module.initialize();
      final runtimeBefore = List.of(storage.runtimeActions);
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: native,
            appearanceId: 'Default',
            readOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(native.opens, hasLength(1));
      expect(native.protections, hasLength(1));
      expect(native.protections.single, hasLength(1));
      expect(native.plays, isEmpty);
      expect(storage.guideWrites, 0);
      expect(
        find.byKey(const Key('appearance-preview-inspector')),
        findsNothing,
      );
      for (final name in ['save', 'collapse', 'switch-side', 'skin']) {
        expect(find.byKey(Key('appearance-preview-$name')), findsNothing);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(storage.mutations, isEmpty);
      expect(storage.runtimeActions, runtimeBefore);
      await tester.tap(find.byKey(const Key('appearance-preview-exit')));
      await tester.pumpAndSettle();
      expect(native.closes, 1);
      expect(storage.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
