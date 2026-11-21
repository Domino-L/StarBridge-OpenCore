import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_view.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievement_extras.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';

final _contracts = achievementCatalog
    .where((d) => d.groupId == 'contract')
    .toList();
final _at = DateTime.utc(2026, 11, 3);

AchievementCollection _collection(bool earned) => AchievementCollection(
  generation: 1,
  status: AchievementCollectionStatus.ready,
  earnedAt: earned ? {for (final d in _contracts) d.id: _at} : {},
  progress: const {},
  contractRecords: earned
      ? {
          for (final d in _contracts)
            d.id: const ContractRecordText(
              '本机合约记录',
              '本機合約記錄',
              'Local contract record',
            ),
        }
      : const {},
);

Widget _app(Locale locale, Widget child) => MaterialApp(
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
  home: Scaffold(body: child),
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _fullText(WidgetTester tester, String value) {
  final finder = find.text(value);
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse);
}

void main() {
  test('five one-time contract awards follow Journey in their exact order', () {
    expect(achievementCatalog.map((d) => d.groupId).toSet().toList(), [
      'journey',
      'contract',
      'hangar',
    ]);
    expect(_contracts.map((d) => d.id), [
      'contract-first',
      'contract-tsg-lead',
      'contract-tsg-complete',
      'contract-tsg-swift',
      'contract-tsg-deathless',
    ]);
    final strings = AppStrings.resolve(const Locale('zh', 'CN'));
    expect(_contracts.map((d) => strings.text(d.nameKey)), [
      '开张大吉',
      '打击群·领队',
      '打击群·凯旋',
      '打击群·闪击',
      '打击群·不灭',
    ]);
    for (final d in _contracts) {
      expect(d.groupNameKey, 'achievements.group.contract');
      expect(d.source, AchievementSource.bridge);
      expect(d.isSeries, isFalse);
      expect(d.target, isNull);
      expect(d.metricKey, isNull);
      expect(d.unitKey, isNull);
      // 11-05: TSG four have their own art pair; 11-07: contract-first too.
      expect(d.earnedAsset, 'assets/achievements/${d.id}-earned-192.webp');
      expect(d.lockedAsset, 'assets/achievements/${d.id}-locked-192.webp');
    }
  });

  test('awards need confirmed receipts and never use contract progress', () {
    final strings = AppStrings.resolve(const Locale('zh', 'CN'));
    for (final d in _contracts) {
      for (final earned in [false, true]) {
        final p = AchievementPresentation(d, _collection(earned), strings);
        expect(p.earned, earned);
        expect(p.complete, earned);
        expect(p.name, strings.text(d.nameKey));
        expect(p.progressText, isNull);
        expect(p.fraction, isNull);
        expect(p.nextTarget, isNull);
      }
      final unknown = AchievementPresentation(
        d,
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {d.id: _at},
          unknownIds: {d.id},
        ),
        strings,
      );
      expect(unknown.earned, isFalse);
      expect(unknown.status, isNull);
    }
  });

  test(
    'bridge reads contract earnedAt with only the four existing progress keys',
    () {
      final payload = <String, Object?>{
        'earnedAt': {for (final d in _contracts) d.id: _at.toIso8601String()},
        'progress': {
          'hangar-home': 1,
          'hangar-collection': 3,
          'hangar-paths': 2,
          'journey-stanton': 2,
        },
      };
      final collection = BridgeAchievementCollection.parseCollection(
        payload,
        1,
      );
      expect(collection.status, AchievementCollectionStatus.ready);
      expect(collection.earnedAt.keys, _contracts.map((d) => d.id));
      for (final d in _contracts) {
        expect(collection.isEarned(d.id), isTrue);
        expect(
          BridgeAchievementCollection.parseCollection({
            ...payload,
            'progress': {d.id: 1},
          }, 1).status,
          AchievementCollectionStatus.unavailable,
        );
      }
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    final strings = AppStrings.resolve(locale);
    test(
      '$locale has complete contract copy and resolves the minute parameter',
      () {
        expect(
          strings.text('achievements.group.contract'),
          switch (locale.countryCode) {
            'CN' => '合约',
            'TW' => '合約',
            _ => 'Contracts',
          },
        );
        for (final d in _contracts) {
          for (final key in [d.nameKey, d.conditionKey, ?d.noteKey]) {
            final value = strings.text(key);
            expect(value, isNot(key));
            expect(value, isNotEmpty);
            expect(value, isNot(contains('TODO')));
            expect(value, isNot(contains('待确认')));
            expect(value, isNot(contains('\uFFFD')));
          }
          final p = AchievementPresentation(d, _collection(false), strings);
          expect(p.condition, isNot(contains('{')));
          if (d.id != 'contract-first') {
            expect(p.name, contains('\u00B7'));
          }
        }
        final swift = _contracts.firstWhere(
          (d) => d.id == 'contract-tsg-swift',
        );
        expect(strings.text(swift.conditionKey), contains('{minutes}'));
        expect(
          AchievementPresentation(swift, _collection(false), strings).condition,
          contains('90'),
        );
      },
    );

    testWidgets(
      '$locale shows the contract category after Journey without SCM',
      (tester) async {
        _size(tester, const Size(1200, 900));
        final scroll = ScrollController();
        final focus = {for (final d in achievementCatalog) d.id: FocusNode()};
        addTearDown(scroll.dispose);
        addTearDown(() {
          for (final node in focus.values) {
            node.dispose();
          }
        });
        await tester.pumpWidget(
          _app(
            locale,
            AchievementCollectionView(
              catalog: achievementCatalog,
              collection: _collection(false),
              header: const SizedBox.shrink(),
              scrollController: scroll,
              focusNodes: focus,
              onInspect: (_, _) {},
              scope: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final journey = find.byKey(
          const Key('achievement-group-bridge:journey'),
        );
        final contract = find.byKey(
          const Key('achievement-group-bridge:contract'),
        );
        final hangar = find.byKey(const Key('achievement-group-bridge:hangar'));
        expect(journey, findsOneWidget);
        expect(contract, findsOneWidget);
        expect(hangar, findsOneWidget);
        expect(
          tester.getTopLeft(journey).dy,
          lessThan(tester.getTopLeft(contract).dy),
        );
        expect(
          tester.getTopLeft(contract).dy,
          lessThan(tester.getTopLeft(hangar).dy),
        );
        await tester.tap(contract);
        await tester.pumpAndSettle();
        final rows = tester.widgetList<AchievementEntry>(
          find.byType(AchievementEntry),
        );
        expect(
          rows.map((row) => row.definition.id),
          _contracts.map((d) => d.id),
        );
        expect(
          find.text(strings.text('achievements.contractTsgSwift.note')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final earned in [false, true]) {
      testWidgets(
        '$locale contract entry and detail fit 320 px, earned=$earned',
        (tester) async {
          _size(tester, const Size(320, 700));
          final focus = FocusNode();
          addTearDown(focus.dispose);
          for (final d in _contracts) {
            final collection = _collection(earned);
            final p = AchievementPresentation(d, collection, strings);
            await tester.pumpWidget(
              _app(
                locale,
                SingleChildScrollView(
                  child: AchievementEntry(
                    key: ValueKey(d.id),
                    definition: d,
                    collection: collection,
                    focusNode: focus,
                    onPressed: () {},
                    wall: earned,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            _fullText(tester, p.name);
            _fullText(tester, earned ? p.memory : p.condition);
            expect(
              tester.widget<AchievementArt>(find.byType(AchievementArt)).earned,
              earned,
            );
            if (p.note case final note?) {
              _fullText(tester, note);
            }
            expect(tester.takeException(), isNull);

            await tester.pumpWidget(
              _app(
                locale,
                AchievementDetail(
                  key: ValueKey('detail-${d.id}'),
                  definition: d,
                  collection: collection,
                ),
              ),
            );
            await tester.pumpAndSettle();
            _fullText(tester, p.name);
            _fullText(tester, p.condition);
            expect(
              find.text(
                strings.text(
                  earned ? 'achievements.earned' : 'achievements.locked',
                ),
              ),
              findsOneWidget,
            );
            if (earned) {
              _fullText(tester, p.memory);
            }
            if (p.note case final note?) {
              _fullText(tester, note);
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
