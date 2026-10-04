import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';

import '../../features/friends/social_layout_test.dart' show app, size;

void main() {
  for (final faded in [false, true]) {
    for (final bridge in [false, true]) {
      testWidgets(
        'foreground click does not raise back window faded=$faded bridge=$bridge',
        (tester) async {
          size(tester, const Size(1280, 720));
          final workspace = MenuWorkspaceController(
            scope: Object(),
            panels: [
              for (final id in ['back', 'front'])
                MenuPanelSpec(
                  id: id,
                  initialBounds: const Rect.fromLTWH(50, 50, 400, 300),
                ),
            ],
          );
          addTearDown(workspace.dispose);
          workspace.open('back');
          workspace.open('front');
          await tester.pumpWidget(
            app(
              MenuOverlayWorkspace(
                controller: workspace,
                panels: [
                  for (final id in ['back', 'front'])
                    MenuPanelContent(
                      id: id,
                      title: id,
                      icon: StarBridgeIconSemantic.tools,
                      builder: (_, _) => const SizedBox.expand(),
                    ),
                ],
                closeLabel: 'Close',
                moveLabel: 'Move',
                resizeLabel: 'Resize',
                bridgeStyle: bridge,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (faded) {
            await tester.pump(const Duration(seconds: 5));
            await tester.pump(const Duration(milliseconds: 220));
          }
          expect(workspace.activeId, 'front');
          await tester.tapAt(const Offset(200, 200));
          await tester.pump();
          expect(
            workspace.activeId,
            'front',
            reason: 'a click within the foreground surface must not activate the obscured window',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
