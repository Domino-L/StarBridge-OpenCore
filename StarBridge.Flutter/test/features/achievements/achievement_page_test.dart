import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_entry.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;
import 'scm_achievements_test.dart' as scm_fixture;

class _OfflineMode extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot snapshot = ConnectionModeSnapshot(
    scope: 1,
    revision: 4,
    state: ConnectionModeState.offline,
    offlineAccount: OfflineAccountDisplay('Pilot', DateTime.utc(2026, 9, 4)),
  );
  @override
  bool get failed => false;
  @override
  bool get busy => false;
  @override
  bool get allowsOnlineTraffic => false;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
  void clear() {
    snapshot = const ConnectionModeSnapshot(state: ConnectionModeState.local);
    notifyListeners();
  }
}

class _Records implements AchievementCollectionPort {
  _Records(this.awards, [this.progress, this.cachedAtUtc]);
  final Map<String, DateTime> awards;
  final Map<String, int>? progress;
  final DateTime? cachedAtUtc;
  @override
  Future<AchievementCollection> read({required int generation}) async =>
      AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.ready,
        earnedAt: awards,
        progress: progress,
        cachedAtUtc: cachedAtUtc,
      );
}

class _ScmRecords implements AchievementCollectionPort {
  const _ScmRecords();
  @override
  Future<AchievementCollection> read({required int generation}) =>
      scm_fixture.read();
}

// 原有的版面测试按最早的四个成就写死了数量和布局，继续用那四个当夹具；四城抵达的条目另有测试。
final _legacyCatalog = achievementCatalog
    .where((d) => !d.id.startsWith('journey-'))
    .toList();

Widget _app({
  required ValueListenable<AccountProjection> account,
  AchievementCollectionPort port = const UnavailableAchievementCollection(),
  AchievementCollectionPort? scmPort,
  List<AchievementDefinition>? catalog,
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode appearance = AppearanceMode.dark,
  double textScale = 1,
  ConnectionModeControl? mode,
}) => RepaintBoundary(
  key: const Key('achievement-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(appearance),
      locale,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: AchievementsPage(
        account: account,
        port: port,
        scmPort: scmPort,
        catalog: catalog ?? _legacyCatalog,
        mode: mode,
      ),
    ),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('ACHIEVEMENT_CAPTURE_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('achievement-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadPreviewMaterial(WidgetTester tester) async {
  if (const String.fromEnvironment('ACHIEVEMENT_CAPTURE_DIR').isEmpty) return;
  await tester.runAsync(() async {
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    final context = tester.element(find.byType(AchievementsPage));
    for (final definition in achievementCatalog) {
      for (final asset in [definition.lockedAsset, definition.earnedAsset]) {
        await precacheImage(AssetImage(asset), context);
      }
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide directory remains 196 wide with a 28 content gap', (
    tester,
  ) async {
    _size(tester, const Size(2400, 1000));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(account: account, scmPort: const _ScmRecords()),
    );
    await tester.pumpAndSettle();
    final search = find.byType(TextField).first;
    final content = find.text('最近收藏').first;
    final navRect = tester.getRect(search);
    expect(navRect.width, 196);
    expect(tester.getTopLeft(content).dx - navRect.right, 28);
    expect(tester.takeException(), isNull);
  });
  for (final cached in [false, true]) {
    testWidgets(
      'F directory collection bars retain confirmed counts cached=$cached',
      (tester) async {
        _size(tester, const Size(1200, 950));
        final account = ValueNotifier(achievementTestAccount(1));
        addTearDown(account.dispose);
        await tester.pumpWidget(
          _app(
            account: account,
            catalog: _futureCatalog(8, groupCount: 4),
            appearance: cached ? AppearanceMode.light : AppearanceMode.dark,
            port: _Records(
              {
                'future-0-1': DateTime.utc(2026, 10, 1),
                'future-0-2': DateTime.utc(2026, 10, 2),
                'future-4': DateTime.utc(2026, 10, 3),
                'future-1': DateTime.utc(2026, 10, 4),
              },
              null,
              cached ? DateTime.utc(2026, 10, 5) : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        double? value(String id) => tester
            .widget<LinearProgressIndicator>(
              find.byKey(Key('achievement-group-progress-$id')),
            )
            .value;
        expect(value('all'), 3 / 8);
        expect(value('bridge:g0'), 1);
        expect(value('bridge:g1'), .5);
        expect(value('bridge:g2'), 0);
        expect(
          find.byKey(const Key('achievement-group-progress-earned')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('achievement-group-bridge:g1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('achievement-filter-locked')));
        await tester.pumpAndSettle();
        expect(value('bridge:g1'), .5);
        await _loadPreviewMaterial(tester);
        await _capture(
          tester,
          'f-directory-progress-${cached ? 'light-cached' : 'dark'}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('F directory does not display unknown source as zero progress', (
    tester,
  ) async {
    _size(tester, const Size(1200, 950));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(account: account, scmPort: const _ScmRecords()),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('achievement-group-progress-all')),
      findsNothing,
    );
    for (final d in achievementCatalog) {
      expect(
        find.byKey(Key('achievement-group-progress-bridge:${d.groupId}')),
        findsNothing,
      );
    }
    expect(
      find.byKey(const Key('achievement-group-progress-scm:scm-NORMAL')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SCM catalog uses F directory, official copy, decimals and owner cleanup',
    (tester) async {
      _size(tester, const Size(1200, 950));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          port: _Records({}),
          scmPort: const _ScmRecords(),
        ),
      );
      await tester.pumpAndSettle();
      await _loadPreviewMaterial(tester);
      expect(find.byKey(const Key('achievement-search')), findsOneWidget);
      // Overview recent wall and near-target cards share the display mapping.
      expect(find.text('A title'), findsWidgets);
      expect(find.text('SCM collection 1'), findsNothing);
      expect(
        find.byKey(const Key('achievement-group-scm:scm-NORMAL')),
        findsOneWidget,
      );
      await _capture(tester, 'scm-overview-dark-1200');
      await tester.tap(
        find.byKey(const Key('achievement-group-scm:scm-NORMAL')),
      );
      await tester.pumpAndSettle();
      expect(find.text('A title'), findsWidgets);
      expect(find.text('1.2 / 2.5'), findsWidgets);
      await _capture(tester, 'scm-group-dark-1200');
      await tester.enterText(
        find.byKey(const Key('achievement-search')),
        'A title',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-entry-scm-1')), findsOneWidget);
      expect(find.text('A title'), findsWidgets);
      await tester.enterText(find.byKey(const Key('achievement-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('achievement-entry-scm-1')));
      await tester.pumpAndSettle();
      expect(find.text('已收藏 · SCM · 史诗'), findsOneWidget);
      expect(find.text('Original SCM condition'), findsWidgets);
      final detail = find.byKey(const Key('achievement-detail'));
      expect(
        find.descendant(of: detail, matching: find.text('A title')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.text('Original SCM description'),
        ),
        findsOneWidget,
      );
      await _capture(tester, 'scm-detail-dark-1200');
      account.value = achievementTestAccount(2, signedIn: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-detail')), findsNothing);
      expect(find.text('A title'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('SCM source failure retains Bridge collection in compact mode', (
    tester,
  ) async {
    _size(tester, const Size(540, 950));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(
        account: account,
        port: _Records({'first-entry': DateTime.utc(2026, 10, 1)}),
        scmPort: const UnavailableAchievementCollection(),
        appearance: AppearanceMode.light,
      ),
    );
    await tester.pumpAndSettle();
    await _loadPreviewMaterial(tester);
    expect(find.text('初入星海'), findsOneWidget);
    expect(find.byKey(const Key('achievement-scm-notice')), findsOneWidget);
    await _capture(tester, 'scm-unavailable-light-540');
    expect(tester.takeException(), isNull);
  });
  testWidgets('F capture compact collection across themes and widths', (
    tester,
  ) async {
    if (const String.fromEnvironment('ACHIEVEMENT_CAPTURE_DIR').isEmpty) return;
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    for (final appearance in AppearanceMode.values) {
      for (final width in [1200.0, 380.0, 320.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        _size(tester, Size(width, width == 1200 ? 900 : 1400));
        await tester.pumpWidget(
          _app(
            account: account,
            appearance: appearance,
            textScale: width == 320 ? 1.5 : 1,
            port: _Records(
              {
                'first-entry': DateTime.utc(2026, 10, 8, 12),
                'hangar-home-1': DateTime.utc(2026, 10, 8, 12),
                'hangar-home-2': DateTime.utc(2026, 10, 9, 12),
                'hangar-collection-1': DateTime.utc(2026, 10, 10, 12),
              },
              {'hangar-home': 4, 'hangar-collection': 4, 'hangar-paths': 1},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _loadPreviewMaterial(tester);
        await _capture(
          tester,
          'f-client-now-${appearance.name}-${width.toInt()}',
        );
        await tester.ensureVisible(
          find.byKey(const Key('achievement-entry-hangar-home')),
        );
        await tester.tap(
          find.byKey(const Key('achievement-entry-hangar-home')),
        );
        await tester.pumpAndSettle();
        await _capture(
          tester,
          'f-client-detail-${appearance.name}-${width.toInt()}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
    'F compact collection uses three large paired pictures and one card',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          port: _Records(
            {
              'first-entry': DateTime.utc(2026, 10, 8),
              'hangar-home-1': DateTime.utc(2026, 10, 8),
              'hangar-home-2': DateTime.utc(2026, 10, 9),
              'hangar-collection-1': DateTime.utc(2026, 10, 10),
            },
            {'hangar-home': 4, 'hangar-collection': 4, 'hangar-paths': 1},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _loadPreviewMaterial(tester);
      expect(find.byKey(const Key('achievement-search')), findsNothing);
      expect(find.text('已收藏 3 / 4'), findsOneWidget);
      final entries = tester
          .widgetList<AchievementEntry>(find.byType(AchievementEntry))
          .toList();
      expect(entries.where((e) => e.wall).length, 3);
      expect(entries.where((e) => !e.wall).length, 1);
      final earnedArt = find.descendant(
        of: find.byKey(const Key('achievement-entry-first-entry')),
        matching: find.byType(AchievementArt),
      );
      expect(
        tester.widget<AchievementArt>(earnedArt).size,
        inInclusiveRange(178, 220),
      );
      expect(find.text('下一目标 4 / 5 艘'), findsOneWidget);
      expect(find.text('查看详情'), findsNothing);
      await _capture(tester, 'f-client-now-dark-1200');
      await tester.tap(find.byKey(const Key('achievement-entry-hangar-home')));
      await tester.pumpAndSettle();
      expect(find.text('还差 1 艘'), findsOneWidget);
      expect(find.text('至少 20 艘'), findsOneWidget);
      final context = tester.element(find.byType(AchievementsPage));
      final dates = MaterialLocalizations.of(context);
      expect(
        find.descendant(
          of: find.byKey(const Key('achievement-date-hangar-home-1')),
          matching: find.text(
            dates.formatShortDate(DateTime.utc(2026, 10, 8).toLocal()),
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('achievement-date-hangar-home-2')),
          matching: find.text(
            dates.formatShortDate(DateTime.utc(2026, 10, 9).toLocal()),
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      await _capture(tester, 'f-client-detail-dark-1200');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F details return focus to last viewed offscreen item without moving any card',
    (tester) async {
      _size(tester, const Size(1200, 720));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      final catalog = _futureCatalog(20, groupCount: 1);
      await tester.pumpWidget(
        _app(
          account: account,
          catalog: catalog,
          port: _Records({
            for (final d in catalog) d.id: DateTime.utc(2026, 10, 8),
          }),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('achievement-collection-scroll')),
          )
          .controller!;
      final pixels = scroll.offset;
      final geometry = {
        for (final d in catalog)
          d.id: tester.getRect(find.byKey(Key('achievement-entry-${d.id}'))),
      };
      await tester.tap(find.byKey(const Key('achievement-entry-future-0')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 19; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(find.byKey(const Key('achievement-detail-next')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('achievement-detail-next')),
            )
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusContext = FocusManager.instance.primaryFocus!.context!;
      var inside = false;
      focusContext.visitAncestorElements((e) {
        if (e.widget is Dialog) inside = true;
        return true;
      });
      expect(inside, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final last = find.byKey(const Key('achievement-entry-future-19'));
      expect(tester.widget<AchievementEntry>(last).focusNode.hasFocus, isTrue);
      expect(tester.getRect(last).top, greaterThan(720));
      expect(scroll.offset, pixels);
      for (final d in catalog) {
        expect(
          tester.getRect(find.byKey(Key('achievement-entry-${d.id}'))),
          geometry[d.id],
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F large directory excludes overview duplicates and loads 24 at a time',
    (tester) async {
      _size(tester, const Size(1200, 1000));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      final catalog = _futureCatalog(100, groupCount: 4);
      await tester.pumpWidget(
        _app(
          account: account,
          catalog: catalog,
          port: _Records(
            {
              for (var i = 0; i < 70; i++)
                'future-$i': DateTime.utc(2026, 10, 1 + i % 15),
            },
            {for (var i = 0; i < 100; i++) 'future-$i': i + 1},
          ),
        ),
      );
      await tester.pumpAndSettle();
      var entries = tester
          .widgetList<AchievementEntry>(find.byType(AchievementEntry))
          .toList();
      expect(entries.length, 10);
      expect(entries.map((e) => e.definition.id).toSet().length, 10);
      await _loadPreviewMaterial(tester);
      await _capture(tester, 'f-client-future-dark-1200');
      await tester.tap(find.byKey(const Key('achievement-group-earned')));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementEntry), findsNWidgets(24));
      await tester.ensureVisible(
        find.byKey(const Key('achievement-show-more')),
      );
      await tester.tap(find.byKey(const Key('achievement-show-more')));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementEntry), findsNWidgets(48));
      final search = find.byKey(const Key('achievement-search'));
      await tester.enterText(search, 'Future 99');
      await tester.pumpAndSettle();
      expect(find.byType(AchievementEntry), findsOneWidget);
      expect(
        tester
            .widget<AchievementEntry>(find.byType(AchievementEntry))
            .definition
            .id,
        'future-99',
      );
      await tester.tap(find.byKey(const Key('achievement-filter-earned')));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementEntry), findsNothing);
      expect(find.text('没有符合条件的成就。试试其他分组、筛选或关键词。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (count, groupCount, directory) in [
    (24, 3, false),
    (25, 3, true),
    (4, 4, true),
  ]) {
    testWidgets('F shape boundary $count items in $groupCount groups', (
      tester,
    ) async {
      _size(tester, const Size(1200, 900));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          catalog: _futureCatalog(count, groupCount: groupCount),
          port: _Records({}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('achievement-search')),
        directory ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in AppStrings.supportedLocales) {
    for (final appearance in AppearanceMode.values) {
      for (final width in [320.0, 380.0]) {
        testWidgets(
          'F directory fits $locale $appearance at $width with 1.5x text',
          (tester) async {
            _size(tester, Size(width, 1000));
            final account = ValueNotifier(achievementTestAccount(1));
            addTearDown(account.dispose);
            await tester.pumpWidget(
              _app(
                account: account,
                catalog: _futureCatalog(100, groupCount: 4),
                port: _Records({}),
                locale: locale,
                appearance: appearance,
                textScale: 1.5,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byWidgetPredicate(
                (widget) => widget is DropdownButtonFormField<String>,
              ),
              findsOneWidget,
            );
            expect(
              tester.getRect(find.byKey(const Key('achievement-search'))).right,
              lessThanOrEqualTo(width),
            );
            expect(tester.takeException(), isNull);
            if (locale == const Locale('zh', 'CN') && width == 320) {
              await _loadPreviewMaterial(tester);
              await _capture(
                tester,
                'f-client-future-${appearance.name}-320-large',
              );
            }
          },
        );
      }
    }
  }
  testWidgets(
    'F hidden and SCM presentation never exposes hidden conditions or grants from progress',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      final first = achievementCatalog.first;
      final hidden = AchievementDefinition(
        id: 'hidden',
        nameKey: 'Secret name',
        conditionKey: 'Secret condition',
        memoryKey: first.memoryKey,
        earnedAsset: first.earnedAsset,
        lockedAsset: first.lockedAsset,
        hidden: true,
        source: AchievementSource.scm,
        rarity: AchievementRarity.rare,
      );
      await tester.pumpWidget(
        _app(
          account: account,
          catalog: [achievementCatalog[1], hidden],
          port: _Records({}, {'hangar-home': 20}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已收藏 0 / 2'), findsOneWidget);
      expect(find.text('Secret condition'), findsNothing);
      expect(find.text('稀有'), findsNothing);
      await tester.tap(find.byKey(const Key('achievement-entry-hidden')));
      await tester.pumpAndSettle();
      expect(find.text('尚未收藏 · SCM · 稀有'), findsOneWidget);
      expect(find.text('Secret name'), findsNothing);
      expect(find.text('Secret condition'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('条件已满足，等待授奖确认'), findsOneWidget);
      expect(find.text('星海有归舟 · I'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cold loading never paints unknown achievements as locked', (
    tester,
  ) async {
    final account = ValueNotifier(achievementTestAccount(1));
    final port = DeferredAchievementPort();
    addTearDown(account.dispose);
    await tester.pumpWidget(_app(account: account, port: port));
    await tester.pump();
    expect(find.byType(AchievementArt), findsNothing);
    expect(
      find.byKey(const Key('achievement-entry-first-entry')),
      findsNothing,
    );
    port.requests.single.completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
      ),
    );
    await tester.pumpAndSettle();
    final art = find.descendant(
      of: find.byKey(const Key('achievement-entry-first-entry')),
      matching: find.byType(AchievementArt),
    );
    expect(tester.widget<AchievementArt>(art).earned, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'network outage shows confirmed collection without contribution and clears on logout',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final account = ValueNotifier(
        achievementTestAccount(
          1,
          retainedReadId: '0123456789abcdef0123456789abcdef',
        ),
      );
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          port: _Records(
            {'first-entry': DateTime.utc(2026, 9, 4)},
            null,
            DateTime.utc(2026, 9, 5),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('achievement-offline-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('已收藏 1'), findsWidgets);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('achievement-contribute')),
            )
            .onPressed,
        isNull,
      );
      account.value = achievementTestAccount(1, signedIn: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-offline-notice')), findsNothing);
      expect(find.textContaining('已收藏 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline page retains confirmed collection but disables contribution and clears on mode change',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final mode = _OfflineMode();
      final account = ValueNotifier(achievementTestAccount(1, signedIn: false));
      addTearDown(mode.dispose);
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          mode: mode,
          port: _Records(
            {'first-entry': DateTime.utc(2026, 9, 4)},
            null,
            DateTime.utc(2026, 9, 5),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('achievement-offline-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('上次联网确认'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('achievement-contribute')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('已收藏 1'), findsWidgets);
      mode.clear();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-offline-notice')), findsNothing);
      expect(find.textContaining('已收藏 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'five-rank series keeps suffix only and exposes every requirement and peak progress',
    (tester) async {
      _size(tester, const Size(1200, 900));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      final date = DateTime.utc(2026, 10, 9);
      await tester.pumpWidget(
        _app(
          account: account,
          port: _Records(
            {'hangar-home-1': date, 'hangar-home-2': date},
            {'hangar-home': 4, 'hangar-collection': 2, 'hangar-paths': 1},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _loadPreviewMaterial(tester);
      expect(find.text('星海有归舟 · II'), findsOneWidget);
      expect(find.text('舷影成诗 · I'), findsOneWidget);
      final entry = find.byKey(const Key('achievement-entry-hangar-home'));
      final before = tester.getRect(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(tester.getRect(entry), before);
      for (var rank = 1; rank <= 5; rank++) {
        expect(
          find.byKey(Key('achievement-rank-hangar-home-$rank')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            Key(
              '${rank <= 2 ? 'achievement-date' : 'achievement-progress'}-hangar-home-$rank',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('4 / 5'), findsOneWidget);
      expect(find.text('4 / 20'), findsOneWidget);
      expect(find.text('至少 20 艘'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'hangar-five-ranks-detail');
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'five-rank details fit ${locale.toLanguageTag()} at $width with large text and unknown progress',
        (tester) async {
          _size(tester, Size(width, 900));
          final account = ValueNotifier(achievementTestAccount(1));
          addTearDown(account.dispose);
          await tester.pumpWidget(
            _app(
              account: account,
              locale: locale,
              textScale: 1.8,
              port: _Records({}),
            ),
          );
          await tester.pumpAndSettle();
          final entry = find.byKey(const Key('achievement-entry-hangar-paths'));
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          for (var rank = 1; rank <= 5; rank++) {
            expect(
              find.byKey(Key('achievement-rank-hangar-paths-$rank')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('achievement-progress-hangar-paths-1')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final locale in AppStrings.supportedLocales) {
    for (final appearance in AppearanceMode.values) {
      for (final width in [320.0, 800.0, 1200.0]) {
        testWidgets(
          'collection and inspector fit $locale $appearance at $width',
          (tester) async {
            _size(tester, Size(width, 820));
            final account = ValueNotifier(achievementTestAccount(1));
            addTearDown(account.dispose);
            await tester.pumpWidget(
              _app(
                account: account,
                port: _Records({}),
                locale: locale,
                appearance: appearance,
              ),
            );
            await tester.pumpAndSettle();
            final strings = AppStrings.resolve(locale);
            expect(
              find.text(strings.text('achievements.locked')),
              findsOneWidget,
            );
            expect(
              find.text(strings.text('achievements.firstEntry.condition')),
              findsOneWidget,
            );
            expect(find.textContaining('0 / 4'), findsOneWidget);
            final entry = find.byKey(
              const Key('achievement-entry-first-entry'),
            );
            final before = tester.getRect(entry);
            await tester.ensureVisible(entry);
            final scrolled = tester.getRect(entry);
            await tester.tap(entry);
            await tester.pumpAndSettle();
            expect(tester.getRect(entry), scrolled);
            final dialog = tester.getRect(
              find.byKey(const Key('achievement-detail')),
            );
            expect(dialog.left, greaterThanOrEqualTo(0));
            expect(dialog.right, lessThanOrEqualTo(width));
            expect(dialog.bottom, lessThanOrEqualTo(820));
            await tester.tap(find.byKey(const Key('achievement-detail-close')));
            await tester.pumpAndSettle();
            expect(tester.getRect(entry), scrolled);
            expect(before.width, scrolled.width);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'opening and closing details preserves every row and scroll position',
    (tester) async {
      _size(tester, const Size(1200, 720));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      final catalog = List.generate(
        16,
        (i) => AchievementDefinition(
          id: 'synthetic-$i',
          nameKey: achievementCatalog.first.nameKey,
          conditionKey: achievementCatalog.first.conditionKey,
          memoryKey: achievementCatalog.first.memoryKey,
          earnedAsset: achievementCatalog.first.earnedAsset,
          lockedAsset: achievementCatalog.first.lockedAsset,
        ),
      );
      final awards = {
        for (var i = 0; i < 8; i++) 'synthetic-$i': DateTime.utc(2026, 10, 9),
      };
      await tester.pumpWidget(
        _app(
          account: account,
          catalog: catalog,
          port: _Records(awards),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in ['synthetic-4', 'synthetic-12']) {
        final entry = find.byKey(Key('achievement-entry-$id'));
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        final geometry = {
          for (final definition in catalog)
            definition.id: tester.getRect(
              find.byKey(Key('achievement-entry-${definition.id}')),
            ),
        };
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        final pixels = scroll.pixels;
        await tester.tap(entry);
        await tester.pumpAndSettle();
        for (final definition in catalog) {
          expect(
            tester.getRect(
              find.byKey(Key('achievement-entry-${definition.id}')),
            ),
            geometry[definition.id],
          );
        }
        expect(scroll.pixels, pixels);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsNothing);
        expect(scroll.pixels, pixels);
        for (final definition in catalog) {
          expect(
            tester.getRect(
              find.byKey(Key('achievement-entry-${definition.id}')),
            ),
            geometry[definition.id],
          );
        }
        final card = tester.widget<AchievementEntry>(entry);
        expect(card.focusNode.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
        await tester.tap(find.byKey(const Key('achievement-detail-close')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown records never claim zero; account changes dismiss old details',
    (tester) async {
      _size(tester, const Size(1200, 820));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      await tester.pumpWidget(_app(account: account));
      await tester.pumpAndSettle();
      expect(find.textContaining('— / 4'), findsOneWidget);
      expect(find.text('可获得'), findsOneWidget);
      expect(find.text('待确认'), findsNothing);
      expect(find.text('尚未收藏'), findsNothing);
      expect(find.text('未获得'), findsNothing);
      await tester.tap(find.byKey(const Key('achievement-entry-first-entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
      account.value = achievementTestAccount(2, signedIn: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement-detail')), findsNothing);
      expect(find.text('登录后查看你的成就收藏。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SCM 就绪、星海舰桥记录未知时，不把未知写成没有收藏', (tester) async {
    _size(tester, const Size(1200, 820));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(
        account: account,
        scmPort: const _ScmRecords(),
        catalog: achievementCatalog,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievement-bridge-notice')), findsOneWidget);
    expect(find.textContaining('已收藏 — / '), findsOneWidget);
    final journey = achievementCatalog.firstWhere(
      (d) => d.id == 'journey-lorville',
    );
    await tester.ensureVisible(
      find.byKey(Key('achievement-group-${journey.source.name}:${journey.groupId}')),
    );
    await tester.tap(find.byKey(Key('achievement-group-${journey.source.name}:${journey.groupId}')));
    await tester.pumpAndSettle();
    expect(find.text('待确认'), findsNothing);
    expect(find.text('你的星海收藏，从这里开始。'), findsNothing);
    expect(find.text('暂时无法确认已获得的成就。'), findsOneWidget);
    expect(find.text('可获得'), findsOneWidget);
    expect(find.text('尚未收藏'), findsOneWidget, reason: '只有筛选项');
    expect(tester.takeException(), isNull);
  });

  testWidgets('四城抵达条目：名字、未解锁图、总成就进度 x / 4', (tester) async {
    _size(tester, const Size(1200, 820));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(
        account: account,
        catalog: achievementCatalog,
        port: _Records(
          {
            'journey-lorville': DateTime.utc(2026, 12, 20),
            'journey-orison': DateTime.utc(2026, 12, 21),
          },
          {'journey-stanton': 2},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ids = tester
        .widgetList<AchievementEntry>(find.byType(AchievementEntry))
        .map((e) => e.definition.id)
        .toSet();
    expect(
      ids,
      containsAll([
        'journey-lorville',
        'journey-area18',
        'journey-orison',
        'journey-new-babbage',
        'journey-stanton',
      ]),
    );
    expect(find.text('罗威尔黄昏'), findsOneWidget);
    expect(find.text('霓虹十八区'), findsOneWidget);
    expect(find.text('云上奥里森'), findsOneWidget);
    expect(find.text('雪落新巴贝奇'), findsOneWidget);
    expect(find.text('巡礼斯坦顿'), findsOneWidget);
    expect(find.textContaining('2 / 4'), findsWidgets, reason: '总成就显示已抵达 2 座');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'earned state uses approved original and keeps condition in inspector',
    (tester) async {
      _size(tester, const Size(1200, 820));
      final account = ValueNotifier(achievementTestAccount(1));
      addTearDown(account.dispose);
      await tester.pumpWidget(
        _app(
          account: account,
          port: _Records({'first-entry': DateTime.utc(2026, 10, 9)}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 / 4'), findsOneWidget);
      expect(find.text('星汉灿烂，若出其里'), findsOneWidget);
      expect(find.text('让星海舰桥首次确认你已进入《星际公民》游戏服务器'), findsNothing);
      expect(
        tester
            .widget<AchievementArt>(
              find.descendant(
                of: find.byKey(const Key('achievement-entry-first-entry')),
                matching: find.byType(AchievementArt),
              ),
            )
            .earned,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('achievement-entry-first-entry')));
      await tester.pumpAndSettle();
      expect(find.text('让星海舰桥首次确认你已进入《星际公民》游戏服务器'), findsOneWidget);
      expect(find.textContaining('获得于'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large type remains readable in collection and detail', (
    tester,
  ) async {
    _size(tester, const Size(320, 700));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.pumpWidget(
      _app(account: account, textScale: 2, port: _Records({})),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('achievement-entry-first-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture the actual Flutter page and inspector', (tester) async {
    const captureDirectory = String.fromEnvironment('ACHIEVEMENT_CAPTURE_DIR');
    if (captureDirectory.isEmpty) return;
    _size(tester, const Size(1200, 820));
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    await tester.runAsync(() async {
      for (final font in {
        'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
        'Saira': 'assets/fonts/Saira-VF.ttf',
        'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
        'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    });
    for (final appearance in AppearanceMode.values) {
      await tester.pumpWidget(_app(account: account, appearance: appearance));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(AchievementsPage));
        for (final asset in [
          achievementCatalog.first.lockedAsset,
          achievementCatalog.first.earnedAsset,
        ]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      await tester.pumpAndSettle();
      await _capture(tester, 'flutter-${appearance.name}-unavailable');
      await tester.pumpWidget(
        _app(account: account, appearance: appearance, port: _Records({})),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'flutter-${appearance.name}-locked');
      await tester.tap(find.byKey(const Key('achievement-entry-first-entry')));
      await tester.pumpAndSettle();
      await _capture(tester, 'flutter-${appearance.name}-detail');
      await tester.tap(find.byKey(const Key('achievement-detail-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(
          account: account,
          appearance: appearance,
          port: _Records({'first-entry': DateTime.utc(2026, 10, 9)}),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'flutter-${appearance.name}-earned');
    }
  });
}

// Deliberately synthetic and test-only: never added to the product catalog.
List<AchievementDefinition> _futureCatalog(
  int count, {
  required int groupCount,
}) => List.generate(
  count,
  (i) => AchievementDefinition(
    id: 'future-$i',
    nameKey: 'Future $i',
    conditionKey: 'Archive requirement $i',
    memoryKey: achievementCatalog.first.memoryKey,
    earnedAsset: achievementCatalog.first.earnedAsset,
    lockedAsset: achievementCatalog.first.lockedAsset,
    groupId: 'g${i % groupCount}',
    groupNameKey: 'Group ${i % groupCount}',
    target: 100,
  ),
);
