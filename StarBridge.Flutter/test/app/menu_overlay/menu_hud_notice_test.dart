import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'direct HUD failure remains visible without a settings window and clears on success',
    (tester) async {
      size(tester, const Size(1400, 900));
      Widget surface(String notice, {bool preview = false}) => app(
        MenuBridgePreview(
          visible: true,
          settingsPreview: preview,
          onDismiss: () {},
          onFeatureVisible: (_, _) {},
          onFeatureAction: (_, _, _) {},
          features: {
            'hud': MenuFeatureView('ready', hudEnabled: false, notice: notice),
          },
        ),
      );
      const failure = '未完成，请检查客户端浮层设置后重试。';
      await tester.pumpWidget(surface(failure));
      await tester.pumpAndSettle();
      expect(find.text(failure), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-panel-hud')), findsNothing);
      final semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('menu-hud-notice')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.liveRegion, isTrue);

      await tester.pumpWidget(surface(''));
      await tester.pumpAndSettle();
      expect(find.text(failure), findsNothing);
      await tester.pumpWidget(surface(failure, preview: true));
      await tester.pumpAndSettle();
      expect(find.text(failure), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
