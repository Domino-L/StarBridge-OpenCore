import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/hangar/hangar_inventory_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_inventory_module.dart';
import 'package:starbridge_flutter/features/hangar/hangar_inventory_port.dart';

import 'hangar_inventory_test.dart';

void main() {
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'inventory review fits narrow and wide ${locale.toLanguageTag()} ${mode.name}',
        (tester) async {
          if (const bool.fromEnvironment('HANGAR_INVENTORY_GOLDENS')) {
            for (final font in {
              'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
              'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
              'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
            }.entries) {
              await (FontLoader(
                font.key,
              )..addFont(rootBundle.load(font.value))).load();
            }
          }
          final module = HangarInventoryModule(VisualInventory());
          for (final size in const [Size(1120, 720), Size(440, 900)]) {
            await tester.binding.setSurfaceSize(size);
            await tester.pumpWidget(
              MaterialApp(
                locale: locale,
                supportedLocales: const [
                  Locale('zh', 'CN'),
                  Locale('zh', 'TW'),
                  Locale('en'),
                ],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: buildStarBridgeTheme(
                  FutureRestraintStyle.resolve(mode),
                  locale,
                ),
                home: Scaffold(
                  body: HangarInventoryPage(module: module, onBack: () {}),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (module.pending == null) {
              final scenario = tester.widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>).at(1),
              );
              scenario.onChanged!('expanded');
              await tester.pump();
              await tester.tap(find.byKey(const Key('inventory-preview')));
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('HANGAR_INVENTORY_GOLDENS') &&
                locale.countryCode == 'CN') {
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile(
                  '../../../build/hangar_inventory_${mode.name}_${size.width.toInt()}.png',
                ),
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
          module.dispose();
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }
  testWidgets(
    'test inventory offers preview then confirmation and saved feedback',
    (tester) async {
      final module = HangarInventoryModule(TestInventory());
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: HangarInventoryPage(module: module, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试机库'), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory-preview')));
      await tester.pumpAndSettle();
      expect(find.text('确认保存'), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory-save')));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
      module.dispose();
    },
  );
}

class VisualInventory extends TestInventory {
  static const ships = [
    HangarInventoryShip(
      '1',
      'F7C-M Super Hornet Mk II',
      'F7C-M 超级大黄蜂 Mk II',
      'F7C-M 超級大黃蜂 Mk II',
      'small',
    ),
    HangarInventoryShip('2', 'F8C Lightning', 'F8C 闪电', 'F8C 閃電', 'small'),
    HangarInventoryShip('3', 'Dragonfly Black', '黑色蜻蜓', '黑色蜻蜓', 'small'),
    HangarInventoryShip('4', 'Ironclad Assault', '铁甲 突袭', '鐵甲 突襲', 'large'),
    HangarInventoryShip('5', 'Idris-P Frigate', '伊德里斯-P', '伊德里斯-P', 'capital'),
    HangarInventoryShip('6', 'Nox', 'NOX', 'NOX', 'small'),
  ];
  VisualInventory() {
    stored = HangarInventorySnapshot(
      1,
      DateTime.utc(2026, 9, 3, 12),
      ships.take(3).toList(),
    );
  }
  @override
  Future<HangarInventoryImport> preview(
    String account,
    String scenario,
    String key,
    int revision,
  ) async =>
      const HangarInventoryImport('op', 1, 'digest', ships, 3, 0, 3, false);
}
