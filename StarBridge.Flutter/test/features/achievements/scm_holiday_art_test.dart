import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/scm_flat_svg.dart';
import 'package:starbridge_flutter/features/achievements/scm_holiday_art.dart';

AchievementDefinition holiday(
  String title, {
  AchievementSource source = AchievementSource.scm,
  String group = 'scm-HOLIDAY',
}) => AchievementDefinition(
  id: 'scm-999',
  nameKey: '',
  conditionKey: '',
  memoryKey: '',
  earnedAsset: '',
  lockedAsset: '',
  source: source,
  groupId: group,
  serverName: title,
);

const titles = [
  '新春快乐',
  '辞旧迎新',
  '花灯初上',
  '粽情端午',
  '鹊桥相会',
  '月圆人团圆',
  '腊八寒冬',
  '新年新气象',
  '星际有情人',
  '星际整蛊师',
  '星际劳模',
  '童心未泯',
  '星际鬼才',
  '星际圣诞',
  '登高望远',
  '国庆节',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all sixteen holidays have 192 and 512 images, earned and locked',
    () async {
      final paths = <String>{};
      for (final title in titles) {
        for (final earned in [true, false]) {
          for (final (logical, density, resolution) in [
            (64.0, 3.0, 192),
            (96.0, 2.0, 192),
            (100.0, 2.0, 512),
            (240.0, 3.0, 512),
          ]) {
            final art = scmAchievementArtAsset(
              holiday(title),
              earned: earned,
              logicalSize: logical,
              devicePixelRatio: density,
            )!;
            expect(art.vector, isFalse);
            final asset = art.path;
            expect(asset.contains('-locked-'), !earned);
            paths.add(asset);
            final bytes = await rootBundle.load(asset);
            if (resolution == 192) {
              // 10-29 补的重阳、国庆两张画面更满：彩色列表图约 10 KB，
              // 未解锁列表图是无损 WebP，约 20 KB。
              expect(
                bytes.lengthInBytes,
                lessThanOrEqualTo(earned ? 12288 : 24576),
              );
            }
            final codec = await ui.instantiateImageCodec(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
            final frame = await codec.getNextFrame();
            expect(frame.image.width, resolution);
            expect(frame.image.height, resolution);
            frame.image.dispose();
            codec.dispose();
          }
        }
      }
      expect(paths, hasLength(64));
    },
    skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'),
  );

  test(
    'same titles in other sources or categories do not acquire holiday artwork',
    () {
      for (final d in [
        holiday('新春快乐', source: AchievementSource.bridge),
        holiday('新春快乐', group: 'scm-NORMAL'),
        holiday('新春快乐', group: 'scm-HIDDEN'),
        holiday('新春快乐特别版'),
        holiday('未来节日'),
      ]) {
        expect(
          scmAchievementArtAsset(
            d,
            earned: true,
            logicalSize: 64,
            devicePixelRatio: 1,
          ),
          isNull,
        );
      }
    },
  );

  testWidgets(
    'owned holidays show colour art and unowned ones the paired locked art',
    (tester) async {
      final definition = holiday('新春快乐');
      for (final earned in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AchievementArt(
                definition: definition,
                earned: earned,
                size: 64,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(find.byType(Image));
        expect(
          (image.image as AssetImage).assetName,
          contains(
            earned
                ? 'scm-holiday-spring-festival-192.webp'
                : 'scm-holiday-spring-festival-locked-192.webp',
          ),
        );
        expect(definition.source, AchievementSource.scm);
        expect(tester.takeException(), isNull);
      }
    },
  );

  const daily = {
    '萌新启航': 'account-rookie',
    '中登': 'account-regular',
    '纵横星海': 'account-veteran',
    '攻略新手': 'guide-beginner',
    '攻略达人': 'guide-adept',
    '攻略大师': 'guide-master',
    '初涉商海': 'trade-beginner',
    '商业精英': 'trade-adept',
    '商业大亨': 'trade-master',
    '猎头帮': 'bounty-beginner',
    '猎头帮首脑': 'bounty-leader',
  };
  const limited = {
    '春节精英': 'spring-elite',
    '签到达人': 'checkin-streak',
    '春节欢庆': 'spring-participant',
  };

  test('daily and limited-event titles map to bundled flat SVGs', () async {
    final checks = [
      for (final state in ['', '-locked']) ...[
        for (final e in daily.entries)
          for (final group in ['scm-NORMAL', 'scm-SPECIAL'])
            (
              e.key,
              group,
              'assets/achievements/scm-daily-${e.value}$state.svg',
            ),
        for (final e in limited.entries)
          (
            e.key,
            'scm-EVENT_LIMITED',
            'assets/achievements/scm-event-${e.value}$state.svg',
          ),
      ],
    ];
    for (final (title, group, path) in checks) {
      final art = scmAchievementArtAsset(
        holiday(title, group: group),
        earned: !path.endsWith('-locked.svg'),
        logicalSize: 64,
        devicePixelRatio: 2,
      )!;
      expect(art.path, path);
      expect(art.vector, isTrue);
      final drawing = ScmFlatDrawing.parse(await rootBundle.loadString(path));
      expect(drawing, isNotNull, reason: path);
      expect(drawing!.extent, 256);
      expect(drawing.shapes, isNotEmpty);
    }
  }, skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'));

  test(
    'flat art never reaches hidden, other-category or other-source rows',
    () {
      for (final d in [
        holiday('萌新启航', group: 'scm-HIDDEN'),
        holiday('萌新启航', group: 'scm-HOLIDAY'),
        holiday('春节精英', group: 'scm-NORMAL'),
        holiday('春节精英', group: 'scm-HIDDEN'),
        holiday('萌新启航', source: AchievementSource.bridge, group: 'scm-NORMAL'),
        holiday('萌新启航二期', group: 'scm-NORMAL'),
      ]) {
        expect(
          scmAchievementArtAsset(
            d,
            earned: true,
            logicalSize: 64,
            devicePixelRatio: 1,
          ),
          isNull,
        );
      }
    },
  );

  test('flat SVG parser rejects anything outside the approved subset', () {
    const ok =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path fill="#081C2B" d="M0 0 256 0 256 256 0 256Z"/></svg>';
    expect(ScmFlatDrawing.parse(ok), isNotNull);
    for (final bad in [
      ok.replaceFirst('<path', '<image href="x.png"/><path'),
      ok.replaceFirst('0 256Z', '0 256 C1 2 3 4 5 6Z'),
      ok.replaceFirst('viewBox="0 0 256 256"', 'viewBox="0 0 256 128"'),
      ok.replaceFirst('Z"', '"'),
      ok.replaceFirst('M0 0 256 0 256 256 0 256Z', 'M0 0Z'),
    ]) {
      expect(ScmFlatDrawing.parse(bad), isNull, reason: bad);
    }
  });

  testWidgets('daily art paints a vector without changing the definition', (
    tester,
  ) async {
    final definition = holiday('商业大亨', group: 'scm-NORMAL');
    for (final earned in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementArt(
              definition: definition,
              earned: earned,
              size: 64,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => rootBundle.loadString(
          earned
              ? 'assets/achievements/scm-daily-trade-master.svg'
              : 'assets/achievements/scm-daily-trade-master-locked.svg',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScmFlatSvg), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ScmFlatSvg),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(definition.groupId, 'scm-NORMAL');
      expect(tester.takeException(), isNull);
    }
  }, skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'));
}
