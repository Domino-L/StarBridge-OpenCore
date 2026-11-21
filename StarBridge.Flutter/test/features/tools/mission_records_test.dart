import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/mission_records_strings.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/tools/catalog_page.dart';
import 'package:starbridge_flutter/features/tools/catalog_port.dart';
import 'package:starbridge_flutter/features/tools/mission_records_controller.dart';
import 'package:starbridge_flutter/features/tools/mission_records_page.dart';
import 'package:starbridge_flutter/features/tools/mission_records_port.dart';
import 'package:starbridge_flutter/features/tools/mission_records_widgets.dart';

import 'catalog_browse_test.dart'
    show app, size, settle, tap, reveal, disposePage;
import 'catalog_samples.dart';
import 'mission_records_samples.dart';

Future<MissionRecordsController> controller(RecordsPort port) async {
  final c = MissionRecordsController(port);
  await c.load();
  addTearDown(() {
    c.dispose();
    port.dispose();
  });
  return c;
}

void main() {
  test(
    'cancellation reads the committed Host result when commit won the race',
    () async {
      final port = RecordsPort()..heldRead = Completer<CatalogRow>();
      final c = await controller(port);
      final start = c.startImport();
      await Future<void>.delayed(Duration.zero);
      await c.cancelImport();
      port.completeImport(skipped: 0);
      port.heldRead!.complete(port.progress);
      await start;
      expect(c.result?['added'], 4);
      expect(c.error, isNull);
      expect(c.canImport, isTrue);
      expect(port.calls.where((r) => r == 'summary'), hasLength(2));
    },
  );

  test('a changed import gate is reread from summary; malformed summary is not empty', () async {
    final port = RecordsPort();
    final c = await controller(port);
    port.startFailure = const MissionRecordsFailure(
      'missionRecords.unavailable',
    );
    port.summary.addAll({
      'importAvailable': false,
      'importUnavailableReason': 'consentMissing',
    });
    await c.startImport();
    expect(c.canImport, isFalse);
    expect(c.reason, 'consentMissing');
    expect(port.calls, ['summary', 'importStart', 'summary']);
    port.summary.remove('groups');
    await c.load();
    expect(c.error, 'readError');
    expect(c.groups, hasLength(1));
  });

  testWidgets('read capability alone hides unsupported import controls', (
    tester,
  ) async {
    final port = RecordsPort()..importSupported = false;
    final c = await controller(port);
    await tester.pumpWidget(app(MissionRecordsImport(c)));
    await settle(tester);
    expect(find.byKey(const Key('mission-record-import')), findsNothing);
    await disposePage(tester);
  });

  testWidgets(
    'blueprint cross navigation retains mission-record capability without blueprint reads',
    (tester) async {
      size(tester, 1440);
      final port = RecordsPort();
      await tester.pumpWidget(
        app(
          CatalogPage(
            kind: CatalogKind.blueprints,
            port: SampleCatalogPort(),
            recordsPort: port,
          ),
        ),
      );
      await settle(tester);
      expect(port.calls, isEmpty);
      await tap(tester, const Key('catalog-other'));
      expect(port.calls, ['summary']);
      expect(find.byKey(const Key('mission-record-entry')), findsOneWidget);
      await disposePage(tester);
      port.dispose();
    },
  );

  testWidgets('discovering supports cancel before importStart replies', (
    tester,
  ) async {
    final port = RecordsPort()..heldStart = Completer<CatalogRow>();
    final c = await controller(port);
    await tester.pumpWidget(app(MissionRecordsImport(c)));
    await settle(tester);
    await tester.tap(find.byKey(const Key('mission-record-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('正在查找日志文件…'), findsOneWidget);
    expect(find.text('已读取 0 / 0 个文件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mission-record-cancel')));
    await tester.pump();
    expect(find.text('正在取消…'), findsWidgets);
    port.heldStart!.complete({'scanId': '07307307307307307307307307307307'});
    await tester.pump();
    await tester.pumpAndSettle();
    expect(port.calls.where((r) => r == 'importCancel'), hasLength(1));
    expect(find.byKey(const Key('mission-record-scan')), findsNothing);
    await disposePage(tester);
  });

  test(
    'sort count, fastest (unknown last), and recent without mutating summary',
    () {
      final groups = [
        MissionRecordGroup(
          record(
            key: 'a',
            count: 2,
            fastest: null,
            date: '2026-11-08T00:00:00Z',
          ),
        ),
        MissionRecordGroup(
          record(
            key: 'b',
            count: 6,
            fastest: 600,
            date: '2026-11-07T00:00:00Z',
          ),
        ),
        MissionRecordGroup(record(key: 'c', count: 3, fastest: 300)),
      ];
      expect(
        sortedMissionRecords(
          groups,
          MissionRecordsSort.count,
        ).map((g) => g.key),
        ['b', 'c', 'a'],
      );
      expect(
        sortedMissionRecords(
          groups,
          MissionRecordsSort.fastest,
        ).map((g) => g.key),
        ['c', 'b', 'a'],
      );
      expect(
        sortedMissionRecords(
          groups,
          MissionRecordsSort.recent,
        ).map((g) => g.key),
        ['c', 'a', 'b'],
      );
      expect(groups.first.key, 'a');
    },
  );

  test('three languages and minute/hour duration, optional fastest', () {
    expect(missionRecordsEn.keys.toSet(), missionRecordsZhCn.keys.toSet());
    expect(missionRecordsZhTw.keys.toSet(), missionRecordsZhCn.keys.toSet());
    final cn = AppStrings.resolve(const Locale('zh', 'CN'));
    final tw = AppStrings.resolve(const Locale('zh', 'TW'));
    final en = AppStrings.resolve(const Locale('en', 'US'));
    expect(missionRecordDuration(cn, 3900), '1 小时 5 分');
    expect(missionRecordDuration(tw, 3900), '1 小時 5 分');
    expect(missionRecordDuration(en, 3900), '1 h 5 min');
    expect(missionRecordDuration(en, 125), '2 min');
    expect(missionRecordDuration(cn, 125), '2 分');
    expect(
      missionRecordLabel(cn, MissionRecordGroup(record(fastest: null))),
      '完成 3 次',
    );
  });

  test('role split: every timed role on the card and in the details', () {
    final cn = AppStrings.resolve(const Locale('zh', 'CN'));
    final tw = AppStrings.resolve(const Locale('zh', 'TW'));
    final en = AppStrings.resolve(const Locale('en', 'US'));
    final roles = MissionRecordGroup(
      record(
        fastest: 600,
        solo: 900,
        team: 600,
        joinedFull: 720,
        joinedPartial: 120,
      ),
    );
    // User 11-13: the card lists every role that has a timed run.
    expect(missionRecordLabel(cn, roles).split(missionRecordLabelSeparator), [
      '完成 3 次',
      '单人最快 15 分',
      '组队最快 10 分',
      '加入他人·完整参与 12 分',
      '加入他人·中途加入 2 分',
    ]);
    // Solo and joined both timed: neither hides the other.
    final soloAndJoined = MissionRecordGroup(
      record(fastest: 900, solo: 900, joinedPartial: 300),
    );
    expect(
      missionRecordLabel(cn, soloAndJoined).split(missionRecordLabelSeparator),
      ['完成 3 次', '单人最快 15 分', '加入他人·中途加入 5 分'],
    );
    expect(missionRecordFastestLines(cn, roles), [
      '单人最快 15 分',
      '组队最快 10 分',
      '加入他人最快 12 分（完整参与）',
      '加入他人最快 2 分（中途加入）',
    ]);
    expect(missionRecordFastestLines(tw, roles).last, '加入他人最快 2 分（中途加入）');
    expect(missionRecordFastestLines(en, roles).first, 'Solo best 15 min');
    // No own run: only the joined lines, each saying which kind.
    final joinedOnly = MissionRecordGroup(
      record(fastest: null, joinedPartial: 300, joinedFull: 900),
    );
    expect(
      missionRecordLabel(cn, joinedOnly).split(missionRecordLabelSeparator),
      ['完成 3 次', '加入他人·完整参与 15 分', '加入他人·中途加入 5 分'],
    );
    expect(
      missionRecordLabel(en, joinedOnly).split(missionRecordLabelSeparator),
      [
        'Completed 3 times',
        'Joined from the start 15 min',
        'Joined mid-way 5 min',
      ],
    );
    expect(missionRecordFastestLines(cn, joinedOnly), [
      '加入他人最快 15 分（完整参与）',
      '加入他人最快 5 分（中途加入）',
    ]);
    // Sub-second differences decide the label; only the display rounds.
    final close = MissionRecordGroup({
      ...record(fastest: null),
      'joinedFullFastestSeconds': 300.9,
      'joinedPartialFastestSeconds': 300.1,
    });
    expect(close.joinedFastest?.full, isFalse);
    final fullOnly = MissionRecordGroup(record(fastest: null, joinedFull: 900));
    expect(
      missionRecordLabel(tw, fullOnly).split(missionRecordLabelSeparator),
      ['完成 3 次', '加入他人·完整參與 15 分'],
    );
    // Older hosts without the split keep the single line.
    expect(missionRecordFastestLines(cn, MissionRecordGroup(record())), [
      '最快 1 小时 5 分',
    ]);
    expect(
      missionRecordFastestLines(cn, MissionRecordGroup(record(fastest: null))),
      ['最快 —'],
    );
    // Sorting by fastest: your own best first, else the joined best.
    final sorted = sortedMissionRecords([
      MissionRecordGroup(record(key: 'own', fastest: 400)),
      MissionRecordGroup(
        record(key: 'joined', fastest: null, joinedPartial: 200),
      ),
      MissionRecordGroup(record(key: 'none', fastest: null)),
    ], MissionRecordsSort.fastest);
    expect(sorted.map((g) => g.key), ['joined', 'own', 'none']);
  });

  testWidgets('older records ask for one reimport', (tester) async {
    final port = RecordsPort();
    port.summary['unclassified'] = 12;
    final c = await controller(port);
    expect(c.unclassified, 12);
    await tester.pumpWidget(app(MissionRecordsImport(c)));
    await tester.pump();
    expect(
      find.text('有 12 条旧记录还没分出单人、组队和加入他人，重新导入一次就会显示最快用时（游戏日志已经删掉的补不回来）。'),
      findsOneWidget,
    );
    port.summary['unclassified'] = 0;
    await c.load();
    await tester.pump();
    expect(find.byKey(const Key('mission-record-reimport-hint')), findsNothing);
  });

  test(
    'summary is independent; repeated successful imports reread summary',
    () async {
      final port = RecordsPort()..completeImport();
      final c = await controller(port);
      expect(c.forDefinition(missionGuid.toUpperCase())?.count, 3);
      await c.startImport();
      await c.startImport();
      expect(port.calls, [
        'summary',
        'importStart',
        'importRead',
        'summary',
        'importStart',
        'importRead',
        'summary',
      ]);
      expect(c.canImport, isTrue);
      expect(c.result?['alreadyKnown'], 3);
    },
  );

  test(
    'cancel while start pending sends one cancel after scan ID arrives',
    () async {
      final port = RecordsPort()..heldStart = Completer();
      final c = await controller(port);
      final start = c.startImport();
      await c.cancelImport();
      await c.cancelImport();
      port.heldStart!.complete({'schemaVersion': 1, 'scanId': 'scan-073'});
      await start;
      expect(port.calls.where((r) => r == 'importCancel'), hasLength(1));
      expect(c.busy, isFalse);
      expect(c.error, 'cancelled');
      expect(c.result, isNull);
    },
  );

  test('retirement clears data and ignores late summary or progress', () async {
    final port = RecordsPort();
    final c = await controller(port);
    port.heldRead = Completer();
    final start = c.startImport();
    await Future<void>.delayed(Duration.zero);
    port.retire();
    port.heldRead!.complete({
      'phase': 'done',
      'result': {'added': 9},
    });
    await start;
    expect(c.groups, isEmpty);
    expect(c.visible, isFalse);
    expect(c.result, isNull);
    expect(c.busy, isFalse);
  });

  for (final supported in [true, false]) {
    for (final hasRecords in [true, false]) {
      testWidgets(
        'catalog badge and details records=$hasRecords supported=$supported',
        (tester) async {
          size(tester, 1440);
          final port = RecordsPort()..supported = supported;
          if (!hasRecords) port.summary['groups'] = [];
          await tester.pumpWidget(
            app(
              CatalogPage(
                kind: CatalogKind.missions,
                port: SampleCatalogPort(),
                recordsPort: port,
              ),
            ),
          );
          await settle(tester);
          expect(
            find.byKey(const Key('mission-record-badge')),
            supported && hasRecords ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('mission-record-entry')),
            supported ? findsOneWidget : findsNothing,
          );
          expect(port.calls, supported ? ['summary'] : isEmpty);
          await tap(tester, Key('catalog-row-$missionGuid'));
          expect(
            find.byKey(const Key('mission-record-details')),
            supported ? findsOneWidget : findsNothing,
          );
          if (supported) {
            final count = hasRecords ? '完成 3 次' : '完成 0 次';
            expect(
              find.descendant(
                of: find.byKey(const Key('mission-record-details')),
                matching: find.text(count),
              ),
              findsOneWidget,
            );
            if (hasRecords) {
              // Detail panel and the row's record column both put the count
              // and the best time on separate lines.
              expect(
                find.descendant(
                  of: find.byKey(const Key('mission-record-details')),
                  matching: find.text('最快 1 小时 5 分'),
                ),
                findsOneWidget,
              );
              expect(
                tester
                    .widget<Text>(find.byKey(const Key('mission-record-badge')))
                    .data,
                '$count$missionRecordLabelSeparator最快 1 小时 5 分',
              );
              expect(
                find.descendant(
                  of: find.byKey(const Key('mission-record-details')),
                  matching: find.text('最快用时从你接下这单算起；加入他人的单从你加入算起。'),
                ),
                findsOneWidget,
              );
            }
          }
          await disposePage(tester);
          port.dispose();
        },
      );
    }
  }

  testWidgets(
    'record names use existing page data; missing records stay codes without background calls',
    (tester) async {
      size(tester, 800);
      final port = RecordsPort();
      port.summary['groups'] = [
        record(),
        record(key: 'code:raw', definitionId: null, code: 'RAW_Code'),
      ];
      final c = await controller(port), catalog = RecordCatalog();
      await tester.pumpWidget(
        app(
          MissionRecordsPage(
            controller: c,
            catalog: catalog,
            known: const [missionSample],
          ),
        ),
      );
      await settle(tester);
      expect(find.text('示意合约'), findsOneWidget);
      // Unresolved log codes keep a distinct code face: the theme's mono
      // family (main style), not the resolved-name title style.
      final code = tester.widget<Text>(find.text('RAW_Code'));
      expect(
        code.style?.fontFamily,
        tester.element(find.text('RAW_Code')).tokens.typography.monoFamily,
      );
      expect(catalog.calls, isEmpty);
      await tap(tester, const Key('mission-record-row-code:raw'));
      expect(catalog.calls, isEmpty);
      await disposePage(tester);
    },
  );

  testWidgets(
    'unknown lookup is once per row; not found stays code without an error',
    (tester) async {
      size(tester, 800);
      final c = await controller(RecordsPort()),
          catalog = RecordCatalog()..response = null;
      await tester.pumpWidget(
        app(
          MissionRecordsPage(controller: c, catalog: catalog, known: const []),
        ),
      );
      await settle(tester);
      expect(find.text('delivery_contract_073'), findsOneWidget);
      await tap(tester, Key('mission-record-row-$missionGuid'));
      await tap(tester, Key('mission-record-row-$missionGuid'));
      expect(
        catalog.calls.where((r) => r.operation == 'missions.detail'),
        hasLength(1),
      );
      expect(catalog.calls.single.parameters, {'guid': missionGuid});
      expect(find.text('delivery_contract_073'), findsOneWidget);
      expect(find.byKey(const Key('mission-record-error')), findsNothing);
      await disposePage(tester);
    },
  );

  testWidgets(
    'record lookup opens catalog detail without a second detail request',
    (tester) async {
      size(tester, 1440);
      final port = RecordsPort(), catalog = RecordCatalog();
      await tester.pumpWidget(
        app(
          CatalogPage(
            kind: CatalogKind.missions,
            port: catalog,
            recordsPort: port,
          ),
        ),
      );
      await settle(tester);
      await tap(tester, const Key('mission-record-entry'));
      await tap(tester, Key('mission-record-row-$missionGuid'));
      expect(
        catalog.calls.where((r) => r.operation == 'missions.detail'),
        hasLength(1),
      );
      expect(find.byKey(const Key('catalog-detail')), findsOneWidget);
      expect(find.text('示意合约'), findsWidgets);
      await disposePage(tester);
      port.dispose();
    },
  );

  testWidgets('all sort controls change the visible row order locally', (
    tester,
  ) async {
    size(tester, 800);
    final port = RecordsPort();
    port.summary['groups'] = [
      record(key: 'a', code: 'A', count: 2, fastest: 800),
      record(
        key: 'b',
        code: 'B',
        count: 5,
        fastest: 400,
        date: '2026-11-08T00:00:00Z',
      ),
    ];
    final c = await controller(port), catalog = RecordCatalog();
    await tester.pumpWidget(
      app(MissionRecordsPage(controller: c, catalog: catalog, known: const [])),
    );
    await settle(tester);
    double y(String key) =>
        tester.getTopLeft(find.byKey(Key('mission-record-row-$key'))).dy;
    expect(y('b'), lessThan(y('a')));
    await tester.tap(find.byKey(const Key('mission-record-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近完成').last);
    await tester.pumpAndSettle();
    expect(y('a'), lessThan(y('b')));
    expect(catalog.calls, isEmpty);
    await disposePage(tester);
  });

  for (final reason in [
    'signedOut',
    'identityUnverified',
    'consentMissing',
    'localMode',
  ]) {
    testWidgets(
      'unavailable import $reason shows the exact reason and disabled button',
      (tester) async {
        final port = RecordsPort();
        port.summary.addAll({
          'importAvailable': false,
          'importUnavailableReason': reason,
        });
        final c = await controller(port);
        await tester.pumpWidget(app(MissionRecordsImport(c)));
        await settle(tester);
        final strings = AppStrings.resolve(const Locale('zh', 'CN'));
        expect(
          find.text(strings.text('missionRecords.$reason')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('mission-record-import')));
        await tester.pump();
        expect(port.calls, ['summary']);
        await disposePage(tester);
      },
    );
  }

  testWidgets('progress, cancel, and committed result racing cancellation', (
    tester,
  ) async {
    final port = RecordsPort(), c = await controller(port);
    await tester.pumpWidget(app(MissionRecordsImport(c)));
    await settle(tester);
    await tester.tap(find.byKey(const Key('mission-record-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('mission-record-scan')), findsOneWidget);
    expect(find.text('正在读取日志…'), findsOneWidget);
    expect(find.text('已读取 2 / 5 个文件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mission-record-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(port.calls, contains('importCancel'));
    expect(find.text('已取消导入。'), findsOneWidget);
    expect(find.byKey(const Key('mission-record-scan')), findsNothing);
    port.completeImport();
    await tester.tap(find.byKey(const Key('mission-record-import')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('扫描了 5 个日志文件，新增 4 次完成，3 次已经记过'), findsOneWidget);
    expect(find.textContaining('跳过 1 个（不是本账号的日志或读不了）'), findsOneWidget);
    expect(port.calls.where((r) => r == 'summary'), hasLength(2));
    await disposePage(tester);
  });

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('320 wide large text records, catalog and import in $locale', (
      tester,
    ) async {
      size(tester, 320);
      final port = RecordsPort(), c = await controller(port);
      final catalog = RecordCatalog();
      final strings = AppStrings.resolve(locale);
      await tester.pumpWidget(
        app(
          MissionRecordsPage(
            controller: c,
            catalog: catalog,
            known: const [missionSample],
          ),
          locale: locale,
          scale: 2,
        ),
      );
      await settle(tester);
      expect(
        find.text(locale.languageCode == 'en' ? 'Sample contract' : '示意合约'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('mission-record-import')),
      );
      await tester.tap(find.byKey(const Key('mission-record-import')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text(strings.text('missionRecords.scanning')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('mission-record-cancel')),
      );
      await tester.tap(find.byKey(const Key('mission-record-cancel')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      port.completeImport();
      await tester.ensureVisible(
        find.byKey(const Key('mission-record-import')),
      );
      await tester.tap(find.byKey(const Key('mission-record-import')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mission-record-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePage(tester);
      await tester.pumpWidget(
        app(
          CatalogPage(
            kind: CatalogKind.missions,
            port: catalog,
            recordsPort: port,
          ),
          locale: locale,
          scale: 2,
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      // At 320 wide and 2x text the row is taller than half the viewport and is
      // the last list item: let the scroll settle before tapping its centre.
      final row = find.byKey(Key('catalog-row-$missionGuid'));
      await reveal(tester, row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await settle(tester);
      // The detail view is a fresh lazy list under the (tall, 2x) page header.
      expect(find.byKey(const Key('catalog-detail-scroll')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('mission-record-details')));
      expect(find.byKey(const Key('mission-record-details')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePage(tester);
    });
  }

  testWidgets('empty records use helpful copy', (tester) async {
    final port = RecordsPort();
    port.summary['groups'] = [];
    final c = await controller(port);
    await tester.pumpWidget(
      app(
        MissionRecordsPage(
          controller: c,
          catalog: RecordCatalog(),
          known: const [],
        ),
      ),
    );
    await settle(tester);
    expect(find.text('还没有记录。完成合约后会自动记下，也可以从游戏日志导入。'), findsOneWidget);
    await disposePage(tester);
  });
}
