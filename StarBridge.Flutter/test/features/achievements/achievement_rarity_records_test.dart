import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievement_extras.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';
import 'package:starbridge_flutter/features/achievements/achievement_sources.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';

final _at = DateTime.utc(2026, 11, 3);
final _definition = achievementCatalog.firstWhere(
  (d) => d.id == 'contract-first',
);
const _record = ContractRecordText(
  '第一单：需要战术打击群 · 11月3日',
  '第一單：需要戰術打擊群 · 11月3日',
  'First contract: Tactical Strike Group · Nov 3',
);
const _scm = AchievementDefinition(
  id: 'scm-test',
  nameKey: '',
  conditionKey: '',
  memoryKey: '',
  earnedAsset: '',
  lockedAsset: '',
  source: AchievementSource.scm,
  rarity: AchievementRarity.legendary,
  serverName: 'SCM award',
  serverMemory: 'SCM memory',
);
Map<String, Object?> _rarity(
  Map<String, Object?> values, {
  int active = 50,
}) => {
  'schemaVersion': 1,
  'windowDays': 30,
  'activeAccounts': active,
  'computedAt': _at.toIso8601String(),
  'percentages': values,
  'tiers': {if (values.containsKey('contract-first')) 'contract-first': 'rare'},
};
AchievementCollection _collection({
  int? value,
  String? tier = 'rare',
  bool earned = true,
  bool record = true,
}) => AchievementCollection(
  generation: 1,
  status: AchievementCollectionStatus.ready,
  earnedAt: earned ? {_definition.id: _at} : {},
  percentages: value == null ? {} : {_definition.id: value, _scm.id: value},
  tiers: value == null || tier == null
      ? {}
      : {_definition.id: tier, _scm.id: tier},
  contractRecords: record ? {_definition.id: _record} : {},
);
Widget _app(Locale locale, Widget child, {double scale = 1}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
void main() {
  test(
    'shared rarity fixtures carry both server tiers and empty population',
    () {
      final samples = jsonDecode(
        File('../contracts/achievements/rarity-response.json')
            .readAsStringSync(),
      ) as Map;
      final available = samples['available'];
      expect(
        parseAchievementTiers(available).values,
        containsAll(['rare', 'veryRare']),
      );
      expect(parseAchievementRarity(available), isNotEmpty);
      expect(
        parseAchievementTiers(samples['insufficientActiveAccounts']),
        isEmpty,
      );
      final data = BridgeAchievementCollection.parseCollection({
        'earnedAt': <String, Object?>{},
        'rarity': available,
      }, 1);
      expect(data.tiers, parseAchievementTiers(available));
    },
  );
  test('rarity parser accepts bounded basis points and hides insufficient population', () {
    expect(parseAchievementRarity(_rarity({'contract-first': 320})), {
      'contract-first': 320,
    });
    expect(parseAchievementRarity(_rarity({}, active: 49)), isEmpty);
    for (final value in [
      null,
      _rarity({'contract-first': 1}, active: 49),
      _rarity({'bad id': 1}),
      _rarity({'contract-first': -1}),
      _rarity({'contract-first': 10001}),
      _rarity({'contract-first': 1.2}),
      _rarity({for (var i = 0; i < 257; i++) 'id-$i': 1}),
      {..._rarity({}), 'schemaVersion': 2},
      {..._rarity({}), 'windowDays': 7},
      {..._rarity({}), 'computedAt': 'invalid'},
    ]) {
      expect(parseAchievementRarity(value), isEmpty);
    }
  });
  test('tiers accept only server enum values and known percentage keys', () {
    final raw = _rarity({'contract-first': 100});
    expect(
      parseAchievementTiers({
        ...raw,
        'tiers': {'contract-first': 'rare'},
      }),
      {'contract-first': 'rare'},
    );
    expect(
      parseAchievementTiers({
        ...raw,
        'tiers': {'contract-first': 'veryRare'},
      }),
      {'contract-first': 'veryRare'},
    );
    for (final tiers in [
      null,
      {'contract-first': 'ultraRare'},
      {'other': 'rare'},
    ]) {
      expect(parseAchievementTiers({...raw, 'tiers': tiers}), isEmpty);
    }
  });
  test('optional invalid extras never invalidate the earned collection', () {
    final value = BridgeAchievementCollection.parseCollection({
      'earnedAt': {'contract-first': _at.toIso8601String()},
      'rarity': _rarity({'bad id': 3}),
      'contractRecords': {
        'contract-first': {'en': 'incomplete'},
      },
    }, 1);
    expect(value.isEarned('contract-first'), isTrue);
    expect(value.percentages, isEmpty);
    expect(value.contractRecords, isEmpty);
  });
  test(
    'record bridge consumes three locales and rejects malformed records',
    () {
      final raw = {
        'contract-first': {
          'zhCN': _record.zhCN,
          'zhTW': _record.zhTW,
          'en': _record.en,
        },
      };
      final collection = BridgeAchievementCollection.parseCollection({
        'earnedAt': {'contract-first': _at.toIso8601String()},
        'rarity': _rarity({'contract-first': 320}),
        'contractRecords': raw,
      }, 1);
      expect(collection.percentages['contract-first'], 320);
      expect(collection.tiers['contract-first'], 'rare');
      expect(collection.contractRecords['contract-first']!.zhCN, _record.zhCN);
      expect(
        parseContractRecords({
          'contract-first': {'zhCN': '\n', 'zhTW': 'ok', 'en': 'ok'},
        }),
        isEmpty,
      );
      expect(parseContractRecords({'other': raw['contract-first']}), isEmpty);
      final combined = combineAchievementSources(
        collection,
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          catalog: const [_scm],
        ),
        achievementCatalog,
      );
      expect(combined.percentages['contract-first'], 320);
      expect(combined.tiers['contract-first'], 'rare');
      expect(combined.contractRecords['contract-first']!.en, _record.en);
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    final strings = AppStrings.resolve(locale);
    test('$locale server tiers override rounded percentages', () {
      for (final row in [
        (1001, null, null),
        (1000, null, null), // 101/1009 truncates to 1000 but is not rare.
        (1000, 'rare', 'achievements.appRarity.rare'),
        (101, 'rare', 'achievements.appRarity.rare'),
        (100, 'rare', 'achievements.appRarity.rare'), // 2/199 is above 1%.
        (100, 'veryRare', 'achievements.appRarity.ultraRare'),
        (99, null, null), // Missing tier must never be inferred.
        (0, 'veryRare', 'achievements.appRarity.ultraRare'),
      ]) {
        final p = AchievementPresentation(
          _definition,
          _collection(value: row.$1, tier: row.$2),
          strings,
        );
        expect(
          p.rarityLabelFor(),
          row.$3 == null ? null : strings.text(row.$3!),
        );
      }
      expect(
        AchievementPresentation(
          _definition,
          _collection(value: 320),
          strings,
        ).rarityTextFor(),
        strings
            .text('achievements.appRarity.percentage')
            .replaceAll('{percent}', '3.2'),
      );
      expect(
        AchievementPresentation(
          _definition,
          _collection(value: 5),
          strings,
        ).rarityTextFor(),
        strings.text('achievements.appRarity.belowPointOne'),
      );
      expect(
        AchievementPresentation(
          _definition,
          _collection(),
          strings,
        ).rarityTextFor(),
        isNull,
      );
      expect(
        AchievementPresentation(
          _definition,
          _collection(earned: false),
          strings,
        ).memory,
        isEmpty,
      );
      expect(
        AchievementPresentation(
          _definition,
          _collection(record: false),
          strings,
        ).memory,
        isEmpty,
      );
      expect(
        AchievementPresentation(
          _scm,
          _collection(value: 1),
          strings,
        ).rarityTextFor(),
        isNull,
      );
      expect(_scm.rarity, AchievementRarity.legendary);
    });
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$locale 320px scale=$scale ratio, label and record fit entry/detail',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final data = _collection(value: 320);
          final line = _record.localized(strings);
          final ratio = AchievementPresentation(
            _definition,
            data,
            strings,
          ).rarityTextFor()!;
          await tester.pumpWidget(
            _app(
              locale,
              SingleChildScrollView(
                child: AchievementEntry(
                  definition: _definition,
                  collection: data,
                  focusNode: focus,
                  onPressed: () {},
                  wall: true,
                ),
              ),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(ratio), findsOneWidget);
          expect(
            find.text(strings.text('achievements.appRarity.rare')),
            findsOneWidget,
          );
          expect(find.text(line), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            _app(
              locale,
              AchievementDetail(definition: _definition, collection: data),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(ratio), findsOneWidget);
          expect(find.text(line), findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(line),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            _app(
              locale,
              AchievementDetail(
                definition: _definition,
                collection: _collection(record: false),
              ),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(line), findsNothing);
          expect(find.text(ratio), findsNothing);
          expect(
            find.text(strings.text('achievements.appRarity.rare')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('$locale tier ratios fit 320px at double text size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final definition = achievementCatalog.firstWhere(
        (d) => d.id == 'hangar-home',
      );
      final data = AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'hangar-home-1': _at},
        percentages: {
          'hangar-home-1': 1000,
          'hangar-home-2': 100,
          'hangar-home-3': 5,
        },
      );
      await tester.pumpWidget(
        _app(
          locale,
          AchievementDetail(definition: definition, collection: data),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final p = AchievementPresentation(definition, data, strings);
      expect(find.textContaining(p.rarityTextFor(1)!), findsNWidgets(2));
      expect(find.textContaining(p.rarityTextFor(2)!), findsOneWidget);
      expect(find.textContaining(p.rarityTextFor(3)!), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$locale SCM keeps its own rarity and has no app percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          locale,
          AchievementDetail(
            definition: _scm,
            collection: _collection(value: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(strings.text('achievements.rarity.legendary')),
        findsOneWidget,
      );
      expect(find.byType(AchievementRarityInfo), findsOneWidget);
      expect(
        find.text(strings.text('achievements.appRarity.ultraRare')),
        findsNothing,
      );
      expect(find.textContaining('0.1%'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'series exposes exact per-rank rarity without fabricating missing ranks',
    () {
      final definition = achievementCatalog.firstWhere(
        (d) => d.id == 'hangar-home',
      );
      final data = AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'hangar-home-1': _at},
        percentages: {'hangar-home-1': 1000, 'hangar-home-2': 100},
      );
      final p = AchievementPresentation(
        definition,
        data,
        AppStrings.resolve(const Locale('zh', 'CN')),
      );
      expect(p.percentageFor(), 1000);
      expect(p.percentageFor(2), 100);
      expect(p.percentageFor(3), isNull);
    },
  );
}
