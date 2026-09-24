import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/shell/widgets/shell_workspace.dart';
import 'package:starbridge_flutter/app/shell/shell_navigation_controller.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';

import '../features/personal_profile/profile_polish_regression_test.dart'
    show app;

void main() {
  testWidgets(
    'profile entry and exit do not repaint the whole page each animation frame',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      await module.initialize();
      var paints = 0;
      FeatureDescriptor feature(String id, Widget child) => FeatureDescriptor(
        id: id,
        route: '/$id',
        labelKey: id,
        descriptionKey: id,
        icon: StarBridgeIconSemantic.profile,
        navigationRegion: NavigationRegion.accountMenu,
        order: 1,
        buildDestination: (_) => child,
      );
      final profile = feature(
        'profile',
        _Probe(
          onPaint: () => paints++,
          child: PersonalProfilePage(module: module),
        ),
      );
      final other = feature('other', const ColoredBox(color: Colors.black));
      Future<void> show(FeatureDescriptor selected) async {
        await tester.pumpWidget(
          app(
            Theme(
              data: buildStarBridgeTheme(
                FutureRestraintStyle.resolve(AppearanceMode.dark),
                const Locale('zh', 'CN'),
              ),
              child: ShellWorkspace(
                selected: selected,
                interaction: NavigationInteraction.pointer,
              ),
            ),
          ),
        );
      }

      await show(other);
      await tester.pumpAndSettle();
      await show(profile);
      // A page change must not translate the entire desktop-sized raster layer.
      // Paint counts alone miss this: a cached subtree can still raster slowly.
      final workspaceOrigin = tester.getTopLeft(find.byType(ShellWorkspace));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byType(PersonalProfilePage)),
          workspaceOrigin,
        );
      }
      final entryPaints = paints;
      await tester.pumpAndSettle();
      paints = 0;
      await show(other);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      debugPrint(
        'Profile transition subtree paints: entry=$entryPaints exit=$paints',
      );
      expect(entryPaints, lessThanOrEqualTo(3));
      expect(paints, lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    },
  );
}

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) => _PaintProbe(onPaint);
}

class _PaintProbe extends RenderProxyBox {
  _PaintProbe(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
