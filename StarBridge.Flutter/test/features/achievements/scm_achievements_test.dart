import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/achievements/achievement_presentation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_controller.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_sources.dart';
import 'package:starbridge_flutter/features/achievements/scm_achievement_wire.dart';
import 'package:starbridge_flutter/features/achievements/scm_holiday_art.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;

Map<String, Object?> row(int id, {bool owned = false}) => {
  'id': 'scm-$id',
  'name': 'SCM collection $id',
  'title': 'A title',
  'description': 'Original SCM description',
  'condition': 'Original SCM condition',
  'imageUrl': 'https://assets.example.invalid/achievement.png',
  'rarity': 'EPIC',
  'type': 'NORMAL',
  'unlocked': owned,
  'unlockedAtUtc': null,
  'currentValue': 1.25,
  'targetValue': 2.5,
};
Map<String, Object?> page(
  int offset, {
  int total = 129,
  String snapshot = 'one',
}) => {
  'schemaVersion': 1,
  'snapshotId': snapshot,
  'total': total,
  'offset': offset,
  'readAtUtc': '2026-10-01T00:00:00Z',
  'cachedAtUtc': null,
  'nextOffset': offset + 16 < total ? offset + 16 : null,
  'items': [
    for (var i = offset; i < total && i < offset + 16; i++)
      row(i + 1, owned: i == 0),
  ],
};
Future<AchievementCollection> read({
  Map<String, Object?>? first,
  Future<Map<String, Object?>> Function(int, String)? next,
}) => readScmAchievementPages(
  first ?? page(0),
  next ?? (offset, id) async => page(offset),
  generation: 1,
  cached: false,
);

void main() {
  test(
    'SCM Title is display name and description is not repeated title',
    () async {
      for (final title in ['登高望远', '', '  ', null]) {
        final result = await read(
          first: {
            ...page(0, total: 1),
            'items': [
              {...row(1), 'name': 'holiday_double_ninth', 'title': title},
            ],
          },
        );
        final p = AchievementPresentation(
          result.catalog.single,
          result,
          AppStrings.resolve(const Locale('zh', 'CN')),
        );
        expect(
          p.name,
          title == null || title.trim().isEmpty
              ? 'holiday_double_ninth'
              : '登高望远',
        );
        expect(p.memory, 'Original SCM description');
      }
    },
  );
  // SCM 的劳动节标题带了一个多余的“×”，清掉后名字和图都要对得上。
  test(
    'stray marks around the SCM title are removed for name and art',
    () async {
      for (final (raw, expected) in [
        ('×星际劳模', '星际劳模'),
        (' ✕ 星际劳模 ', '星际劳模'),
        ('星际劳模 ·', '星际劳模'),
        ('⚒星际劳模', '星际劳模'),
        ('⚒\uFE0F 星际劳模', '星际劳模'),
        ('登高望远', '登高望远'),
      ]) {
        final result = await read(
          first: {
            ...page(0, total: 1),
            'items': [
              {
                ...row(1),
                'name': 'holiday_labor',
                'title': raw,
                'type': 'HOLIDAY',
              },
            ],
          },
        );
        final definition = result.catalog.single;
        final p = AchievementPresentation(
          definition,
          result,
          AppStrings.resolve(const Locale('zh', 'CN')),
        );
        expect(p.name, expected, reason: raw);
        final art = scmAchievementArtAsset(
          definition,
          earned: false,
          logicalSize: 96,
          devicePixelRatio: 1,
        );
        // 登高望远 10-29 也有图了（重阳）。
        expect(
          art?.path,
          expected == '星际劳模'
              ? 'assets/achievements/scm-holiday-labor-day-locked-192.webp'
              : 'assets/achievements/scm-holiday-double-ninth-locked-192.webp',
          reason: raw,
        );
      }
      expect(scmDisplayTitle('×'), isNull);
      expect(scmDisplayTitle('⚒'), isNull);
      expect(scmDisplayTitle('   '), isNull);
    },
  );
  test('achievement text says sign in, not sign in to the website', () async {
    for (final (raw, expected) in [
      ('于春节期间登录网站', '于春节期间登录'),
      ('在重阳节登录网站，遍插茱萸', '在重阳节登录，遍插茱萸'),
      ('在万圣节登录网站，Trick or Treat!', '在万圣节登录，Trick or Treat!'),
      ('於春節期間登入網站', '於春節期間登入'),
      ('於春節期間登錄網站', '於春節期間登錄'),
      (
        'Log in to the website during Spring Festival',
        'Log in during Spring Festival',
      ),
      ('Sign in to the site on Halloween', 'Sign in on Halloween'),
      ('logged in to the website', 'logged in'),
      ('在网站完成交易', '在网站完成交易'),
      ('登录后访问网站', '登录后访问网站'),
      ('Original SCM description', 'Original SCM description'),
    ]) {
      expect(scmDisplayText(raw), expected, reason: raw);
    }
    final result = await read(
      first: {
        ...page(0, total: 1),
        'items': [
          {
            ...row(1),
            'type': 'HOLIDAY',
            'condition': '于春节期间登录网站',
            'description': '在重阳节登录网站，遍插茱萸',
          },
        ],
      },
    );
    final definition = result.catalog.single;
    expect(definition.serverCondition, '于春节期间登录');
    expect(definition.serverMemory, '在重阳节登录，遍插茱萸');
  });
  test(
    'SCM progress formats integral and fractional values only for display',
    () async {
      for (final values in [
        (64.0, 90.0, '64 / 90'),
        (1.0, 10.0, '1 / 10'),
        (1.25, 2.5, '1.2 / 2.5'),
        (2.3, 5.0, '2.3 / 5'),
        (9.96, 10.0, '9.9 / 10'),
      ]) {
        final result = await read(
          first: {
            ...page(0, total: 1),
            'items': [
              {...row(1), 'currentValue': values.$1, 'targetValue': values.$2},
            ],
          },
        );
        final p = AchievementPresentation(
          result.catalog.single,
          result,
          AppStrings.resolve(const Locale('zh', 'CN')),
        );
        expect(p.progressText, values.$3);
        expect(result.progressFor('scm-1'), values.$1);
      }
    },
  );
  test(
    'all pages preserve official copy, decimals and owned-without-date',
    () async {
      final result = await read();
      expect(result.catalog, hasLength(129));
      expect(result.catalog.last.id, 'scm-129');
      expect(result.catalog.first.serverName, 'A title');
      expect(result.catalog.first.rarity, AchievementRarity.epic);
      expect(result.catalog.first.isSeries, isFalse);
      expect(result.isEarned('scm-1'), isTrue);
      expect(result.dateFor('scm-1'), isNull);
      expect(result.progressFor('scm-1'), 1.25);
      expect(result.catalog.first.target, 2.5);
    },
  );
  test(
    'changed, duplicate, missing or malformed later pages fail as a whole',
    () async {
      for (final next in <Future<Map<String, Object?>> Function(int, String)>[
        (offset, id) async => page(offset, snapshot: 'other'),
        (offset, id) async => {
          ...page(offset),
          'items': [row(1), for (var n = 1; n < 16; n++) row(offset + n + 1)],
        },
        (offset, id) async => {...page(offset), 'items': []},
        (offset, id) async => {...page(offset), 'offset': 0},
      ]) {
        await expectLater(read(next: next), throwsFormatException);
      }
      await expectLater(
        read(next: (_, _) async => throw TimeoutException('synthetic')),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
  test(
    'unknown progress stays unknown and invalid source facts are rejected',
    () async {
      final first = page(0, total: 1);
      first['items'] = [
        {...row(1), 'currentValue': null, 'targetValue': null},
      ];
      final unknown = await read(first: first);
      expect(unknown.progressFor('scm-1'), isNull);
      for (final patch in [
        {'currentValue': -1},
        {'targetValue': 0},
        {'unlockedAtUtc': '2026-10-01T00:00:00Z'},
        {'imageUrl': 'http://assets.example.invalid/a.png'},
        {'rarity': 'I'},
      ]) {
        await expectLater(
          read(
            first: {
              ...first,
              'items': [
                {...row(1), ...patch},
              ],
            },
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('SCM refresh replaces revoked awards and decreasing progress, transient failures retain', () async {
    final account = ValueNotifier(achievementTestAccount(1));
    final port = DeferredAchievementPort();
    final controller = AchievementCollectionController(
      account: account,
      port: port,
      permanentMilestones: false,
    );
    addTearDown(controller.dispose);
    addTearDown(account.dispose);
    port.requests.last.completion.complete(await read());
    await Future<void>.delayed(Duration.zero);
    expect(controller.value.isEarned('scm-1'), isTrue);
    var refresh = controller.refresh();
    port.requests.last.completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        catalog: controller.value.catalog,
        progress: {'scm-1': 0.5},
      ),
    );
    await refresh;
    expect(controller.value.isEarned('scm-1'), isFalse);
    expect(controller.value.progressFor('scm-1'), 0.5);
    refresh = controller.refresh();
    port.requests.last.completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.unavailable,
        transientFailure: true,
      ),
    );
    await refresh;
    expect(controller.value.catalog, hasLength(129));
    expect(controller.value.refreshFailed, isTrue);
    refresh = controller.refresh();
    port.requests.last.completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.unavailable,
      ),
    );
    await refresh;
    expect(controller.value.isReady, isFalse);
    expect(controller.value.catalog, isEmpty);
  });
  test('one source never grants or erases the other source', () async {
    final scm = await read();
    final bridge = AchievementCollection(
      generation: 1,
      status: AchievementCollectionStatus.unavailable,
    );
    final combined = combineAchievementSources(bridge, scm, achievementCatalog);
    expect(combined.isEarned('scm-1'), isTrue);
    expect(combined.isConfirmed('first-entry'), isFalse);
    expect(combined.progressFor('hangar-home'), isNull);
    final bridgeReady = AchievementCollection(
      generation: 1,
      status: AchievementCollectionStatus.ready,
      earnedAt: {'first-entry': DateTime.utc(2026, 10, 1)},
    );
    expect(
      combineAchievementSources(
        bridgeReady,
        bridge,
        achievementCatalog,
      ).isEarned('first-entry'),
      isTrue,
    );
  });
}
