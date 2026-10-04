import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_shared_preset_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import 'overlay_preset_transfer_test.dart' show layout;

Widget polishApp(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    );

void main() {
  for (final locale in [const Locale('zh', 'CN'), const Locale('zh', 'TW')]) {
    testWidgets(
      'NightShadow uses official appearance name in card and import $locale',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final shared = settings({
          'requestedSkin': 'NightShadow',
          'skin': 'NightShadow',
        });
        await tester.pumpWidget(
          polishApp(
            Center(
              child: OverlaySharedPresetCard(
                name: '分享布局',
                preview: OverlayPresetTransfer(
                  name: '分享布局',
                  settings: shared,
                  layout: layout,
                ),
                onInspect: () {},
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('· 夜影'), findsOneWidget);
        expect(find.textContaining('暗影'), findsNothing);
        await tester.pumpWidget(
          polishApp(
            OverlayPresetImportPreview(
              name: '分享布局',
              settings: shared,
              layout: layout,
              currentSettings: null,
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('夜影'), findsOneWidget);
        expect(find.text('暗影'), findsNothing);
        expect(shared['requestedSkin'], 'NightShadow');
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('English Night Shadow name remains unchanged', () {
    expect(
      AppStrings.resolve(const Locale('en'))
          .text('overlay.workspace.option.NightShadow'),
      'Night Shadow',
    );
  });
  testWidgets(
    'shared preset card shows one name, labeled appearance and local layout',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        polishApp(
          Center(
            child: SizedBox(
              width: 280,
              child: OverlaySharedPresetCard(
                name: '夜影',
                preview: OverlayPresetTransfer(
                  name: '夜影',
                  settings: settings(),
                  layout: layout,
                ),
                onInspect: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('夜影'), findsOneWidget);
      expect(find.textContaining('外观 ·'), findsOneWidget);
      expect(find.byType(OverlayWorkspaceLayoutWorkbench), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('查看详情并导入'));
      expect(opened, 1);
    },
  );
  for (final width in [1280.0, 1440.0]) {
    testWidgets('import values stay clear of scrollbar at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        polishApp(
          OverlayPresetImportPreview(
            name: 'Layout fixture',
            settings: settings(),
            layout: layout,
            currentSettings: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(OverlayPresetImportPreview),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final viewport = tester.getRect(scroll);
      final values = find.descendant(
        of: find.byType(OverlayPresetImportPreview),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.textAlign == TextAlign.end,
        ),
      );
      expect(values, findsWidgets);
      for (final element in values.evaluate()) {
        expect(
          tester.getRect(find.byWidget(element.widget)).right,
          lessThanOrEqualTo(viewport.right - 12),
        );
      }
    });
  }
}
