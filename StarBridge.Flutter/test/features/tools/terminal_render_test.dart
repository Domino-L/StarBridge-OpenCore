import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/terminal_strings.dart';
import 'package:starbridge_flutter/features/tools/catalog_page.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/catalog_recent.dart';
import 'package:starbridge_flutter/features/tools/catalog_table.dart';
import 'package:starbridge_flutter/features/tools/cached_exec_hangar.dart';
import 'package:starbridge_flutter/features/tools/mission_records_controller.dart';
import 'package:starbridge_flutter/features/tools/mission_records_page.dart';
import 'package:starbridge_flutter/features/tools/mission_records_widgets.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';
import 'package:starbridge_flutter/features/tools/tools_card_data.dart';
import 'package:starbridge_flutter/features/tools/tools_style.dart';

import 'catalog_browse_test.dart' show size, settle, reveal, disposePage;
import 'catalog_samples.dart';
import 'mission_records_samples.dart';
import 'terminal_fixtures.dart';

class GradedCatalog extends SampleCatalogPort {
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) {
    if (operation == 'blueprints.page') {
      return Future.value({
        'total': 4,
        'rows': [
          for (var grade = 1; grade <= 4; grade++)
            {...blueprintSample, 'id': grade, 'grade': grade},
        ],
      });
    }
    return super.read(operation, parameters, refresh: refresh);
  }
}

void main() {
  for (final kind in CatalogKind.values) {
    testWidgets(
      '${kind.name} detail title is visible without scrolling at 320px, 2x, English',
      (t) async {
        size(t, 320);
        final records = RecordsPort();
        await t.pumpWidget(
          terminalApp(
            CatalogPage(
              kind: kind,
              port: SampleCatalogPort(),
              recordsPort: records,
            ),
            locale: const Locale('en'),
            scale: 2,
          ),
        );
        await settle(t);
        final id = kind == CatalogKind.missions ? missionGuid : 73;
        await reveal(t, find.byKey(Key('catalog-row-$id')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key('catalog-row-$id')));
        await settle(t);
        // Do not reveal, ensureVisible, or drag in detail mode before this check.
        final detailScroll = find.byKey(const Key('catalog-detail-scroll'));
        final scrollable = t.state<ScrollableState>(
          find
              .descendant(of: detailScroll, matching: find.byType(Scrollable))
              .first,
        );
        expect(scrollable.position.pixels, 0);
        final title = find.descendant(
          of: find.byKey(const Key('catalog-detail')),
          matching: find.text(
            kind == CatalogKind.missions ? 'Sample contract' : 'Sample helmet',
          ),
        );
        expect(title, findsOneWidget);
        final viewport = t.getRect(detailScroll), titleRect = t.getRect(title);
        expect(titleRect.top, greaterThanOrEqualTo(viewport.top));
        expect(titleRect.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(titleRect.left, greaterThanOrEqualTo(viewport.left));
        expect(titleRect.right, lessThanOrEqualTo(viewport.right));
        expect(find.byKey(const Key('catalog-other')), findsNothing);
        expect(find.byKey(const Key('mission-record-entry')), findsNothing);
        expect(find.byType(MissionRecordsImport), findsNothing);
        await t.tap(find.byKey(const Key('catalog-back')));
        await settle(t);
        expect(find.byKey(const Key('catalog-narrow')), findsOneWidget);
        final actions = [
          const Key('catalog-back'),
          const Key('catalog-refresh'),
          const Key('catalog-other'),
          if (kind == CatalogKind.missions) ...[
            const Key('mission-record-entry'),
            const Key('mission-record-import'),
          ],
        ];
        for (final key in actions) {
          await reveal(t, find.byKey(key));
          await t.pumpAndSettle();
          expect(find.byKey(key).hitTestable(), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await disposePage(t);
        records.dispose();
      },
    );
  }

  testWidgets('only selected tools filters paint a slanted face', (t) async {
    await t.pumpWidget(
      terminalApp(
        Column(
          children: [
            ToolsOption(label: '全部', selected: true, onTap: () {}),
            ToolsOption(label: 'Stanton', selected: false, onTap: () {}),
          ],
        ),
      ),
    );
    // App strings load asynchronously; the page is built on the next frame.
    await t.pump();
    expect(find.byType(MarketSlantFace), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MarketSlantFace),
        matching: find.text('全部'),
      ),
      findsOneWidget,
    );
    expect(find.text('Stanton'), findsOneWidget);
    await disposePage(t);
  });
  testWidgets('blueprint grid renders all four numeric grades as A through D', (
    t,
  ) async {
    size(t, 1440);
    await t.pumpWidget(
      terminalApp(
        CatalogPage(kind: CatalogKind.blueprints, port: GradedCatalog()),
      ),
    );
    await settle(t);
    for (var grade = 1; grade <= 4; grade++) {
      expect(
        find.descendant(
          of: find.byKey(Key('catalog-row-$grade')),
          matching: find.text(catalogGrade(grade)),
        ),
        findsOneWidget,
      );
    }
    await disposePage(t);
  });
  testWidgets(
    'hangar card advances its cached countdown without another read',
    (t) async {
      size(t, 1440);
      var elapsed = Duration.zero;
      final hangar = CachedExecHangar(
        TerminalHangarPort(),
        elapsed: () => elapsed,
      );
      await hangar.read();
      await t.pumpWidget(terminalApp(ToolsPage(hangar: hangar)));
      await settle(t);
      expect(find.text('00:10:00'), findsOneWidget);
      final siblings = <String, ToolsCardData>{
        for (final card in t.widgetList<ToolsCardData>(
          find.byType(ToolsCardData),
        ))
          if (card.id != 'exec-hangar') card.id: card,
      };
      expect(
        siblings.keys,
        unorderedEquals(['missions', 'blueprints', 'key-bindings']),
      );
      elapsed = const Duration(seconds: 2);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('00:09:58'), findsOneWidget);
      for (final card in t.widgetList<ToolsCardData>(
        find.byType(ToolsCardData),
      )) {
        if (card.id != 'exec-hangar') expect(card, same(siblings[card.id]));
      }
      await disposePage(t);
    },
  );
  test('terminal strings cover three locales and grades follow SCM numeric mapping', () {
    expect(terminalZhCn.keys.toSet(), terminalEn.keys.toSet());
    expect(terminalZhTw.keys.toSet(), terminalEn.keys.toSet());
    expect([1, 2, 3, 4].map(catalogGrade), ['A', 'B', 'C', 'D']);
    expect(catalogGrade(null), '—');
    expect(toolEntries.map((e) => e.id), [
      'exec-hangar',
      'missions',
      'blueprints',
      'key-bindings',
    ]);
  });
  testWidgets('tools are one row of equal tiles with one empty state each', (
    t,
  ) async {
    size(t, 1440);
    final records = RecordsPort()
      ..summary = {
        'schemaVersion': 1,
        'groups': [],
        'total': 0,
        'importAvailable': false,
        'importUnavailableReason': 'consentMissing',
      };
    await t.pumpWidget(terminalApp(ToolsPage(recordsPort: records)));
    await settle(t);
    for (final text in ['暂无数据', '还没有记录', '打开后显示总数', '打开按键查看后显示绑定数']) {
      expect(find.text(text), findsOneWidget);
    }
    // Importing and its reasons live inside 任务库, not on the tile.
    expect(find.byKey(const Key('mission-record-reason')), findsNothing);
    expect(find.byType(MissionRecordsImport), findsNothing);
    expect(records.calls, ['summary']);
    final cards = toolEntries
        .map((e) => t.getRect(find.byKey(Key('tool-${e.id}'))))
        .toList();
    for (var i = 1; i < cards.length; i++) {
      expect(cards[i].top, cards[0].top);
      expect(cards[i].left, greaterThan(cards[i - 1].right));
      expect(cards[i].size, cards[0].size);
    }
    await disposePage(t);
    records.dispose();
  });
  testWidgets(
    'tiles stay equal and wrap as the page narrows or tools are added',
    (t) async {
      List<Rect> rects(Iterable<ToolEntry> entries) => [
        for (final e in entries) t.getRect(find.byKey(Key('tool-${e.id}'))),
      ];
      size(t, 700);
      await t.pumpWidget(terminalApp(const ToolsPage()));
      await settle(t);
      var cards = rects(toolEntries);
      expect(cards[1].top, cards[0].top);
      expect(cards[2].top, greaterThan(cards[0].bottom));
      expect(cards[2].left, cards[0].left);
      // Equal up to layout rounding (3 columns of 900 px are not exact).
      expect(
        cards.map((c) => c.width.toStringAsFixed(1)).toSet(),
        hasLength(1),
      );
      await disposePage(t);
      // Three to a row: the fourth starts the next row at the same width.
      size(t, 900);
      await t.pumpWidget(terminalApp(const ToolsPage()));
      await settle(t);
      cards = rects(toolEntries);
      expect(cards[2].top, cards[0].top);
      expect(cards[3].top, greaterThan(cards[0].bottom));
      expect(cards[3].left, cards[0].left);
      // Equal up to layout rounding (3 columns of 900 px are not exact).
      expect(
        cards.map((c) => c.width.toStringAsFixed(1)).toSet(),
        hasLength(1),
      );
      expect(t.takeException(), isNull);
      await disposePage(t);
      // One to a row.
      size(t, 520);
      await t.pumpWidget(terminalApp(const ToolsPage()));
      await settle(t);
      cards = rects(toolEntries);
      for (var i = 1; i < cards.length; i++) {
        expect(cards[i].top, greaterThan(cards[i - 1].bottom));
        expect(cards[i].left, cards[0].left);
      }
      // Equal up to layout rounding (3 columns of 900 px are not exact).
      expect(
        cards.map((c) => c.width.toStringAsFixed(1)).toSet(),
        hasLength(1),
      );
      expect(t.takeException(), isNull);
      await disposePage(t);
      size(t, 1440);
      final more = [
        ...toolEntries,
        for (var i = 0; i < 2; i++)
          ToolEntry(
            id: 'later-$i',
            titleKey: 'navigation.tools',
            route: '/tools',
          ),
      ];
      await t.pumpWidget(terminalApp(ToolsPage(entries: more)));
      await settle(t);
      cards = rects(more);
      expect(cards[3].top, cards[0].top);
      expect(cards[4].top, greaterThan(cards[0].bottom));
      expect(cards[4].left, cards[0].left);
      expect(cards[5].left, cards[1].left);
      // Equal up to layout rounding (3 columns of 900 px are not exact).
      expect(
        cards.map((c) => c.width.toStringAsFixed(1)).toSet(),
        hasLength(1),
      );
      expect(t.takeException(), isNull);
      await disposePage(t);
    },
  );
  testWidgets('each tile shows its name and one live value', (t) async {
    size(t, 1440);
    final hangar = await terminalHangar(),
        cache = terminalCache(),
        records = RecordsPort();
    await t.pumpWidget(
      terminalApp(
        ToolsPage(hangar: hangar, cache: cache, recordsPort: records),
      ),
    );
    await settle(t);
    // Same wording as the 行政机库 page itself.
    expect(find.text('开启中'), findsOneWidget);
    expect(find.text('00:10:00'), findsOneWidget);
    Finder inTile(String id, String text) => find.descendant(
      of: find.byKey(Key('tool-$id')),
      matching: find.text(text),
    );
    expect(inTile('exec-hangar', '行政机库'), findsOneWidget);
    expect(inTile('missions', '完成过'), findsOneWidget);
    expect(inTile('missions', '3'), findsOneWidget);
    expect(inTile('missions', '次'), findsOneWidget);
    expect(inTile('blueprints', '1'), findsOneWidget);
    expect(inTile('blueprints', '张'), findsOneWidget);
    expect(inTile('key-bindings', '3'), findsOneWidget);
    expect(inTile('key-bindings', '个绑定'), findsOneWidget);
    // Nothing but the name and that value: no lamps, reminders, fastest
    // contract, categories or per-device split.
    for (final gone in ['1 · 1 · 1', '示意合约 ·', '护甲 1', '指示灯']) {
      expect(find.textContaining(gone), findsNothing);
    }
    expect(find.byType(MissionRecordsImport), findsNothing);
    expect(records.calls, ['summary']);
    await disposePage(t);
    cache.dispose();
    records.dispose();
  });
  for (final locale in AppStrings.supportedLocales) {
    for (final light in [false, true]) {
      testWidgets(
        'terminal ${locale.toLanguageTag()} light=$light at 320px and 2x',
        (t) async {
          size(t, 320);
          final hangar = await terminalHangar(),
              cache = terminalCache(),
              records = RecordsPort();
          await t.pumpWidget(
            terminalApp(
              ToolsPage(hangar: hangar, cache: cache, recordsPort: records),
              locale: locale,
              light: light,
              scale: 2,
            ),
          );
          await settle(t);
          await t.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -1600),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          for (final kind in CatalogKind.values) {
            await t.pumpWidget(
              terminalApp(
                CatalogPage(
                  kind: kind,
                  port: SampleCatalogPort(),
                  recordsPort: records,
                ),
                locale: locale,
                light: light,
                scale: 2,
              ),
            );
            await settle(t);
            expect(t.takeException(), isNull);
            final id = kind == CatalogKind.missions ? missionGuid : 73;
            await reveal(t, find.byKey(Key('catalog-row-$id')));
            await t.pumpAndSettle();
            await t.tap(find.byKey(Key('catalog-row-$id')));
            await settle(t);
            await t.drag(
              find.byKey(const Key('catalog-detail-scroll')),
              const Offset(0, -2200),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await disposePage(t);
          }
          final controller = MissionRecordsController(records);
          await controller.load();
          await t.pumpWidget(
            terminalApp(
              MissionRecordsPage(
                controller: controller,
                catalog: SampleCatalogPort(),
                known: const [missionSample],
              ),
              locale: locale,
              light: light,
              scale: 2,
            ),
          );
          await settle(t);
          await t.drag(
            find.byKey(const Key('mission-record-list')),
            const Offset(0, -1000),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await disposePage(t);
          controller.dispose();
          cache.dispose();
          records.dispose();
        },
      );
    }
  }
  for (final light in [false, true]) {
    for (final page in ['tools', 'missions', 'blueprints', 'records']) {
      testWidgets('mainstyle golden $page ${light ? 'light' : 'dark'}', (
        t,
      ) async {
        size(t, 1440);
        for (final font in {
          'Saira': 'assets/fonts/Saira-VF.ttf',
          'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(rootBundle.load(font.value));
          await loader.load();
        }
        final records = RecordsPort(), cache = terminalCache();
        cache.keysReadAt = DateTime.utc(2026, 11, 9, 10);
        final recent = CatalogRecent(MemoryCatalogRecentStore());
        await recent.switchOwner('golden');
        await recent.view(CatalogKind.missions, missionSample);
        final controller = MissionRecordsController(records);
        await controller.load();
        final hangar = await terminalHangar();
        final Widget child = switch (page) {
          'tools' => ToolsPage(
            hangar: hangar,
            cache: cache,
            recordsPort: records,
            recent: recent,
          ),
          'records' => MissionRecordsPage(
            controller: controller,
            catalog: SampleCatalogPort(),
            known: const [missionSample],
          ),
          _ => CatalogPage(
            kind: page == 'missions'
                ? CatalogKind.missions
                : CatalogKind.blueprints,
            port: SampleCatalogPort(),
            recordsPort: records,
          ),
        };
        await t.pumpWidget(
          terminalApp(
            RepaintBoundary(key: const Key('terminal-golden'), child: child),
            light: light,
          ),
        );
        await settle(t);
        if (page == 'missions' || page == 'blueprints') {
          await t.tap(
            find.byKey(
              Key('catalog-row-${page == 'missions' ? missionGuid : 73}'),
            ),
          );
          await settle(t);
        }
        expect(t.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('terminal-golden')),
          matchesGoldenFile(
            'goldens/mainstyle_${page}_${light ? 'light' : 'dark'}.png',
          ),
        );
        await disposePage(t);
        controller.dispose();
        records.dispose();
        cache.dispose();
        recent.dispose();
      });
    }
  }
}
