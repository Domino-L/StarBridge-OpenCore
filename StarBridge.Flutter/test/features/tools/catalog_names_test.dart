import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/tools/catalog_blueprint_grid.dart';
import 'package:starbridge_flutter/features/tools/catalog_controller.dart';
import 'package:starbridge_flutter/features/tools/catalog_names.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';

import 'catalog_browse_test.dart' as browse;
import 'catalog_samples.dart';

const zh = Locale('zh', 'CN'), tw = Locale('zh', 'TW'), en = Locale('en');

void main() {
  test('mission types: SCM Chinese, then our table, then the SCM text', () {
    expect(catalogMissionType({'missionType': 'Bounty Hunter'}, zh), '赏金猎人');
    expect(catalogMissionType({'missionType': 'Bounty Hunter'}, tw), '賞金獵人');
    expect(
      catalogMissionType({'missionType': 'Bounty Hunter'}, en),
      'Bounty Hunter',
    );
    expect(
      catalogMissionType({
        'missionType': 'Delivery',
        'missionTypeCn': '运输',
      }, zh),
      '运输',
    );
    expect(catalogMissionType({'missionType': 'Battaglia'}, zh), 'Battaglia');
    expect(catalogMissionType({}, zh), '—');
    expect(catalogMissionTypeLabel('local', zh), '本地');
    expect(catalogMissionTypeLabel('Hauling - Stellar', tw), '貨運 - 星系內');
    expect(
      catalogMissionTypeLabel('Hauling - Stellar', en),
      'Hauling - Stellar',
    );
    // SCM labels still win over raw values where our table has nothing.
    expect(
      catalogMissionTypeLabel('xyz_type', en, fallback: 'XYZ Type'),
      'XYZ Type',
    );
    expect(
      catalogMissionTypeLabel('xyz_type', zh, fallback: 'XYZ Type'),
      'XYZ Type',
    );
    expect(catalogMissionTypeLabel('local', zh, fallback: 'Local'), '本地');
    for (final (s, t) in catalogMissionTypeNames.values) {
      expect(s.trim(), isNotEmpty);
      expect(t.trim(), isNotEmpty);
    }
  });

  test('item kinds: known codes only, case-insensitive', () {
    expect(catalogBlueprintKind('wep', zh), '武器');
    expect(catalogBlueprintKind('NOZZLE', zh), '喷口');
    expect(catalogBlueprintKind('cool', tw), '冷卻器');
    // English keeps the SCM value as before, unknown or not.
    expect(catalogBlueprintKind('carryable', en), 'carryable');
    expect(catalogBlueprintKind('xyz', en), 'xyz');
    for (final locale in const [
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('zh', 'HK'),
      Locale('zh', 'MO'),
    ]) {
      expect(catalogBlueprintKind('cool', locale), '冷卻器');
    }
    expect(catalogBlueprintKind('xyz', zh), isNull);
    expect(catalogBlueprintKind(null, zh), isNull);
    expect(catalogBlueprintKindLabel('xyz', zh), 'xyz');
  });

  test('blueprint titles: drop the repeated kind word, lift the size', () {
    ({String name, String? size}) title(
      String name,
      String? kind, [
      Locale locale = zh,
      String? cn,
    ]) => catalogBlueprintTitle({
      'blueprintName': name,
      'manufacturer': ?kind,
      'blueprintNameCn': ?cn,
    }, locale);
    expect(title('Wep Tractorbeam S1 Utility', 'wep'), (
      name: 'Tractorbeam Utility',
      size: 'S1',
    ));
    expect(title('Cool Aegs S04 Javelin Scitem', 'cool'), (
      name: 'Aegs Javelin Scitem',
      size: 'S4',
    ));
    expect(title('Nozzle Fuelgiver Shin Nozzleexpensivesecure', 'nozzle'), (
      name: 'Fuelgiver Shin Nozzleexpensivesecure',
      size: null,
    ));
    expect(title('Carryable 2H Sq Collectormaterial', 'carryable'), (
      name: '2H Sq Collectormaterial',
      size: null,
    ));
    // Only a leading word equal to the kind code goes; nothing else changes.
    expect(title('Tractorbeam Wep S2', 'wep'), (
      name: 'Tractorbeam Wep',
      size: 'S2',
    ));
    expect(title('Wep', 'wep'), (name: 'Wep', size: null));
    expect(title('Wep S1', 'wep'), (name: 'Wep S1', size: null));
    // Several size words: kept as sent (only the kind word goes).
    expect(title('Wep S1 S04 Mount', 'wep'), (
      name: 'S1 S04 Mount',
      size: null,
    ));
    expect(title('WEP Laser s3', 'wep'), (name: 'Laser', size: 'S3'));
    expect(title('Laser Wep', 'wep'), (name: 'Laser Wep', size: null));
    expect(title('Wep XS04 S04Utility', 'wep'), (
      name: 'XS04 S04Utility',
      size: null,
    ));
    // English UI and SCM Chinese names are untouched.
    expect(title('Wep Tractorbeam S1 Utility', 'wep', en), (
      name: 'Wep Tractorbeam S1 Utility',
      size: null,
    ));
    expect(title('Wep Tractorbeam S1 Utility', 'wep', zh, '牵引光束'), (
      name: '牵引光束',
      size: null,
    ));
    expect(
      catalogBlueprintTitleLine({
        'blueprintName': 'Wep Tractorbeam S1 Utility',
        'manufacturer': 'wep',
      }, zh),
      'Tractorbeam Utility · S1',
    );
  });

  testWidgets('card: tidy name, size tag, Chinese kind; unknown code hidden', (
    tester,
  ) async {
    final c = CatalogController(CatalogKind.blueprints, SampleCatalogPort());
    Future<void> show(CatalogRow row, Locale locale) async {
      await tester.pumpWidget(
        browse.app(
          SingleChildScrollView(
            child: CatalogBlueprintCard(controller: c, row: row),
          ),
          locale: locale,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final row = {
      ...blueprintSample,
      'blueprintName': 'Wep Tractorbeam S1 Utility',
      'blueprintNameCn': null,
      'categoryName': 'Components',
      'manufacturer': 'wep',
    };
    await show(row, zh);
    expect(find.text('Tractorbeam Utility'), findsOneWidget);
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('舰船组件 · 武器'), findsOneWidget);
    expect(find.textContaining('wep'), findsNothing);
    await show({...row, 'manufacturer': 'zzz'}, zh);
    expect(find.text('舰船组件'), findsOneWidget);
    expect(find.textContaining('zzz'), findsNothing);
    await show(row, en);
    expect(find.text('Wep Tractorbeam S1 Utility'), findsOneWidget);
    expect(find.text('S1'), findsNothing);
    // English cards keep the SCM value exactly as before.
    expect(find.textContaining('· wep'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await browse.disposePage(tester);
    c.dispose();
  });
}
